#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "$ROOT_DIR/benchmarks/harness.sh"

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    if [[ "$expected" != "$actual" ]]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2
        return 1
    fi
}

assert_eq \
    "1:1|256|16|Pipeline-16 Mixed" \
    "$(get_scenario_params pipeline-16)" \
    "scenario parameters remain deterministic"

parsed=$(
    printf '%s' \
        '{"ALL STATS":{"Totals":{"Ops/sec":1234.5,"Latency":1.25},"Sets":{"Percentile Latencies":{"p50.00000":0.5,"p99.00000":2.0,"p99.90000":3.0}}}}' \
        | parse_memtier_json
)
assert_eq "1234.50,1.250,0.500,2.000,3.000" "$parsed" "memtier JSON parsing"

if printf '%s' '{"not":"memtier"}' | parse_memtier_json >/dev/null 2>&1; then
    printf 'FAIL: malformed memtier JSON should fail\n' >&2
    exit 1
fi

if (
    # shellcheck disable=SC2034
    SERVERS="ferrite,unknown"
    # shellcheck disable=SC2034
    SCENARIOS="get"
    validate_inputs >/dev/null 2>&1
); then
    printf 'FAIL: invalid server should fail validation\n' >&2
    exit 1
fi

# shellcheck disable=SC1091
source "$ROOT_DIR/benchmarks/vector_comparison.sh"

assert_eq \
    "42.5" \
    "$(read_result_value <(printf '%s\n' 'QPS=42.5' 'OTHER=value') QPS)" \
    "result parser reads exact keys"
assert_eq \
    "N/A" \
    "$(read_result_value <(printf '%s\n' 'QPS=42.5') MISSING N/A)" \
    "result parser returns explicit default"

printf 'Shell helper tests passed.\n'
