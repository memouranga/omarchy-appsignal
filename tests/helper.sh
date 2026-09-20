#!/usr/bin/env bash
# Shared assertions and fixture-mode helpers for the memong.appsignal test
# suite. Every test file sources this, calls assertions, and ends with
# finish. No test here ever touches the network: the collector's
# APPSIGNAL_FIXTURE_DIR mode (see bin/appsignal-collect's "fixture mode for
# tests/" comment) replaces every curl call with a read from a canned JSON
# fixture under tests/fixtures/<scenario>/.

set -uo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly PLUGIN_DIR
readonly COLLECTOR="$PLUGIN_DIR/bin/appsignal-collect"
readonly FIXTURES_DIR="$PLUGIN_DIR/tests/fixtures"

pass_count=0
fail_count=0

red() { printf '\033[31m%s\033[0m' "$1"; }
green() { printf '\033[32m%s\033[0m' "$1"; }

ok() {
  pass_count=$((pass_count + 1))
  printf '  %s %s\n' "$(green ok)" "$1"
}

fail() {
  fail_count=$((fail_count + 1))
  printf '  %s %s\n' "$(red FAIL)" "$1"
  [[ $# -gt 1 ]] && printf '       %s\n' "${@:2}"
}

assert_eq() {
  local expected=$1 actual=$2 label=$3
  if [[ $expected == "$actual" ]]; then
    ok "$label"
  else
    fail "$label" "expected: $expected" "actual:   $actual"
  fi
}

assert_json_eq() {
  local expected actual label=$3
  expected=$(printf '%s' "$1" | jq -S -c . 2>/dev/null)
  actual=$(printf '%s' "$2" | jq -S -c . 2>/dev/null)
  assert_eq "$expected" "$actual" "$label"
}

assert_contains() {
  local haystack=$1 needle=$2 label=$3
  if [[ $haystack == *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label" "expected to contain: $needle" "actual: $haystack"
  fi
}

# Runs the collector against tests/fixtures/$scenario, with a dummy token (no
# real credential is ever read: APPSIGNAL_API_TOKEN is set explicitly here)
# and a clean HOME/XDG_STATE_HOME so nothing brushes against Memo's real
# ~/.local/state/omarchy/appsignal/. Extra args are passed straight to the
# collector, e.g. run_collector full -limit 5 -sections "alerts,errors".
run_collector() {
  local scenario=$1; shift
  APPSIGNAL_FIXTURE_DIR="$FIXTURES_DIR/$scenario" \
    APPSIGNAL_API_TOKEN="test-fixture-token" \
    HOME="$WORK/home" XDG_STATE_HOME="$WORK/state" \
    "$COLLECTOR" "$@"
}

# Same, but with no fixture dir and no token anywhere — the "no credential"
# path, which must return before ever looking at APPSIGNAL_FIXTURE_DIR.
run_collector_no_token() {
  env -i HOME="$WORK/home" PATH="$PATH" XDG_STATE_HOME="$WORK/state" \
    "$COLLECTOR" "$@"
}

# A scratch HOME/XDG_STATE_HOME per test file, torn down on exit.
WORK=$(mktemp -d)
mkdir -p "$WORK/home" "$WORK/state"
trap 'rm -rf "$WORK"' EXIT

finish() {
  printf '\n%d passed, %d failed\n' "$pass_count" "$fail_count"
  ((fail_count == 0)) || exit 1
}
