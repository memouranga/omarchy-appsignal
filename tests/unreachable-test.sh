#!/usr/bin/env bash
# AppSignal unreachable (no network, DNS failure, connection refused).
#
# curl still prints its %{http_code} — "000" — when it never got a response,
# and it exits non-zero at the same time. A `|| echo 000` after it therefore
# put a SECOND "000" on run_query's stdout and the caller read "000000", which
# matched neither the unreachable branch nor 200: the panel showed the
# baffling "AppSignal returned HTTP 000000." instead of curl's own reason.
#
# No network here either: a curl stub that behaves exactly like the real one
# on a failed connection goes first on PATH, ahead of tests/run.sh's own
# loud-failure stub.

# shellcheck source=tests/helper.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helper.sh"

echo "appsignal unreachable"

stub_bin="$WORK/bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/curl" <<'STUB'
#!/usr/bin/env bash
# Mimics curl -w '%{http_code}' failing to connect: "000" on stdout, the
# reason on stderr, exit 7.
printf '000'
printf 'curl: (7) Failed to connect to appsignal.test port 443: Could not connect to server\n' >&2
exit 7
STUB
chmod +x "$stub_bin/curl"

run_collector_unreachable() {
  PATH="$stub_bin:$PATH" APPSIGNAL_API_TOKEN="test-fixture-token" \
    HOME="$WORK/home" XDG_STATE_HOME="$WORK/state" \
    "$COLLECTOR" "$@"
}

out=$(run_collector_unreachable -limit 5)

assert_eq "0" "$(jq -e . <<<"$out" >/dev/null 2>&1; echo $?)" "the output is valid JSON"
assert_eq "false" "$(jq -r .ready <<<"$out")" "ready is false"
assert_eq "false" "$(jq -r .stale <<<"$out")" "stale is false with no previous overview to keep"
assert_contains "$(jq -r .error <<<"$out")" "AppSignal unreachable" "error says AppSignal is unreachable"
assert_contains "$(jq -r .error <<<"$out")" "curl: (7)" "error carries curl's own reason"

if [[ $(jq -r .error <<<"$out") == *"000000"* ]]; then
  fail "the HTTP code is not doubled" "error still reports HTTP 000000"
else
  ok "the HTTP code is not doubled"
fi

# Same failure on a machine that already has a good overview: keep it and mark
# it stale rather than blanking the panel.
previous="$WORK/previous.json"
run_collector full -limit 5 -output "$previous"
assert_eq "true" "$(jq -r .ready "$previous")" "the previous overview starts out ready"

run_collector_unreachable -limit 5 -output "$previous"
assert_eq "true" "$(jq -r .ready "$previous")" "an unreachable refresh keeps the previous overview"
assert_eq "true" "$(jq -r .stale "$previous")" "and marks it stale"
assert_contains "$(jq -r .error "$previous")" "AppSignal unreachable" "and says why"

finish
