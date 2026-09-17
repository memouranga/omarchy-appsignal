#!/usr/bin/env bash
# v0.4.1: slow actions are ranked by impact (totalMs = meanMs * count), not
# by mean alone, split into slowWeb/slowBackground, each capped at
# floor(limit/2)+1 rows. fixtures/full/slow-app...001.json has, per
# namespace, one high-count/low-mean row that should outrank a low-count/
# high-mean row, plus a fourth, lowest-impact row that should be cut off.

source "$(dirname -- "${BASH_SOURCE[0]}")/helper.sh"

echo "performance: impact ranking (web/background)"

out=$(run_collector full -limit 5)
app=$(jq -c '.organizations[0].apps[] | select(.id == "app0000000000000000000001")' <<<"$out")

assert_eq "0" "$(jq -r '.perf | length' <<<"$app")" "no open performance incidents (so the fallback ranking applies)"
assert_eq "3" "$(jq -r '.slowWeb | length' <<<"$app")" "web ranking capped at floor(5/2)+1 = 3 rows"
assert_eq "3" "$(jq -r '.slowBackground | length' <<<"$app")" "background ranking capped at 3 rows too"

assert_eq "ProfilesController#current_topics" "$(jq -r '.slowWeb[0].action' <<<"$app")" \
  "highest-impact web action wins despite a low mean (4ms × 69397 beats 87ms × 265)"
assert_eq "ProfilesController#show" "$(jq -r '.slowWeb[1].action' <<<"$app")" "second web action by impact"
assert_eq "null" "$(jq -r '[.slowWeb[].action] | index("TinyController#ping")' <<<"$app")" \
  "the lowest-impact web action (100ms total) did not make the cut"

assert_eq "Job::Mailer#deliver" "$(jq -r '.slowBackground[0].action' <<<"$app")" \
  "highest-impact background action wins (50ms × 5000 beats 20000ms × 1)"
assert_eq "Job::Cleanup#run" "$(jq -r '.slowBackground[1].action' <<<"$app")" "second background action by impact"
assert_eq "null" "$(jq -r '[.slowBackground[].action] | index("Job::Low#run")' <<<"$app")" \
  "the lowest-impact background action (1ms total) did not make the cut"

assert_eq "277588" "$(jq -r '.slowWeb[0].totalMs' <<<"$app")" "totalMs is meanMs × count"

finish
