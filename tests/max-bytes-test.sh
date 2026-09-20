#!/usr/bin/env bash
# v1.0.1 (marketplace security review): no response may be written to disk
# without a ceiling. The collector asks curl for --max-filesize on every
# request and re-checks the body that landed before jq ever opens it; fixture
# mode goes through that same check, which is what lets this test drive the
# rejection path with no network.
#
# Covered here: an oversized phase 1 (GraphQL) body with and without a
# previous overview to fall back on, an oversized phase 2 (metrics) body, a
# body that is over the *default* 8 MiB ceiling rather than a test-sized one,
# and the normal case staying green.

set -uo pipefail

# shellcheck source=tests/helper.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/helper.sh"

printf 'response byte ceiling\n'

# A scenario built on the fly, so an oversized fixture never has to be
# committed to the repository.
scenario() {
  local name=$1 dir
  dir="$WORK/fx/$name"
  mkdir -p "$dir"
  cp "$FIXTURES_DIR"/full/* "$dir"/
  printf '%s' "$dir"
}

run_fx() {
  local dir=$1; shift
  APPSIGNAL_FIXTURE_DIR="$dir" APPSIGNAL_API_TOKEN="test-fixture-token" \
    HOME="$WORK/home" XDG_STATE_HOME="$WORK/state" \
    "$COLLECTOR" "$@"
}

# ---------------------------------------------------------------- baseline
base=$(scenario baseline)
out=$(run_fx "$base" -max-response-bytes 1048576)
assert_eq "true" "$(jq -r '.ready' <<<"$out")" "a normal run is unaffected by the ceiling"
assert_eq "" "$(jq -r '.error' <<<"$out")" "and reports no error"

# ------------------------------------------------- phase 1 over the ceiling
big=$(scenario phase1-big)
# ~64 KB of padding inside a still-valid JSON document: the point is the size
# of the body, not its shape — the collector must reject it before parsing.
jq --arg pad "$(head -c 65536 /dev/zero | tr '\0' 'x')" '. + {pad: $pad}' \
  "$FIXTURES_DIR/full/graphql.json" > "$big/graphql.json"

out=$(run_fx "$big" -max-response-bytes 8192)
assert_eq "false" "$(jq -r '.ready' <<<"$out")" "an oversized GraphQL body is not ready"
assert_eq "false" "$(jq -r '.stale' <<<"$out")" "and not stale when there is nothing to keep"
assert_contains "$(jq -r '.error' <<<"$out")" "8192-byte response limit" \
  "the error names the limit that was hit"
assert_eq "0" "$(jq -r '.organizations | length' <<<"$out")" "no data survived from the oversized body"

# Same, but with a good overview already on disk: the panel keeps showing it,
# marked stale, exactly like any other transient failure.
prev="$WORK/state/overview.json"
run_fx "$base" -output "$prev" >/dev/null
assert_eq "true" "$(jq -r '.ready' "$prev")" "the previous overview starts out ready"
run_fx "$big" -output "$prev" -max-response-bytes 8192
assert_eq "true" "$(jq -r '.ready' "$prev")" "an oversized refresh keeps the previous overview"
assert_eq "true" "$(jq -r '.stale' "$prev")" "and marks it stale"
assert_contains "$(jq -r '.error' "$prev")" "response limit" "and says why"

# ------------------------------------------------- phase 2 over the ceiling
# The metrics responses are much smaller than the GraphQL one, so a ceiling
# between the two sizes isolates a phase 2 overflow: phase 1 goes through,
# the metrics body is thrown away, and the panel still gets a usable overview
# with an error line explaining the gap.
p2=$(scenario phase2-big)
jq --arg pad "$(head -c 65536 /dev/zero | tr '\0' 'x')" '. + {pad: $pad}' \
  "$FIXTURES_DIR/full/jobs-app0000000000000000000001.json" \
  > "$p2/jobs-app0000000000000000000001.json"

out=$(run_fx "$p2" -max-response-bytes 32768)
assert_eq "true" "$(jq -r '.ready' <<<"$out")" "an oversized metrics body does not sink the overview"
assert_contains "$(jq -r '.error' <<<"$out")" "32768-byte limit" \
  "the panel is told a metrics response was discarded"
assert_eq "0" "$(jq -r '[.organizations[].apps[].queues[]] | length' <<<"$out")" \
  "the queues of the discarded response are empty"
assert_eq "true" "$(jq -r '[.organizations[].apps[].hosts[]] | length > 0' <<<"$out")" \
  "sections whose responses fit are still populated"

# ------------------------------------------------- the default 8 MiB ceiling
# No -max-response-bytes flag here: this is the shipped default rejecting a
# genuinely large body, the case a compromised endpoint would produce.
huge=$(scenario default-ceiling)
{ printf '{"pad":"'; head -c 9000000 /dev/zero | tr '\0' 'x'; printf '"}'; } > "$huge/graphql.json"
assert_eq "1" "$(( $(wc -c < "$huge/graphql.json") > 8388608 ))" \
  "the test body really is over 8 MiB"

out=$(run_fx "$huge")
assert_eq "false" "$(jq -r '.ready' <<<"$out")" "the default ceiling rejects a 9 MB body"
assert_contains "$(jq -r '.error' <<<"$out")" "8388608-byte response limit" \
  "and the default limit is the one reported"

finish
