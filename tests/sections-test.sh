#!/usr/bin/env bash
# v0.7: the `sections` setting reaches the collector as -sections, and a
# section that's off skips its phase 2 request bucket entirely (performance:
# health+slow; servers: hosts; jobs: queues). fixtures/full/ has valid,
# non-empty fixtures for all three; running with them excluded from
# -sections and getting empty results back proves the request was actually
# skipped, not just coincidentally empty.

# shellcheck source=helper.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helper.sh"

echo "sections: off skips the phase 2 request"

full=$(run_collector full -limit 5 -sections "alerts,errors,performance,servers,uptime,jobs,checkins,deploy")
app_full=$(jq -c '.organizations[0].apps[] | select(.id == "app0000000000000000000001")' <<<"$full")
assert_eq "false" "$(jq -r '.health == null' <<<"$app_full")" "with every section on, health is populated"
assert_eq "3" "$(jq -r '.slowWeb | length' <<<"$app_full")" "...and slowWeb"
assert_eq "1" "$(jq -r '.hosts | length' <<<"$app_full")" "...and hosts"
assert_eq "5" "$(jq -r '.queues | length' <<<"$app_full")" "...and queues"

narrowed=$(run_collector full -limit 5 -sections "alerts,errors,uptime,checkins,deploy")
app_narrow=$(jq -c '.organizations[0].apps[] | select(.id == "app0000000000000000000001")' <<<"$narrowed")
assert_eq "true" "$(jq -r .ready <<<"$narrowed")" "ready is still true: phase 1 is unaffected by -sections"
assert_eq "true" "$(jq -r '.health == null' <<<"$app_narrow")" \
  "performance off: health is null even though the fixture exists and is valid"
assert_eq "0" "$(jq -r '.slowWeb | length' <<<"$app_narrow")" "...slowWeb is empty"
assert_eq "0" "$(jq -r '.hosts | length' <<<"$app_narrow")" "servers off: hosts is empty despite a valid fixture"
assert_eq "0" "$(jq -r '.queues | length' <<<"$app_narrow")" "jobs off: queues is empty despite a valid fixture"
# Fields sections never gates (they're one cheap phase 1 field, not a phase 2
# request) must be unaffected.
assert_eq "2" "$(jq -r '.errors | length' <<<"$app_narrow")" "errors (always on here) is untouched"

# An empty/garbage -sections falls back to "every section", matching
# Main.qml's sectionOrder fallback — the collector must never end up
# requesting nothing because of a malformed setting.
fallback=$(run_collector full -limit 5 -sections "")
app_fallback=$(jq -c '.organizations[0].apps[] | select(.id == "app0000000000000000000001")' <<<"$fallback")
assert_eq "1" "$(jq -r '.hosts | length' <<<"$app_fallback")" "an empty -sections falls back to every section on"

finish
