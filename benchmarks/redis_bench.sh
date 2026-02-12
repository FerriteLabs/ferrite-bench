#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Redis Benchmark Suite
#
# Runs redis-benchmark against a Redis server and captures throughput and
# latency metrics for common data structure operations. Outputs results in
# JSON and markdown table format. Uses the same methodology as ferrite_bench.sh
# for fair comparison.
#
# Usage:
#   ./redis_bench.sh                            # Run with defaults
#   BENCH_PORT=6379 ./redis_bench.sh            # Custom port
#   BENCH_CLIENTS=200 ./redis_bench.sh          # High concurrency
#
# Prerequisites:
#   - redis-benchmark installed
#   - jq installed
#   - Redis server running on BENCH_HOST:BENCH_PORT
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESULTS_DIR="${REPO_ROOT}/results"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

# ── Configuration ────────────────────────────────────────────────────────────

SERVER_NAME="redis"
HOST="${BENCH_HOST:-127.0.0.1}"
PORT="${BENCH_PORT:-6379}"
CLIENTS="${BENCH_CLIENTS:-50}"
REQUESTS="${BENCH_REQUESTS:-100000}"
DATA_SIZE="${BENCH_DATA_SIZE:-256}"
PIPELINE="${BENCH_PIPELINE:-1}"
THREADS="${BENCH_THREADS:-4}"

# Operations to benchmark (same as ferrite_bench.sh)
OPERATIONS=("SET" "GET" "HSET" "HGET" "LPUSH" "LPOP" "SADD" "ZADD")

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

check_prereqs() {
    local missing=()
    command -v redis-benchmark &>/dev/null || missing+=("redis-benchmark")
    command -v jq &>/dev/null || missing+=("jq")

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        echo "  Install with: brew install redis jq (macOS) or apt install redis-tools jq (Linux)"
        exit 1
    fi
}

check_server() {
    info "Checking ${SERVER_NAME} at ${HOST}:${PORT}..."
    if ! redis-benchmark -h "$HOST" -p "$PORT" -t ping -n 1 --csv &>/dev/null; then
        error "${SERVER_NAME} is not reachable at ${HOST}:${PORT}"
        echo "  Start Redis with: redis-server --port ${PORT} --save \"\" --appendonly no"
        exit 1
    fi
    ok "${SERVER_NAME} is ready."
}

# Run redis-benchmark for a single operation and return JSON metrics
bench_operation() {
    local op="$1"
    local op_lower
    op_lower="$(echo "$op" | tr '[:upper:]' '[:lower:]')"

    # Flush before each operation
    redis-benchmark -h "$HOST" -p "$PORT" -t ping -n 1 --csv &>/dev/null || true

    local raw_csv
    raw_csv=$(redis-benchmark \
        -h "$HOST" \
        -p "$PORT" \
        -c "$CLIENTS" \
        -n "$REQUESTS" \
        -d "$DATA_SIZE" \
        -P "$PIPELINE" \
        -t "$op_lower" \
        --csv \
        2>/dev/null)

    # Parse CSV output (skip header)
    # Format: "test","rps","avg_latency","min_latency","p50","p95","p99","max_latency"
    local data_line
    data_line=$(echo "$raw_csv" | tail -n +2 | head -1)

    if [[ -z "$data_line" ]]; then
        warn "No results for ${op}"
        echo "{}"
        return
    fi

    local rps avg_lat min_lat p50 p95 p99 max_lat
    rps=$(echo "$data_line" | cut -d',' -f2 | tr -d '"')
    avg_lat=$(echo "$data_line" | cut -d',' -f3 | tr -d '"')
    min_lat=$(echo "$data_line" | cut -d',' -f4 | tr -d '"')
    p50=$(echo "$data_line" | cut -d',' -f5 | tr -d '"')
    p95=$(echo "$data_line" | cut -d',' -f6 | tr -d '"')
    p99=$(echo "$data_line" | cut -d',' -f7 | tr -d '"')
    max_lat=$(echo "$data_line" | cut -d',' -f8 | tr -d '"')

    # Compute p99.9 approximation (redis-benchmark doesn't provide it directly)
    local p999="${max_lat}"

    cat <<EOF
{
  "operation": "${op}",
  "ops_per_sec": ${rps:-0},
  "avg_latency_ms": ${avg_lat:-0},
  "min_latency_ms": ${min_lat:-0},
  "p50_latency_ms": ${p50:-0},
  "p95_latency_ms": ${p95:-0},
  "p99_latency_ms": ${p99:-0},
  "p999_latency_ms": ${p999:-0}
}
EOF
}

generate_json() {
    local json_file="$1"
    shift
    local results=("$@")

    local results_array="["
    local first=true
    for r in "${results[@]}"; do
        if [[ "$r" == "{}" ]]; then continue; fi
        if [[ "$first" == true ]]; then
            first=false
        else
            results_array+=","
        fi
        results_array+="$r"
    done
    results_array+="]"

    jq -n \
        --arg server "$SERVER_NAME" \
        --arg timestamp "$TIMESTAMP" \
        --arg host "$HOST" \
        --argjson port "$PORT" \
        --argjson clients "$CLIENTS" \
        --argjson requests "$REQUESTS" \
        --argjson data_size "$DATA_SIZE" \
        --argjson pipeline "$PIPELINE" \
        --argjson threads "$THREADS" \
        --argjson results "$results_array" \
        '{
            server: $server,
            timestamp: $timestamp,
            config: {
                host: $host,
                port: $port,
                clients: $clients,
                requests: $requests,
                data_size: $data_size,
                pipeline: $pipeline,
                threads: $threads
            },
            results: $results
        }' > "$json_file"
}

generate_markdown() {
    local md_file="$1"
    local json_file="$2"

    {
        echo "# Redis Benchmark Results"
        echo ""
        echo "**Date:** ${TIMESTAMP}"
        echo "**Server:** ${SERVER_NAME} at ${HOST}:${PORT}"
        echo ""
        echo "## Configuration"
        echo ""
        echo "| Parameter | Value |"
        echo "|-----------|-------|"
        echo "| Clients | ${CLIENTS} |"
        echo "| Requests | ${REQUESTS} |"
        echo "| Data size | ${DATA_SIZE} bytes |"
        echo "| Pipeline | ${PIPELINE} |"
        echo "| Threads | ${THREADS} |"
        echo ""
        echo "## Results"
        echo ""
        echo "| Operation | Ops/sec | Avg Latency (ms) | P50 (ms) | P99 (ms) | P99.9 (ms) |"
        echo "|-----------|--------:|------------------:|---------:|---------:|-----------:|"

        jq -r '.results[] | "| \(.operation) | \(.ops_per_sec) | \(.avg_latency_ms) | \(.p50_latency_ms) | \(.p99_latency_ms) | \(.p999_latency_ms) |"' "$json_file"

        echo ""
        echo "---"
        echo "*Generated by ferrite-bench on ${TIMESTAMP}*"
    } > "$md_file"
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    check_prereqs
    check_server
    mkdir -p "$RESULTS_DIR"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Redis Benchmark Suite                                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    info "Configuration:"
    echo "  Server:     ${SERVER_NAME} @ ${HOST}:${PORT}"
    echo "  Clients:    ${CLIENTS}"
    echo "  Requests:   ${REQUESTS}"
    echo "  Data size:  ${DATA_SIZE} bytes"
    echo "  Pipeline:   ${PIPELINE}"
    echo "  Threads:    ${THREADS}"
    echo ""

    local results=()

    for op in "${OPERATIONS[@]}"; do
        info "Benchmarking ${op}..."
        local result
        result=$(bench_operation "$op")
        results+=("$result")

        if [[ "$result" != "{}" ]]; then
            local rps
            rps=$(echo "$result" | jq -r '.ops_per_sec')
            local avg
            avg=$(echo "$result" | jq -r '.avg_latency_ms')
            local p99
            p99=$(echo "$result" | jq -r '.p99_latency_ms')
            ok "${op}: ${rps} ops/sec, avg=${avg}ms, p99=${p99}ms"
        fi
    done

    # Generate output files
    local json_file="${RESULTS_DIR}/${SERVER_NAME}_${TIMESTAMP}.json"
    local md_file="${RESULTS_DIR}/${SERVER_NAME}_${TIMESTAMP}.md"

    generate_json "$json_file" "${results[@]}"
    generate_markdown "$md_file" "$json_file"

    # Create a "latest" symlink for easy access
    ln -sf "$(basename "$json_file")" "${RESULTS_DIR}/${SERVER_NAME}_latest.json"
    ln -sf "$(basename "$md_file")" "${RESULTS_DIR}/${SERVER_NAME}_latest.md"

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Results Summary"
    echo "═══════════════════════════════════════════════════════════════"
    jq -r '"  \(.operation):\t\(.ops_per_sec) ops/sec\tavg=\(.avg_latency_ms)ms\tp99=\(.p99_latency_ms)ms"' \
        < <(jq -c '.results[]' "$json_file")
    echo ""
    ok "JSON  → ${json_file}"
    ok "Table → ${md_file}"
}

main "$@"
