#!/usr/bin/env bash
# fixtures/phase2-down/ has a valid phase 1 GraphQL response (one pinned app)
# but no health/slow/hosts/jobs fixtures at all for that app id, so every
# phase 2 request comes back as if curl could not connect (fixture_fetch's
# "missing body -> status 000" default). One app's phase 2 failing must
# never take the whole overview down: ready stays true, and that app's
# phase-2-only fields degrade to null/[] instead of erroring.

# shellcheck source=helper.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helper.sh"

echo "phase 2 down"

out=$(run_collector phase2-down -limit 5)
app=$(jq -c '.organizations[0].apps[0]' <<<"$out")

assert_eq "true" "$(jq -r .ready <<<"$out")" "ready is true: phase 1 succeeded on its own"
assert_eq "false" "$(jq -r .stale <<<"$out")" "stale is false"
assert_eq "1" "$(jq -r '.errors | length' <<<"$app")" "phase 1 data (errors) is intact"
assert_eq "null" "$(jq -r .health <<<"$app")" "health is null"
assert_json_eq '{"slowWeb":[],"slowBackground":[],"slowActions":[]}' \
  "$(jq -c '{slowWeb, slowBackground, slowActions}' <<<"$app")" \
  "slow-action lists are empty arrays, not null or missing"
assert_eq "0" "$(jq -r '.hosts | length' <<<"$app")" "hosts is an empty array"
assert_eq "0" "$(jq -r '.queues | length' <<<"$app")" "queues is an empty array"
assert_eq "0" "$(jq -r '.totals.hostsWarn' <<<"$app")" "hostsWarn is 0, not missing"
assert_eq "0" "$(jq -r '.totals.queuesWarn' <<<"$app")" "queuesWarn is 0, not missing"

finish
