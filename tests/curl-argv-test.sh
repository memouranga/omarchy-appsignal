#!/usr/bin/env bash
# v1.0.1 (marketplace security review): the API token must never appear in a
# curl command line, because every process on the machine can read those
# (`ps -o args=`, `pgrep -af curl`, /proc/<pid>/cmdline) and a URL that
# carries a credential can also end up in proxy and access logs.
#
# This test does NOT use fixture mode: it lets the collector take its real
# curl path, with a stub `curl` first on PATH that records exactly what it
# was invoked with — its argv and the configuration it was handed on stdin —
# and then answers from a canned body. Nothing touches the network.
#
# It asserts both halves of the fix: the token is absent from argv, and it is
# present in the stdin configuration, which is the channel that replaced it.

set -uo pipefail

# shellcheck source=tests/helper.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helper.sh"

printf 'token never reaches curl argv\n'

readonly FAKE_TOKEN="nOtArEaLtOkEn00000000000000000000deadbeef"

stub_bin="$WORK/stub-bin"
mkdir -p "$stub_bin"
export CURL_ARGV_LOG="$WORK/curl-argv.log"
export CURL_CONFIG_LOG="$WORK/curl-config.log"
export CURL_BODY="$FIXTURES_DIR/full/graphql.json"
: > "$CURL_ARGV_LOG"
: > "$CURL_CONFIG_LOG"

cat > "$stub_bin/curl" <<'STUB'
#!/usr/bin/env bash
# Stand-in for curl. Records the argv it was called with and the config it
# read on stdin, then serves $CURL_BODY at the path the config asked for.
printf '%s\n' "$*" >> "$CURL_ARGV_LOG"
cfg=$(cat)
printf '%s\n' "$cfg" >> "$CURL_CONFIG_LOG"
out=$(printf '%s\n' "$cfg" | sed -n 's/^output = "\(.*\)"$/\1/p' | tail -n1)
[[ -n $out && -f ${CURL_BODY:-} ]] && cp "$CURL_BODY" "$out"
printf '200'
STUB
chmod +x "$stub_bin/curl"

out=$(PATH="$stub_bin:$PATH" APPSIGNAL_API_TOKEN="$FAKE_TOKEN" \
  HOME="$WORK/home" XDG_STATE_HOME="$WORK/state" \
  "$COLLECTOR" 2>"$WORK/collect.err")

argv=$(cat "$CURL_ARGV_LOG")
config=$(cat "$CURL_CONFIG_LOG")

if [[ -s $CURL_ARGV_LOG ]]; then
  ok "the collector really did call curl ($(wc -l < "$CURL_ARGV_LOG") times)"
else
  fail "the collector really did call curl" "nothing was recorded"
fi

if [[ $argv == *"$FAKE_TOKEN"* ]]; then
  fail "the token is absent from every curl argv" "argv: $argv"
else
  ok "the token is absent from every curl argv"
fi

if [[ $argv == *"token="* || $argv == *"Authorization"* ]]; then
  fail "no credential-shaped argument at all in argv" "argv: $argv"
else
  ok "no credential-shaped argument at all in argv"
fi

assert_contains "$argv" "-K -" "every call reads its configuration from stdin (-K -)"

if [[ $config == *"$FAKE_TOKEN"* ]]; then
  ok "the token travels in the stdin configuration instead"
else
  fail "the token travels in the stdin configuration instead" "no token in the config curl received"
fi

# The GraphQL call is the one that has to keep ?token= in the URL (AppSignal
# accepts no header there), so it must be inside the config, never in argv.
if [[ $config == *"url = \"https://appsignal.com/graphql?token=$FAKE_TOKEN\""* ]]; then
  ok "the GraphQL token sits in the config's url line, not on the command line"
else
  fail "the GraphQL token sits in the config's url line, not on the command line"
fi

if [[ $config == *"header = \"Authorization: Bearer $FAKE_TOKEN\""* ]]; then
  ok "the metrics API gets its Bearer header through the config too"
else
  fail "the metrics API gets its Bearer header through the config too"
fi

# The byte ceiling rides along on every request.
assert_contains "$config" "max-filesize = " "every request carries a --max-filesize ceiling"

assert_eq "true" "$(printf '%s' "$out" | jq -r '.ready')" "the run still produced a ready overview"

finish
