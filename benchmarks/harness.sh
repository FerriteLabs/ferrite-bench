#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Ferrite Benchmark Harness — Automated, Reproducible, Publishable
#
# Runs standardized benchmark scenarios against multiple key-value servers
# using memtier_benchmark via Docker Compose. Produces CSV data and Markdown
# comparison reports suitable for publishing.
#
# Usage:
#   ./benchmarks/harness.sh
#   ./benchmarks/harness.sh --servers ferrite,redis --scenarios get,set,mixed
#   ./benchmarks/harness.sh --duration 30 --clients 100 --output-dir ./my-results
#   ./benchmarks/harness.sh --help
#
# Prerequisites:
#   - Docker and Docker Compose v2
#   - python3 (for JSON parsing)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="${REPO_DIR}/docker-compose.benchmark.yml"
TIMESTAMP="$(date -u +%Y%m%d_%H%M%S)"

# ── Defaults ─────────────────────────────────────────────────────────────────

DEFAULT_SERVERS="ferrite,redis,dragonfly,keydb,valkey"
DEFAULT_SCENARIOS="get,set,mixed,pipeline-16,pipeline-64,large-values,batch-ops"
DEFAULT_DURATION=60
DEFAULT_CLIENTS=50
DEFAULT_OUTPUT_DIR="${REPO_DIR}/results"
DEFAULT_THREADS=8
DEFAULT_KEY_COUNT=1000000
DEFAULT_VALUE_SIZE=256
DEFAULT_WARMUP=15
DEFAULT_TIMEOUT=900

# ── Server registry ──────────────────────────────────────────────────────────

declare -A SERVER_HOST=(
    [ferrite]=ferrite
    [redis]=redis
    [dragonfly]=dragonfly
    [keydb]=keydb
    [valkey]=valkey
)
declare -A SERVER_PORT=(
    [ferrite]=6379
    [redis]=6379
    [dragonfly]=6379
    [keydb]=6379
    [valkey]=6379
)
declare -A SERVER_HOST_PORT=(
    [ferrite]=6380
    [redis]=6381
    [dragonfly]=6382
    [keydb]=6383
    [valkey]=6384
)

# ── Parsed options ───────────────────────────────────────────────────────────

SERVERS="$DEFAULT_SERVERS"
SCENARIOS="$DEFAULT_SCENARIOS"
DURATION="$DEFAULT_DURATION"
CLIENTS="$DEFAULT_CLIENTS"
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
THREADS="$DEFAULT_THREADS"
WARMUP="$DEFAULT_WARMUP"
TIMEOUT="$DEFAULT_TIMEOUT"

# ── Logging ──────────────────────────────────────────────────────────────────

info()  { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[0;32m[  OK]\033[0m  $*"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[0;31m[ERR ]\033[0m $*" >&2; }

# ── Usage / Help ─────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Ferrite Benchmark Harness — Automated, Reproducible, Publishable

USAGE
    $(basename "$0") [OPTIONS]

OPTIONS
    --servers <list>       Comma-separated servers to benchmark.
                           Choices: ferrite, redis, dragonfly, valkey, keydb
                           Default: ${DEFAULT_SERVERS}

    --scenarios <list>     Comma-separated scenarios to run.
                           Choices: get, set, mixed, pipeline-16, pipeline-64,
                                    large-values, vector
                           Default: ${DEFAULT_SCENARIOS}

    --duration <secs>      Duration of each benchmark run in seconds.
                           Default: ${DEFAULT_DURATION}

    --clients <count>      Number of concurrent clients per thread.
                           Default: ${DEFAULT_CLIENTS}

    --output-dir <path>    Directory for results (CSV + Markdown).
                           Default: ${DEFAULT_OUTPUT_DIR}

    --threads <count>      Number of memtier threads.
                           Default: ${DEFAULT_THREADS}

    --warmup <secs>        Warm-up duration before each measured run.
                           Default: ${DEFAULT_WARMUP}

    --timeout <secs>       Max time per benchmark run before abort.
                           Default: ${DEFAULT_TIMEOUT}

    --help                 Show this help message and exit.

SCENARIOS
    get             100% GET operations, 1M keys, ${DEFAULT_VALUE_SIZE}B values
    set             100% SET operations, 1M keys, ${DEFAULT_VALUE_SIZE}B values
    mixed           50% GET / 50% SET, 1M keys, ${DEFAULT_VALUE_SIZE}B values
    pipeline-16     Mixed workload with pipeline depth 16
    pipeline-64     Mixed workload with pipeline depth 64
    large-values    Mixed workload with 10KB values
    vector          Vector similarity search benchmark (Ferrite only)

OUTPUT
    <output-dir>/data_<timestamp>.csv       Raw benchmark data
    <output-dir>/report_<timestamp>.md      Markdown comparison report

EXAMPLES
    # Full suite with defaults
    $(basename "$0")

    # Quick Ferrite-vs-Redis comparison, 30s each
    $(basename "$0") --servers ferrite,redis --duration 30

    # Pipeline-focused benchmarks only
    $(basename "$0") --scenarios pipeline-16,pipeline-64 --clients 100

    # Custom output directory
    $(basename "$0") --output-dir /tmp/bench-results
EOF
    exit 0
}

# ── Argument parsing ─────────────────────────────────────────────────────────

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --servers)    SERVERS="$2";     shift 2 ;;
            --scenarios)  SCENARIOS="$2";   shift 2 ;;
            --duration)   DURATION="$2";    shift 2 ;;
            --clients)    CLIENTS="$2";     shift 2 ;;
            --output-dir) OUTPUT_DIR="$2";  shift 2 ;;
            --threads)    THREADS="$2";     shift 2 ;;
            --warmup)     WARMUP="$2";      shift 2 ;;
            --timeout)    TIMEOUT="$2";     shift 2 ;;
            --help|-h)    usage ;;
            *)
                error "Unknown option: $1"
                echo "Run '$(basename "$0") --help' for usage."
                exit 1
                ;;
        esac
    done
}

# ── Validation ───────────────────────────────────────────────────────────────

validate_inputs() {
    local valid_servers="ferrite redis dragonfly keydb valkey"
    local valid_scenarios="get set mixed pipeline-16 pipeline-64 large-values vector zipfian batch-ops"

    IFS=',' read -ra server_list <<< "$SERVERS"
    for s in "${server_list[@]}"; do
        if ! echo "$valid_servers" | grep -qw "$s"; then
            error "Unknown server: '$s'. Valid: ${valid_servers// /, }"
            exit 1
        fi
    done

    IFS=',' read -ra scenario_list <<< "$SCENARIOS"
    for s in "${scenario_list[@]}"; do
        if ! echo "$valid_scenarios" | grep -qw "$s"; then
            error "Unknown scenario: '$s'. Valid: ${valid_scenarios// /, }"
            exit 1
        fi
    done

    if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [[ "$DURATION" -lt 1 ]]; then
        error "--duration must be a positive integer (got: '$DURATION')"
        exit 1
    fi
    if ! [[ "$CLIENTS" =~ ^[0-9]+$ ]] || [[ "$CLIENTS" -lt 1 ]]; then
        error "--clients must be a positive integer (got: '$CLIENTS')"
        exit 1
    fi
}

check_prereqs() {
    if ! command -v docker &>/dev/null; then
        error "docker not found. Install Docker Desktop or Docker Engine."
        exit 1
    fi
    if ! docker compose version &>/dev/null; then
        error "docker compose v2 not found."
        exit 1
    fi
    if ! command -v python3 &>/dev/null; then
        error "python3 not found. Required for JSON/report parsing."
        exit 1
    fi
}

# ── Docker lifecycle ─────────────────────────────────────────────────────────

COMPOSE_SERVICES_STARTED=()

cleanup() {
    local exit_code=$?
    echo ""
    info "Cleaning up..."
    docker compose -f "$COMPOSE_FILE" down --remove-orphans 2>/dev/null || true
    if [[ $exit_code -ne 0 ]]; then
        warn "Harness exited with code ${exit_code}"
    fi
}

start_services() {
    IFS=',' read -ra server_list <<< "$SERVERS"
    local services_to_start=()

    for s in "${server_list[@]}"; do
        services_to_start+=("$s")
    done
    services_to_start+=("memtier")

    info "Starting Docker services: ${services_to_start[*]}"
    docker compose -f "$COMPOSE_FILE" up -d "${services_to_start[@]}" 2>&1 | head -20
    COMPOSE_SERVICES_STARTED=("${services_to_start[@]}")

    wait_for_healthy "${server_list[@]}"
}

wait_for_healthy() {
    local servers=("$@")
    info "Waiting for servers to become healthy..."

    local max_wait=120
    local elapsed=0

    for server in "${servers[@]}"; do
        local ready=false
        elapsed=0
        while [[ "$elapsed" -lt "$max_wait" ]]; do
            local health
            health=$(docker compose -f "$COMPOSE_FILE" ps --format json 2>/dev/null \
                | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        if obj.get('Service') == '${server}' and obj.get('Health') == 'healthy':
            print('healthy')
    except (json.JSONDecodeError, KeyError):
        pass
" 2>/dev/null || echo "")

            if [[ "$health" == "healthy" ]]; then
                ready=true
                break
            fi
            sleep 2
            elapsed=$((elapsed + 2))
        done

        if [[ "$ready" != true ]]; then
            error "Server '${server}' did not become healthy within ${max_wait}s"
            exit 1
        fi
        ok "${server} is healthy"
    done

    # Grace period for stability
    sleep 3
}

flush_server() {
    local host="$1"
    local port="$2"
    docker compose -f "$COMPOSE_FILE" exec -T memtier \
        redis-cli -h "$host" -p "$port" FLUSHALL >/dev/null 2>&1 || true
}

# ── Resource collection ──────────────────────────────────────────────────────

collect_resource_usage() {
    local server="$1"
    local container_name

    container_name=$(docker compose -f "$COMPOSE_FILE" ps -q "$server" 2>/dev/null | head -1)
    if [[ -z "$container_name" ]]; then
        echo "0.00,0"
        return
    fi

    docker stats --no-stream --format '{{.CPUPerc}},{{.MemUsage}}' "$container_name" 2>/dev/null \
        | head -1 \
        | python3 -c "
import sys
line = sys.stdin.readline().strip()
try:
    parts = line.split(',')
    cpu = parts[0].replace('%', '').strip()
    mem_part = parts[1].split('/')[0].strip()
    # Convert memory to MiB
    if 'GiB' in mem_part:
        mem_mb = float(mem_part.replace('GiB', '').strip()) * 1024
    elif 'MiB' in mem_part:
        mem_mb = float(mem_part.replace('MiB', '').strip())
    elif 'KiB' in mem_part:
        mem_mb = float(mem_part.replace('KiB', '').strip()) / 1024
    else:
        mem_mb = 0
    print(f'{cpu},{mem_mb:.1f}')
except Exception:
    print('0.00,0.0')
" 2>/dev/null || echo "0.00,0.0"
}

# ── Scenario execution ───────────────────────────────────────────────────────

get_scenario_params() {
    local scenario="$1"
    # Returns: ratio|data_size|pipeline|label
    case "$scenario" in
        get)           echo "0:1|${DEFAULT_VALUE_SIZE}|1|GET-only (128B)" ;;
        set)           echo "1:0|${DEFAULT_VALUE_SIZE}|1|SET-only (128B)" ;;
        mixed)         echo "1:1|${DEFAULT_VALUE_SIZE}|1|Mixed 50/50 (128B)" ;;
        pipeline-16)   echo "1:1|${DEFAULT_VALUE_SIZE}|16|Pipeline-16 Mixed" ;;
        pipeline-64)   echo "1:1|${DEFAULT_VALUE_SIZE}|64|Pipeline-64 Mixed" ;;
        large-values)  echo "1:1|10240|1|Large Values (10KB)" ;;
        zipfian)       echo "1:9|${DEFAULT_VALUE_SIZE}|1|Zipfian Read-Heavy" ;;
        batch-ops)     echo "1:1|${DEFAULT_VALUE_SIZE}|1|Batch Operations" ;;
        vector)        echo "1:1|${DEFAULT_VALUE_SIZE}|1|Vector Search" ;;
        *)             error "Unknown scenario: $scenario"; exit 1 ;;
    esac
}

run_warmup() {
    local host="$1"
    local port="$2"
    local data_size="$3"

    if [[ "$WARMUP" -le 0 ]]; then
        return
    fi

    info "  Warm-up: pre-populating keys (${WARMUP}s)..."
    timeout "${WARMUP}" docker compose -f "$COMPOSE_FILE" exec -T memtier \
        memtier_benchmark \
            --server="$host" \
            --port="$port" \
            --threads="$THREADS" \
            --clients=10 \
            --test-time="$WARMUP" \
            --ratio=1:0 \
            --data-size="$data_size" \
            --key-minimum=1 \
            --key-maximum="$DEFAULT_KEY_COUNT" \
            --key-prefix="bench-" \
            --hide-histogram \
        >/dev/null 2>&1 || true
}

run_benchmark() {
    local server="$1"
    local scenario="$2"
    local csv_file="$3"

    local host="${SERVER_HOST[$server]}"
    local port="${SERVER_PORT[$server]}"

    local params
    params=$(get_scenario_params "$scenario")
    IFS='|' read -r ratio data_size pipeline label <<< "$params"

    info "  ${server} × ${label} (ratio=${ratio}, pipeline=${pipeline}, ${DURATION}s)"

    # Flush and warm up
    flush_server "$host" "$port"
    run_warmup "$host" "$port" "$data_size"

    # Collect pre-run resource snapshot
    local pre_resources
    pre_resources=$(collect_resource_usage "$server")

    # Run the actual benchmark with timeout protection
    local json_output=""
    local run_ok=true

    json_output=$(timeout "$TIMEOUT" docker compose -f "$COMPOSE_FILE" exec -T memtier \
        memtier_benchmark \
            --server="$host" \
            --port="$port" \
            --threads="$THREADS" \
            --clients="$CLIENTS" \
            --test-time="$DURATION" \
            --ratio="$ratio" \
            --data-size="$data_size" \
            --key-minimum=1 \
            --key-maximum="$DEFAULT_KEY_COUNT" \
            --key-prefix="bench-" \
            --pipeline="$pipeline" \
            --json-out-file=/dev/stdout \
            --hide-histogram \
        2>/dev/null) || run_ok=false

    # Collect post-run resource snapshot
    local post_resources
    post_resources=$(collect_resource_usage "$server")

    if [[ "$run_ok" != true ]] || [[ -z "$json_output" ]]; then
        warn "  Benchmark failed or timed out for ${server}/${scenario}"
        echo "${server},${scenario},${label},${ratio},${pipeline},${data_size},${DURATION},0.00,0.000,0.000,0.000,0.000,0.00,0.0" >> "$csv_file"
        return
    fi

    # Parse JSON results
    local results
    results=$(echo "$json_output" | python3 -c "
import sys, json

try:
    d = json.load(sys.stdin)
    totals = d['ALL STATS']['Totals']
    ops_sec = totals.get('Ops/sec', 0)
    avg_lat = totals.get('Latency', 0)

    # Percentile latencies — check both Sets and Gets
    sets_pct = d['ALL STATS'].get('Sets', {}).get('Percentile Latencies', {})
    gets_pct = d['ALL STATS'].get('Gets', {}).get('Percentile Latencies', {})

    def best_pct(key):
        vals = []
        for pct in [sets_pct, gets_pct]:
            v = pct.get(key, 0)
            if v > 0:
                vals.append(v)
        return max(vals) if vals else 0

    p50 = best_pct('p50.00000')
    p99 = best_pct('p99.00000')
    p999 = best_pct('p99.90000')

    print(f'{ops_sec:.2f},{avg_lat:.3f},{p50:.3f},{p99:.3f},{p999:.3f}')
except Exception as e:
    print('0.00,0.000,0.000,0.000,0.000', file=sys.stdout)
" 2>/dev/null)

    if [[ -z "$results" ]]; then
        results="0.00,0.000,0.000,0.000,0.000"
    fi

    IFS=',' read -r cpu_pct mem_mb <<< "$post_resources"

    echo "${server},${scenario},${label},${ratio},${pipeline},${data_size},${DURATION},${results},${cpu_pct},${mem_mb}" >> "$csv_file"

    local ops_sec
    ops_sec=$(echo "$results" | cut -d',' -f1)
    local p99
    p99=$(echo "$results" | cut -d',' -f4)
    ok "  ${ops_sec} ops/sec | p99=${p99}ms | CPU=${cpu_pct}% | Mem=${mem_mb}MiB"
}

# ── Report generation ────────────────────────────────────────────────────────

generate_report() {
    local csv_file="$1"
    local report_file="$2"

    IFS=',' read -ra server_list <<< "$SERVERS"
    IFS=',' read -ra scenario_list <<< "$SCENARIOS"

    {
        echo "# Ferrite Benchmark Report"
        echo ""
        echo "_Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')_"
        echo ""

        # ── System info ──────────────────────────────────────────────────
        echo "## System Information"
        echo ""
        echo "| Property | Value |"
        echo "|----------|-------|"
        echo "| OS | $(uname -s) $(uname -r) |"
        echo "| Architecture | $(uname -m) |"
        echo "| Docker | $(docker --version 2>/dev/null | head -1) |"
        echo "| Docker Compose | $(docker compose version 2>/dev/null | head -1) |"
        echo "| CPUs (host) | $(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 'N/A') |"
        echo "| Memory (host) | $(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f GiB", $1/1073741824}' || echo 'N/A') |"
        echo ""

        # ── Methodology ──────────────────────────────────────────────────
        echo "## Methodology"
        echo ""
        echo "| Parameter | Value |"
        echo "|-----------|-------|"
        echo "| Tool | memtier_benchmark (Docker) |"
        echo "| Threads | ${THREADS} |"
        echo "| Clients per thread | ${CLIENTS} |"
        echo "| Total clients | $((THREADS * CLIENTS)) |"
        echo "| Duration per run | ${DURATION}s |"
        echo "| Warm-up | ${WARMUP}s |"
        echo "| Key range | 1–${DEFAULT_KEY_COUNT} |"
        echo "| Resource limits | 4 CPUs, 2 GiB RAM per server |"
        echo ""
        echo "Each server runs in an isolated Docker container with identical resource"
        echo "constraints. A warm-up phase pre-populates keys before measurement begins."
        echo "Results represent steady-state performance after warm-up."
        echo ""

        # ── Summary table ────────────────────────────────────────────────
        echo "## Summary — Ops/sec"
        echo ""
        printf "| Scenario |"
        for s in "${server_list[@]}"; do
            printf " %s |" "$s"
        done
        echo ""
        printf "|----------|"
        for _ in "${server_list[@]}"; do
            printf "--------:|"
        done
        echo ""

        for scenario in "${scenario_list[@]}"; do
            local label
            label=$(get_scenario_params "$scenario" | cut -d'|' -f4)
            printf "| %s |" "$label"
            for server in "${server_list[@]}"; do
                local ops
                ops=$(grep "^${server},${scenario}," "$csv_file" 2>/dev/null | head -1 | cut -d',' -f8)
                printf " %s |" "${ops:-N/A}"
            done
            echo ""
        done
        echo ""

        # ── Latency summary ─────────────────────────────────────────────
        echo "## Summary — P99 Latency (ms)"
        echo ""
        printf "| Scenario |"
        for s in "${server_list[@]}"; do
            printf " %s |" "$s"
        done
        echo ""
        printf "|----------|"
        for _ in "${server_list[@]}"; do
            printf "--------:|"
        done
        echo ""

        for scenario in "${scenario_list[@]}"; do
            local label
            label=$(get_scenario_params "$scenario" | cut -d'|' -f4)
            printf "| %s |" "$label"
            for server in "${server_list[@]}"; do
                local p99
                p99=$(grep "^${server},${scenario}," "$csv_file" 2>/dev/null | head -1 | cut -d',' -f11)
                printf " %s |" "${p99:-N/A}"
            done
            echo ""
        done
        echo ""

        # ── Per-scenario detail ──────────────────────────────────────────
        for scenario in "${scenario_list[@]}"; do
            local label
            label=$(get_scenario_params "$scenario" | cut -d'|' -f4)
            echo "## ${label}"
            echo ""
            echo "| Server | Ops/sec | Avg (ms) | P50 (ms) | P99 (ms) | P99.9 (ms) | CPU % | Mem (MiB) |"
            echo "|--------|--------:|---------:|---------:|---------:|-----------:|------:|----------:|"

            for server in "${server_list[@]}"; do
                local row
                row=$(grep "^${server},${scenario}," "$csv_file" 2>/dev/null | head -1)
                if [[ -n "$row" ]]; then
                    local ops avg p50 p99 p999 cpu mem
                    ops=$(echo "$row" | cut -d',' -f8)
                    avg=$(echo "$row" | cut -d',' -f9)
                    p50=$(echo "$row" | cut -d',' -f10)
                    p99=$(echo "$row" | cut -d',' -f11)
                    p999=$(echo "$row" | cut -d',' -f12)
                    cpu=$(echo "$row" | cut -d',' -f13)
                    mem=$(echo "$row" | cut -d',' -f14)
                    printf "| %-10s | %s | %s | %s | %s | %s | %s | %s |\n" \
                        "$server" "$ops" "$avg" "$p50" "$p99" "$p999" "$cpu" "$mem"
                else
                    printf "| %-10s | N/A | N/A | N/A | N/A | N/A | N/A | N/A |\n" "$server"
                fi
            done
            echo ""
        done

        # ── Relative performance vs Redis ────────────────────────────────
        if echo "$SERVERS" | grep -q "redis"; then
            echo "## Relative Performance (vs Redis = 100%)"
            echo ""
            printf "| Scenario |"
            for s in "${server_list[@]}"; do
                [[ "$s" == "redis" ]] && continue
                printf " %s |" "$s"
            done
            echo ""
            printf "|----------|"
            for s in "${server_list[@]}"; do
                [[ "$s" == "redis" ]] && continue
                printf "--------:|"
            done
            echo ""

            for scenario in "${scenario_list[@]}"; do
                local label
                label=$(get_scenario_params "$scenario" | cut -d'|' -f4)
                local redis_ops
                redis_ops=$(grep "^redis,${scenario}," "$csv_file" 2>/dev/null | head -1 | cut -d',' -f8)

                printf "| %s |" "$label"
                for server in "${server_list[@]}"; do
                    [[ "$server" == "redis" ]] && continue
                    local ops
                    ops=$(grep "^${server},${scenario}," "$csv_file" 2>/dev/null | head -1 | cut -d',' -f8)
                    if [[ -n "$ops" ]] && [[ -n "$redis_ops" ]] && [[ "$redis_ops" != "0.00" ]]; then
                        local pct
                        pct=$(python3 -c "print(f'{(${ops}/${redis_ops})*100:.1f}%')" 2>/dev/null || echo "N/A")
                        printf " %s |" "$pct"
                    else
                        printf " N/A |"
                    fi
                done
                echo ""
            done
            echo ""
        fi

        echo "---"
        echo ""
        echo "_Report generated by [ferrite-bench](https://github.com/ferritelabs/ferrite-bench) harness v1.0_"

    } > "$report_file"

    ok "Markdown report → ${report_file}"
}

# ── Console summary ──────────────────────────────────────────────────────────

print_console_summary() {
    local csv_file="$1"

    IFS=',' read -ra server_list <<< "$SERVERS"
    IFS=',' read -ra scenario_list <<< "$SCENARIOS"

    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  Benchmark Results — Ops/sec"
    echo "═══════════════════════════════════════════════════════════════════"
    printf "  %-24s" "Scenario"
    for s in "${server_list[@]}"; do
        printf " %14s" "$s"
    done
    echo ""
    echo "  ────────────────────────────────────────────────────────────────"

    for scenario in "${scenario_list[@]}"; do
        printf "  %-24s" "$scenario"
        for server in "${server_list[@]}"; do
            local ops
            ops=$(grep "^${server},${scenario}," "$csv_file" 2>/dev/null | head -1 | cut -d',' -f8)
            printf " %14s" "${ops:-N/A}"
        done
        echo ""
    done
    echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"
    validate_inputs
    check_prereqs

    IFS=',' read -ra server_list <<< "$SERVERS"
    IFS=',' read -ra scenario_list <<< "$SCENARIOS"

    local csv_file="${OUTPUT_DIR}/data_${TIMESTAMP}.csv"
    local report_file="${OUTPUT_DIR}/report_${TIMESTAMP}.md"

    mkdir -p "$OUTPUT_DIR"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║  Ferrite Benchmark Harness                                      ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    info "Configuration:"
    echo "  Servers:   ${SERVERS}"
    echo "  Scenarios: ${SCENARIOS}"
    echo "  Duration:  ${DURATION}s per run"
    echo "  Clients:   ${CLIENTS} per thread × ${THREADS} threads = $((CLIENTS * THREADS)) total"
    echo "  Warm-up:   ${WARMUP}s"
    echo "  Output:    ${OUTPUT_DIR}/"
    echo ""

    trap cleanup EXIT

    start_services

    # CSV header
    echo "server,scenario,label,ratio,pipeline,data_size_bytes,duration_secs,ops_sec,avg_latency_ms,p50_latency_ms,p99_latency_ms,p999_latency_ms,cpu_percent,memory_mib" > "$csv_file"

    local total_runs=$(( ${#server_list[@]} * ${#scenario_list[@]} ))
    local current_run=0

    for scenario in "${scenario_list[@]}"; do
        echo ""
        info "━━━ Scenario: ${scenario} ━━━"

        for server in "${server_list[@]}"; do
            current_run=$((current_run + 1))
            info "[${current_run}/${total_runs}] Running..."
            run_benchmark "$server" "$scenario" "$csv_file"
        done
    done

    echo ""
    info "━━━ Generating reports ━━━"
    ok "CSV data → ${csv_file}"
    generate_report "$csv_file" "$report_file"

    print_console_summary "$csv_file"

    info "Done. ${total_runs} benchmark runs completed."
}

main "$@"
