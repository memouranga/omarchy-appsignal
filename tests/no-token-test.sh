#!/usr/bin/env bash
# No credential anywhere: $APPSIGNAL_API_TOKEN unset, $APPSIGNAL_TOKEN_FILE
# unset, and no ~/.config/appsignal/api_token in the scratch HOME. The
# collector must say so and stop before ever looking at the network (or, in
# this suite, at APPSIGNAL_FIXTURE_DIR — deliberately not set here).

# shellcheck source=tests/helper.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helper.sh"

echo "no token"

out=$(run_collector_no_token -limit 5)

assert_eq "0" "$(jq -e . <<<"$out" >/dev/null 2>&1; echo $?)" "the output is valid JSON"
assert_eq "1" "$(jq -r .schemaVersion <<<"$out")" "the schema version is declared"
assert_eq "false" "$(jq -r .ready <<<"$out")" "ready is false"
assert_eq "false" "$(jq -r .stale <<<"$out")" "stale is false (missing token is config, not a transient failure)"
assert_contains "$(jq -r .authHelpText <<<"$out")" "AppSignal token" "authHelpText explains what's missing"
assert_contains "$(jq -r .authHelpText <<<"$out")" "appsignal.com/users/edit" "authHelpText names where to create one"
assert_eq "" "$(jq -r .error <<<"$out")" "error is empty (this isn't a failure)"
assert_eq "0" "$(jq -r '.organizations | length' <<<"$out")" "no organizations are reported"

finish
