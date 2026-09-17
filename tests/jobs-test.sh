#!/usr/bin/env bash
# v0.6: background job queues. fixtures/full/jobs-app...001.json has five
# queues covering every rule in SPEC.md "v0.6": a real backlog (warn), a
# queue whose wait is long only because its jobs are scheduled for later
# (never warns even though the number is huge), a queue with failed jobs
# (always warns), a healthy queue, and one meant to be dropped by
# ignoreQueues.

# shellcheck source=helper.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helper.sh"

echo "jobs: queues"

out=$(run_collector full -limit 5 -queue-time-warn 30000)
queues=$(jq -c '.organizations[0].apps[] | select(.id == "app0000000000000000000001") | .queues' <<<"$out")

assert_eq "5" "$(jq -r 'length' <<<"$queues")" "all five queues are present (no ignoreQueues set)"

critical=$(jq -c '.[] | select(.name == "critical")' <<<"$queues")
assert_eq "true" "$(jq -r .warn <<<"$critical")" "a queue with failed jobs always warns"
assert_eq "80" "$(jq -r .queueTimeMs <<<"$critical")" "queueTimeMs is the MEAN/MIN figure (the quietest minute), not an average"
assert_eq "false" "$(jq -r .scheduled <<<"$critical")" "not scheduled: its wait is milliseconds"

mailers=$(jq -c '.[] | select(.name == "mailers")' <<<"$queues")
assert_eq "true" "$(jq -r .scheduled <<<"$mailers")" \
  "a queue whose floor wait is hours is scheduled work, not a backlog"
assert_eq "false" "$(jq -r .warn <<<"$mailers")" \
  "a scheduled queue never warns even though its raw wait is huge"

low=$(jq -c '.[] | select(.name == "low_priority")' <<<"$queues")
assert_eq "true" "$(jq -r .warn <<<"$low")" "a real backlog (45s >= the 30s threshold, and not scheduled) warns"
assert_eq "false" "$(jq -r .scheduled <<<"$low")" "...but is not flagged scheduled"

default=$(jq -c '.[] | select(.name == "default")' <<<"$queues")
assert_eq "false" "$(jq -r .warn <<<"$default")" "a healthy queue (15s < 30s threshold) does not warn"

# ignoreQueues drops a queue entirely, not just its warning.
filtered=$(run_collector full -limit 5 -ignore-queues "ignored_queue, mailers")
fqueues=$(jq -c '.organizations[0].apps[] | select(.id == "app0000000000000000000001") | .queues' <<<"$filtered")
assert_eq "3" "$(jq -r 'length' <<<"$fqueues")" "ignoreQueues drops the named queues entirely"
assert_eq "null" "$(jq -r '[.[].name] | index("ignored_queue")' <<<"$fqueues")" "ignored_queue is gone"
assert_eq "null" "$(jq -r '[.[].name] | index("mailers")' <<<"$fqueues")" "mailers is gone too (comma-separated list, trimmed)"

finish
