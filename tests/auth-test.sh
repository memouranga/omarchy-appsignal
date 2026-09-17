#!/usr/bin/env bash
# HTTP 401 from AppSignal (a rejected token) must be treated as a
# configuration problem, not a transient one: no "stale, keep the old data"
# fallback, and it must not retry the #opt-stripped query either (that retry
# is only for a GraphQL validation error on 200/400/422 — see bin/
# appsignal-collect's own comment on gql_failed/run_query).

source "$(dirname -- "${BASH_SOURCE[0]}")/helper.sh"

echo "401"

out=$(run_collector auth-401 -limit 5)

assert_eq "0" "$(jq -e . <<<"$out" >/dev/null 2>&1; echo $?)" "the output is valid JSON"
assert_eq "false" "$(jq -r .ready <<<"$out")" "ready is false"
assert_eq "false" "$(jq -r .stale <<<"$out")" "stale is false"
assert_contains "$(jq -r .authHelpText <<<"$out")" "HTTP 401" "authHelpText names the HTTP status"
assert_contains "$(jq -r .authHelpText <<<"$out")" "rejected the token" "authHelpText says the token was rejected"

finish
