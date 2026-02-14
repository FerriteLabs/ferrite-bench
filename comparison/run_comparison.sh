#!/usr/bin/env bash
# Ferrite vs Redis Benchmark Comparison
# Uses redis-benchmark (ships with Redis) to compare throughput and latency
#
# Prerequisites:
#   - redis-benchmark installed (brew install redis / apt install redis-tools)
#   - ferrite running on FERRITE_PORT (default: 6380)
#   - redis-server running on REDIS_PORT (default: 6379) [optional]
#
# Usage:
#   ./run_comparison.sh                  # Benchmark both Ferrite and Redis
#   ./run_comparison.sh --ferrite-only   # Benchmark Ferrite only
#   FERRITE_PORT=6380 ./run_comparison.sh

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

FERRITE_HOST="${FERRITE_HOST:-127.0.0.1}"
FERRITE_PORT="${FERRITE_PORT:-6380}"
REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"

CLIENTS="${BENCH_CLIENTS:-50}"
REQUESTS="${BENCH_REQUESTS:-100000}"
DATA_SIZE="${BENCH_DATA_SIZE:-256}"
PIPELINE="${BENCH_PIPELINE:-1}"

RESULTS_DIR="$(dirname "$0")/results"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

FERRITE_ONLY=false
if [[ "${1:-}" == "--ferrite-only" ]]; then
    FERRITE_ONLY=true
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

info()  { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

check_prereqs() {
    if ! command -v redis-benchmark &>/dev/null; then
        error "redis-benchmark not found. Install with: brew install redis (macOS) or apt install redis-tools (Linux)"
        exit 1
    fi
}

run_benchmark() {
    local name="$1"
    local host="$2"
    local port="$3"
    local output_file="$4"

    info "Benchmarking ${name} at ${host}:${port} (${CLIENTS} clients, ${REQUESTS} requests, ${DATA_SIZE}B payload, pipeline=${PIPELINE})"

    redis-benchmark \
        -h "$host" \
        -p "$port" \
        -c "$CLIENTS" \
        -n "$REQUESTS" \
        -d "$DATA_SIZE" \
        -P "$PIPELINE" \
        -t set,get,incr,lpush,rpush,lpop,rpop,sadd,hset,ping \
        --csv \
        > "$output_file" 2>/dev/null

    ok "${name} benchmark complete → ${output_file}"
}

print_summary() {
    local label="$1"
    local csv_file="$2"

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  ${label} Results"
    echo "═══════════════════════════════════════════════════════════"
    printf "  %-20s %12s %12s\n" "Command" "Requests/s" "Avg Latency"
    echo "  ───────────────────────────────────────────────────────"

    tail -n +2 "$csv_file" | while IFS=',' read -r test rps avg_latency min_latency p50 p95 p99 max_latency; do
        test="${test//\"/}"
        rps="${rps//\"/}"
        avg_latency="${avg_latency//\"/}"
        printf "  %-20s %12s %10s ms\n" "$test" "$rps" "$avg_latency"
    done
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    check_prereqs
    mkdir -p "$RESULTS_DIR"

    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  Ferrite Benchmark Comparison Suite                     ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    info "Configuration:"
    echo "  Clients:    ${CLIENTS}"
    echo "  Requests:   ${REQUESTS}"
    echo "  Data size:  ${DATA_SIZE} bytes"
    echo "  Pipeline:   ${PIPELINE}"
    echo ""

    local ferrite_csv="${RESULTS_DIR}/ferrite_${TIMESTAMP}.csv"
    local redis_csv="${RESULTS_DIR}/redis_${TIMESTAMP}.csv"

    # Benchmark Ferrite
    if redis-benchmark -h "$FERRITE_HOST" -p "$FERRITE_PORT" -t ping -n 1 --csv &>/dev/null; then
        run_benchmark "Ferrite" "$FERRITE_HOST" "$FERRITE_PORT" "$ferrite_csv"
        print_summary "Ferrite" "$ferrite_csv"
    else
        warn "Ferrite not reachable at ${FERRITE_HOST}:${FERRITE_PORT} — skipping"
    fi

    # Benchmark Redis (optional)
    if [[ "$FERRITE_ONLY" == false ]]; then
        if redis-benchmark -h "$REDIS_HOST" -p "$REDIS_PORT" -t ping -n 1 --csv &>/dev/null; then
            run_benchmark "Redis" "$REDIS_HOST" "$REDIS_PORT" "$redis_csv"
            print_summary "Redis" "$redis_csv"
        else
            warn "Redis not reachable at ${REDIS_HOST}:${REDIS_PORT} — skipping"
        fi
    fi

    info "Results saved to ${RESULTS_DIR}/"

    # Side-by-side comparison if both ran
    if [[ -f "$ferrite_csv" && -f "$redis_csv" ]]; then
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        echo "  Side-by-Side Comparison (Requests/sec)"
        echo "═══════════════════════════════════════════════════════════"
        printf "  %-20s %12s %12s %10s\n" "Command" "Ferrite" "Redis" "Ratio"
        echo "  ───────────────────────────────────────────────────────"

        paste -d'|' <(tail -n +2 "$ferrite_csv") <(tail -n +2 "$redis_csv") | while IFS='|' read -r f_line r_line; do
            f_test=$(echo "$f_line" | cut -d',' -f1 | tr -d '"')
            f_rps=$(echo "$f_line" | cut -d',' -f2 | tr -d '"')
            r_rps=$(echo "$r_line" | cut -d',' -f2 | tr -d '"')

            if [[ -n "$r_rps" && "$r_rps" != "0" && "$r_rps" != "0.00" ]]; then
                ratio=$(echo "scale=2; $f_rps / $r_rps" | bc 2>/dev/null || echo "N/A")
                printf "  %-20s %12s %12s %9sx\n" "$f_test" "$f_rps" "$r_rps" "$ratio"
            else
                printf "  %-20s %12s %12s %10s\n" "$f_test" "$f_rps" "$r_rps" "N/A"
            fi
        done
        echo ""
    fi
}

main "$@"
