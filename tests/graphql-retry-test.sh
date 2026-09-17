#!/usr/bin/env bash
# A GraphQL validation error (AppSignal renamed or removed a field inside the
# #opt-marked checkIns/alerts blocks) must not take down the whole overview:
# one retry with those lines stripped, degrading to "no check-ins, no
# alerts" instead of "no AppSignal". fixtures/graphql-error/graphql.json
# carries an `errors` array with graphql.status=400; graphql-retry.json is
# the second call's answer, and deliberately omits checkIns/alerts entirely
# to prove the transform's `// {}` / `// []` fallbacks hold up even then.

# shellcheck source=helper.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helper.sh"

echo "graphql retry (#opt stripped)"

out=$(run_collector graphql-error -limit 5)

assert_eq "0" "$(jq -e . <<<"$out" >/dev/null 2>&1; echo $?)" "the output is valid JSON"
assert_eq "true" "$(jq -r .ready <<<"$out")" "ready is true after the retry succeeds"
assert_eq "false" "$(jq -r .stale <<<"$out")" "stale is false"
assert_contains "$(jq -r .error <<<"$out")" "unavailable" "error says check-ins/alerts are unavailable"
assert_eq "0" "$(jq -r '.organizations[0].apps[0].checkIns | length' <<<"$out")" \
  "checkIns is an empty array, not missing or null"
assert_eq "0" "$(jq -r '.organizations[0].apps[0].alerts | length' <<<"$out")" \
  "alerts is an empty array, not missing or null"
assert_eq "Acme Web" "$(jq -r '.organizations[0].apps[0].name' <<<"$out")" \
  "the rest of the app (name) survived the retry"

finish
