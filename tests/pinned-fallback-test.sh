#!/usr/bin/env bash
# When no app is pinned in AppSignal, the collector's phase 2 (metrics)
# request falls back to the first MAX_PHASE2_APPS apps overall instead of
# fetching none — the collector-side half of the "onlyPinned sin apps
# fijadas" rule (the panel-side half, showing every app instead of an empty
# list, lives in Main.qml's pinnedFallback and isn't bash-testable here).
# fixtures/nopinned/ has two apps, neither pinned, each with a distinct
# health fixture so both being present proves both were fetched.

# shellcheck source=helper.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helper.sh"

echo "phase 2 fallback: no app pinned"

out=$(run_collector nopinned -limit 5)

a1=$(jq -c '.organizations[0].apps[] | select(.id == "app0000000000000000000001")' <<<"$out")
a2=$(jq -c '.organizations[0].apps[] | select(.id == "app0000000000000000000002")' <<<"$out")

assert_eq "false" "$(jq -r .pinned <<<"$a1")" "neither app is pinned"
assert_eq "111" "$(jq -r '.health.throughput' <<<"$a1")" "the first app still got its phase 2 health fetched"
assert_eq "222" "$(jq -r '.health.throughput' <<<"$a2")" "...and so did the second, proving the fallback covers all of them"

finish
