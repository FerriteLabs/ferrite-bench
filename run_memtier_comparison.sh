#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Competitive Benchmark Suite — Ferrite vs Redis 7 vs Dragonfly vs KeyDB
# Uses memtier_benchmark via Docker Compose for reproducible results.
#
# Usage:
#   ./run_memtier_comparison.sh                  # Benchmark all servers
#   ./run_memtier_comparison.sh --ferrite-only   # Benchmark Ferrite only
#
# Prerequisites:
#   - Docker and Docker Compose v2
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.benchmark.yml"
RESULTS_DIR="${SCRIPT_DIR}/comparison/results"
TIMESTAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
SUMMARY_FILE="${RESULTS_DIR}/summary_${TIMESTAMP}.md"

# ── memtier parameters ──────────────────────────────────────────────────────

THREADS="${MEMTIER_THREADS:-8}"
CLIENTS="${MEMTIER_CLIENTS:-50}"
REQUESTS="${MEMTIER_REQUESTS:-1000000}"
DATA_SIZE="${MEMTIER_DATA_SIZE:-512}"
KEY_MIN="${MEMTIER_KEY_MIN:-1}"
KEY_MAX="${MEMTIER_KEY_MAX:-1000000}"
PIPELINE_SIZES="${MEMTIER_PIPELINE_SIZES:-1,16,32}"
CONCURRENT_CLIENTS="${MEMTIER_CONCURRENT_CLIENTS:-50,100,200}"
CONNECT_TIMEOUT="${MEMTIER_CONNECT_TIMEOUT:-2000}"

# ── Derived configuration ────────────────────────────────────────────────
RUN_ID="${TIMESTAMP}-${RANDOM}"
RECONNECT_INTERVAL="${MEMTIER_RECONNECT_INTERVAL:-0}"

FERRITE_ONLY=false
if [[ "${1:-}" == "--ferrite-only" ]]; then
    FERRITE_ONLY=true
fi

# ── Server definitions ───────────────────────────────────────────────────────

declare -a SERVER_NAMES
declare -A SERVER_HOSTS SERVER_PORTS

if [[ "$FERRITE_ONLY" == true ]]; then
    SERVER_NAMES=(ferrite)
else
    SERVER_NAMES=(ferrite redis dragonfly keydb valkey)
fi

SERVER_HOSTS=(
    [ferrite]=ferrite
    [redis]=redis
    [dragonfly]=dragonfly
    [keydb]=keydb
    [valkey]=valkey
)
SERVER_PORTS=(
    [ferrite]=6379
    [redis]=6379
    [dragonfly]=6379
    [keydb]=6379
    [valkey]=6379
)

# ── Scenario definitions ────────────────────────────────────────────────────
# Each scenario: "label|ratio|pipeline"
SCENARIOS=(
    "set_only|1:0|1"
    "get_only|0:1|1"
    "mixed_50_50|1:1|1"
    "set_only_pipeline16|1:0|16"
    "get_only_pipeline16|0:1|16"
    "mixed_50_50_pipeline16|1:1|16"
)

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

check_prereqs() {
    if ! command -v docker &>/dev/null; then
        error "docker not found. Install Docker Desktop or Docker Engine."
        exit 1
    fi
    if ! docker compose version &>/dev/null; then
        error "docker compose v2 not found."
        exit 1
    fi
}

cleanup() {
    info "Stopping benchmark containers..."
    docker compose -f "$COMPOSE_FILE" down --remove-orphans 2>/dev/null || true
}

wait_for_services() {
    info "Waiting for all services to become healthy..."
    local retries=60
    local count=0
    while ! docker compose -f "$COMPOSE_FILE" ps --format json 2>/dev/null \
          | grep -q '"Health":"healthy"' && [[ $count -lt $retries ]]; do
        sleep 2
        count=$((count + 1))
    done
    # Give a final grace period for all healthchecks
    sleep 5
    ok "Services are ready."
}

# Run memtier_benchmark inside the memtier container against a target server
run_memtier() {
    local server_name="$1"
    local host="$2"
    local port="$3"
    local scenario_label="$4"
    local ratio="$5"
    local pipeline="$6"
    local csv_file="$7"

    info "Benchmarking ${server_name} — scenario: ${scenario_label} (ratio=${ratio}, pipeline=${pipeline})"

    # Pre-populate keys for GET-heavy workloads
    docker compose -f "$COMPOSE_FILE" exec -T memtier \
        memtier_benchmark \
            --server="$host" \
            --port="$port" \
            --threads="$THREADS" \
            --clients=10 \
            --requests=100000 \
            --ratio=1:0 \
            --data-size="$DATA_SIZE" \
            --key-minimum="$KEY_MIN" \
            --key-maximum="$KEY_MAX" \
            --key-prefix="memtier-" \
            --hide-histogram \
        >/dev/null 2>&1 || true

    # Actual benchmark run — capture JSON output
    local json_output
    json_output=$(docker compose -f "$COMPOSE_FILE" exec -T memtier \
        memtier_benchmark \
            --server="$host" \
            --port="$port" \
            --threads="$THREADS" \
            --clients="$CLIENTS" \
            --requests="$REQUESTS" \
            --ratio="$ratio" \
            --data-size="$DATA_SIZE" \
            --key-minimum="$KEY_MIN" \
            --key-maximum="$KEY_MAX" \
            --key-prefix="memtier-" \
            --pipeline="$pipeline" \
            --json-out-file=/dev/stdout \
            --hide-histogram \
        2>/dev/null)

    # Extract totals from JSON: ops/sec, latency avg, p50, p99
    local ops_sec avg_latency p50_latency p99_latency
    ops_sec=$(echo "$json_output" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    totals = d['ALL STATS']['Totals']
    print(f\"{totals['Ops/sec']:.2f}\")
except Exception:
    print('0.00')
" 2>/dev/null || echo "0.00")

    avg_latency=$(echo "$json_output" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    totals = d['ALL STATS']['Totals']
    print(f\"{totals['Latency']:.3f}\")
except Exception:
    print('0.000')
" 2>/dev/null || echo "0.000")

    p50_latency=$(echo "$json_output" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    sets_p50 = d['ALL STATS'].get('Sets', {}).get('Percentile Latencies', {}).get('p50.00000', 0)
    gets_p50 = d['ALL STATS'].get('Gets', {}).get('Percentile Latencies', {}).get('p50.00000', 0)
    vals = [v for v in [sets_p50, gets_p50] if v > 0]
    print(f\"{max(vals):.3f}\" if vals else '0.000')
except Exception:
    print('0.000')
" 2>/dev/null || echo "0.000")

    p99_latency=$(echo "$json_output" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    sets_p99 = d['ALL STATS'].get('Sets', {}).get('Percentile Latencies', {}).get('p99.00000', 0)
    gets_p99 = d['ALL STATS'].get('Gets', {}).get('Percentile Latencies', {}).get('p99.00000', 0)
    vals = [v for v in [sets_p99, gets_p99] if v > 0]
    print(f\"{max(vals):.3f}\" if vals else '0.000')
except Exception:
    print('0.000')
" 2>/dev/null || echo "0.000")

    echo "${server_name},${scenario_label},${ratio},${pipeline},${ops_sec},${avg_latency},${p50_latency},${p99_latency}" >> "$csv_file"
    ok "${server_name}/${scenario_label}: ${ops_sec} ops/sec, avg=${avg_latency}ms, p50=${p50_latency}ms, p99=${p99_latency}ms"
}

# Flush all keys on a server before the next scenario
flush_server() {
    local host="$1"
    local port="$2"
    docker compose -f "$COMPOSE_FILE" exec -T memtier \
        redis-cli -h "$host" -p "$port" FLUSHALL >/dev/null 2>&1 || true
}

generate_summary() {
    local csv_file="$1"

    {
        echo "# Competitive Benchmark Results — ${TIMESTAMP}"
        echo ""
        echo "## Configuration"
        echo ""
        echo "| Parameter | Value |"
        echo "|-----------|-------|"
        echo "| Threads | ${THREADS} |"
        echo "| Clients per thread | ${CLIENTS} |"
        echo "| Total clients | $((THREADS * CLIENTS)) |"
        echo "| Total requests | ${REQUESTS} |"
        echo "| Data size | ${DATA_SIZE} bytes |"
        echo "| Key range | ${KEY_MIN}–${KEY_MAX} |"
        echo "| Tool | memtier_benchmark (Docker) |"
        echo ""

        for scenario_entry in "${SCENARIOS[@]}"; do
            IFS='|' read -r label ratio pipeline <<< "$scenario_entry"
            local friendly_name="${label//_/ }"

            echo "## ${friendly_name} (ratio=${ratio}, pipeline=${pipeline})"
            echo ""
            echo "| Server | Ops/sec | Avg Latency (ms) | p50 (ms) | p99 (ms) |"
            echo "|--------|--------:|------------------:|---------:|---------:|"

            grep ",${label}," "$csv_file" | while IFS=',' read -r srv sc rt pl ops avg p50 p99; do
                printf "| %-10s | %s | %s | %s | %s |\n" "$srv" "$ops" "$avg" "$p50" "$p99"
            done

            echo ""
        done
    } > "$SUMMARY_FILE"

    ok "Markdown summary → ${SUMMARY_FILE}"
}

# Validate latency thresholds for Ferrite
check_latency_thresholds() {
    local csv_file="$1"
    local max_p99="${MAX_P99_LATENCY_MS:-10.0}"

    info "Checking latency thresholds (max p99: ${max_p99}ms)..."
    local failures=0

    grep "^ferrite," "$csv_file" | while IFS=',' read -r srv sc rt pl ops avg p50 p99; do
        if (( $(echo "$p99 > $max_p99" | bc -l) )); then
            warn "THRESHOLD EXCEEDED: ${sc} p99=${p99}ms > ${max_p99}ms"
            failures=$((failures + 1))
        fi
    done

    if [[ $failures -gt 0 ]]; then
        warn "${failures} scenario(s) exceeded latency threshold"
    else
        ok "All scenarios within latency thresholds"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    check_prereqs
    mkdir -p "$RESULTS_DIR"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Competitive Benchmark Suite (memtier_benchmark)            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    info "Configuration:"
    echo "  Threads:            ${THREADS}"
    echo "  Clients per thread: ${CLIENTS}"
    echo "  Total clients:      $((THREADS * CLIENTS))"
    echo "  Total requests:     ${REQUESTS}"
    echo "  Data size:          ${DATA_SIZE} bytes"
    echo "  Key range:          ${KEY_MIN}–${KEY_MAX}"
    echo ""

    # Determine which services to start
    local services
    if [[ "$FERRITE_ONLY" == true ]]; then
        services="ferrite memtier"
    else
        services=""
    fi

    trap cleanup EXIT

    info "Starting Docker Compose services..."
    if [[ -n "$services" ]]; then
        docker compose -f "$COMPOSE_FILE" up -d $services
    else
        docker compose -f "$COMPOSE_FILE" up -d
    fi
    wait_for_services

    local csv_file="${RESULTS_DIR}/memtier_${TIMESTAMP}.csv"
    echo "server,scenario,ratio,pipeline,ops_sec,avg_latency_ms,p50_latency_ms,p99_latency_ms" > "$csv_file"

    for scenario_entry in "${SCENARIOS[@]}"; do
        IFS='|' read -r label ratio pipeline <<< "$scenario_entry"

        echo ""
        info "━━━ Scenario: ${label} (ratio=${ratio}, pipeline=${pipeline}) ━━━"

        for server_name in "${SERVER_NAMES[@]}"; do
            local host="${SERVER_HOSTS[$server_name]}"
            local port="${SERVER_PORTS[$server_name]}"

            flush_server "$host" "$port"
            run_memtier "$server_name" "$host" "$port" "$label" "$ratio" "$pipeline" "$csv_file"
        done
    done

    echo ""
    info "━━━ Results ━━━"
    generate_summary "$csv_file"
    ok "CSV results → ${csv_file}"

    # Print a quick console summary
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Quick Summary — Ops/sec by Scenario"
    echo "═══════════════════════════════════════════════════════════════"
    printf "  %-26s" "Scenario"
    for s in "${SERVER_NAMES[@]}"; do
        printf " %12s" "$s"
    done
    echo ""
    echo "  ─────────────────────────────────────────────────────────────"

    for scenario_entry in "${SCENARIOS[@]}"; do
        IFS='|' read -r label _ratio _pipeline <<< "$scenario_entry"
        printf "  %-26s" "$label"
        for s in "${SERVER_NAMES[@]}"; do
            local ops
            ops=$(grep "^${s},${label}," "$csv_file" | cut -d',' -f5)
            printf " %12s" "${ops:-N/A}"
        done
        echo ""
    done
    echo ""

    info "Full markdown report: ${SUMMARY_FILE}"
}

main "$@"
