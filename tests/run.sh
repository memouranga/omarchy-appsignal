#!/usr/bin/env bash
# Run every test file. No network and no credentials are required — fixture
# mode (APPSIGNAL_FIXTURE_DIR) replaces every curl call, and as a second,
# independent guard this also puts a stub `curl` first on PATH that fails
# loudly and records that it was called. If any test ever reaches a real
# curl invocation (a bug in fixture mode, or a scenario that forgot to set
# APPSIGNAL_FIXTURE_DIR), that shows up as a hard failure here instead of a
# silent pass or, worse, a real network request.
#
# For an even stronger guarantee, run this under a network namespace when
# available: `unshare -rn tests/run.sh`.

set -uo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1

stub_dir=$(mktemp -d)
trap 'rm -rf "$stub_dir"' EXIT
curl_marker="$stub_dir/.curl-was-called"
cat > "$stub_dir/curl" <<SCRIPT
#!/usr/bin/env bash
printf '%s\n' "\$0 \$*" >> "$curl_marker"
exit 1
SCRIPT
chmod +x "$stub_dir/curl"
export PATH="$stub_dir:$PATH"

failed=0
for test in *-test.sh; do
  ./"$test" || failed=1
  echo
done

if [[ -f $curl_marker ]]; then
  printf '%s: curl was invoked during tests — no test should touch the network:\n' "$(printf '\033[31mFAILED\033[0m')"
  cat "$curl_marker"
  failed=1
fi

if ((failed)); then
  printf '\033[31mFAILED\033[0m\n'
  exit 1
fi
printf '\033[32mAll suites passed\033[0m\n'
