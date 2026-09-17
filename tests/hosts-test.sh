#!/usr/bin/env bash
# v0.5: per-host metrics. fixtures/full/hosts-hm-app...001.json deliberately
# has no "total" row for memory (real hosts never publish one — see
# SPEC.md "v0.5"), so memPct must come back null and memUsedMb must carry
# the absolute figure instead; swap does have a total row, so swapPct must
# be a real percentage. Also checks the cpu/disk warn thresholds.

source "$(dirname -- "${BASH_SOURCE[0]}")/helper.sh"

echo "servers: host metrics"

out=$(run_collector full -limit 5 -cpu-warn 80 -mem-warn 85 -disk-warn 85)
host=$(jq -c '.organizations[0].apps[] | select(.id == "app0000000000000000000001") | .hosts[0]' <<<"$out")

assert_eq "10.0.0.1-abc123def456" "$(jq -r .hostname <<<"$host")" "hostname"
assert_eq "10.0.0.1" "$(jq -r .shortName <<<"$host")" "shortName strips the trailing -<container id>"
assert_eq "91.5" "$(jq -r .cpuPct <<<"$host")" "cpu percent"
assert_eq "null" "$(jq -r .memPct <<<"$host")" "memPct is null: no memory 'total' row in this fixture"
assert_eq "512" "$(jq -r .memUsedMb <<<"$host")" "memUsedMb carries the absolute figure instead"
assert_eq "25" "$(jq -r .swapPct <<<"$host")" "swapPct is a real percentage: this fixture does have a swap total"
assert_eq "128" "$(jq -r .swapUsedMb <<<"$host")" "swapUsedMb"
assert_eq "92" "$(jq -r .diskPct <<<"$host")" "diskPct is the fullest mountpoint"
assert_eq "/" "$(jq -r .diskMount <<<"$host")" "diskMount names it"
assert_eq "2.5" "$(jq -r .load1 <<<"$host")" "load1"
assert_eq "true" "$(jq -r .warn <<<"$host")" "warn: cpu 91.5 >= 80 and disk 92 >= 85"

# Thresholds are forwarded from the CLI, not hardcoded: raise them past this
# host's numbers and warn must clear.
out2=$(run_collector full -limit 5 -cpu-warn 99 -mem-warn 99 -disk-warn 99)
host2=$(jq -c '.organizations[0].apps[] | select(.id == "app0000000000000000000001") | .hosts[0]' <<<"$out2")
assert_eq "false" "$(jq -r .warn <<<"$host2")" "warn clears once the thresholds are raised above this host's numbers"

finish
