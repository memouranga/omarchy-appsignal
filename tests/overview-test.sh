#!/usr/bin/env bash
# The "overview feliz" case: a full happy-path run against
# tests/fixtures/full/ (one org, two apps — one pinned with rich phase 1 +
# phase 2 data, one bare) and every field shape the panel (Main.qml/
# Panel.qml) actually reads.

# shellcheck source=tests/helper.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helper.sh"

echo "overview (happy path)"

out=$(run_collector full -limit 5)

assert_eq "0" "$(jq -e . <<<"$out" >/dev/null 2>&1; echo $?)" "the output is valid JSON"
assert_eq "1" "$(jq -r .schemaVersion <<<"$out")" "the schema version is declared"
assert_eq "true" "$(jq -r .ready <<<"$out")" "ready is true"
assert_eq "false" "$(jq -r .stale <<<"$out")" "stale is false"
assert_eq "" "$(jq -r .error <<<"$out")" "error is empty on a clean run"
assert_eq "0" "$(jq -r '.updatedAt | fromdateiso8601 | if . > 0 then 0 else 1 end' <<<"$out")" \
  "updatedAt is a parseable timestamp"
assert_eq "Dev Example" "$(jq -r .viewer.name <<<"$out")" "viewer name comes through"
assert_eq "dev@example.com" "$(jq -r .viewer.email <<<"$out")" "viewer email comes through"

assert_eq "1" "$(jq -r '.organizations | length' <<<"$out")" "one organization"
assert_eq "acme" "$(jq -r '.organizations[0].slug' <<<"$out")" "org slug"
assert_eq "2" "$(jq -r '.organizations[0].apps | length' <<<"$out")" "two apps"

app=$(jq -c '.organizations[0].apps[] | select(.id == "app0000000000000000000001")' <<<"$out")
assert_eq "Acme Web" "$(jq -r .name <<<"$app")" "pinned app name"
assert_eq "true" "$(jq -r .pinned <<<"$app")" "pinned app is marked pinned"
assert_eq "2" "$(jq -r '.errors | length' <<<"$app")" "two open errors"
assert_eq "2" "$(jq -r '.monitors | length' <<<"$app")" "two uptime monitors"
assert_eq "true" "$(jq -r '.monitors[] | select(.id == "mon0000000000000000000002") | .down' <<<"$app")" \
  "the monitor with an OPEN alert is down"
assert_eq "false" "$(jq -r '.monitors[] | select(.id == "mon0000000000000000000001") | .down' <<<"$app")" \
  "the monitor with no alerts is up"
assert_eq "2" "$(jq -r '.checkIns | length' <<<"$app")" "two check-ins"
assert_eq "true" "$(jq -r '.checkIns[] | select(.identifier == "hourly-sync") | .failing' <<<"$app")" \
  "a MISSED check-in is flagged failing"
assert_eq "false" "$(jq -r '.checkIns[] | select(.identifier == "nightly-backup") | .failing' <<<"$app")" \
  "an OK check-in is not flagged failing"
assert_eq "1" "$(jq -r '.alerts | length' <<<"$app")" "one open anomaly-detection alert"
assert_eq "High CPU" "$(jq -r '.alerts[0].triggerName' <<<"$app")" "the alert's trigger name comes through"

assert_json_eq \
  '{"throughput":1234,"errorRate":0.07,"meanMs":182.3,"window":"1h"}' \
  "$(jq -c .health <<<"$app")" \
  "health line: throughput/errorRate/meanMs pass through untouched (no ×100 on errorRate)"

assert_eq "abc1234" "$(jq -r '.lastDeploy.shortRevision' <<<"$app")" "last deploy revision"
assert_eq "4" "$(jq -r '.lastDeploy.exceptionCount' <<<"$app")" "last deploy exception count"

other=$(jq -c '.organizations[0].apps[] | select(.id == "app0000000000000000000002")' <<<"$out")
assert_eq "false" "$(jq -r .pinned <<<"$other")" "the non-pinned app is marked as such"
assert_eq "null" "$(jq -r '.health' <<<"$other")" "the non-pinned app was outside phase 2: health is null"
assert_eq "0" "$(jq -r '.hosts | length' <<<"$other")" "the non-pinned app has no host rows"
assert_eq "0" "$(jq -r '.queues | length' <<<"$other")" "the non-pinned app has no queue rows"

assert_json_eq \
  '{"apps":2,"errors":2,"perf":0,"monitors":2,"monitorsDown":1,"checkIns":2,"checkInsFailing":1,"alertsOpen":1,"hostsWarn":1,"queuesWarn":2}' \
  "$(jq -c .totals <<<"$out")" \
  "global totals are the sum across both apps"

finish
