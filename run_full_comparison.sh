#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Full Benchmark Comparison — Ferrite vs Redis
#
# Orchestrates the complete benchmark workflow:
#   1. Runs benchmarks against Ferrite
#   2. Runs benchmarks against Redis
#   3. Generates a side-by-side comparison report
#
# Usage:
#   ./run_full_comparison.sh                    # Both servers must be running
#   ./run_full_comparison.sh --ferrite-only     # Benchmark Ferrite only
#   ./run_full_comparison.sh --start-servers    # Start servers, benchmark, stop
#
# Prerequisites:
#   - redis-benchmark, jq, python3 installed
#   - Ferrite running on port 6380 (or set FERRITE_PORT)
#   - Redis running on port 6379 (or set REDIS_PORT)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/results"

# ── Configuration ────────────────────────────────────────────────────────────

FERRITE_HOST="${FERRITE_HOST:-127.0.0.1}"
FERRITE_PORT="${FERRITE_PORT:-6380}"
REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"

FERRITE_ONLY=false
START_SERVERS=false
FERRITE_PID=""
REDIS_PID=""

for arg in "$@"; do
    case "$arg" in
        --ferrite-only) FERRITE_ONLY=true ;;
        --start-servers) START_SERVERS=true ;;
        --help|-h)
            echo "Usage: $0 [--ferrite-only] [--start-servers]"
            echo ""
            echo "Options:"
            echo "  --ferrite-only    Only benchmark Ferrite (skip Redis)"
            echo "  --start-servers   Auto-start Ferrite and Redis servers"
            echo ""
            echo "Environment variables:"
            echo "  FERRITE_HOST, FERRITE_PORT  Ferrite connection (default: 127.0.0.1:6380)"
            echo "  REDIS_HOST, REDIS_PORT      Redis connection (default: 127.0.0.1:6379)"
            echo "  FERRITE_BIN                 Path to Ferrite binary"
            echo "  BENCH_CLIENTS, BENCH_REQUESTS, BENCH_DATA_SIZE, BENCH_PIPELINE"
            exit 0
            ;;
    esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

cleanup() {
    if [[ -n "$FERRITE_PID" ]]; then
        info "Stopping Ferrite (PID: ${FERRITE_PID})..."
        kill "$FERRITE_PID" 2>/dev/null || true
        wait "$FERRITE_PID" 2>/dev/null || true
    fi
    if [[ -n "$REDIS_PID" ]]; then
        info "Stopping Redis (PID: ${REDIS_PID})..."
        kill "$REDIS_PID" 2>/dev/null || true
        wait "$REDIS_PID" 2>/dev/null || true
    fi
}

wait_for_server() {
    local name="$1"
    local host="$2"
    local port="$3"
    local retries=30
    local count=0

    info "Waiting for ${name} on ${host}:${port}..."
    while ! redis-benchmark -h "$host" -p "$port" -t ping -n 1 --csv &>/dev/null; do
        count=$((count + 1))
        if [[ $count -ge $retries ]]; then
            error "${name} failed to start within ${retries} seconds"
            return 1
        fi
        sleep 1
    done
    ok "${name} is ready."
}

# ── Server Management ────────────────────────────────────────────────────────

start_servers() {
    local ferrite_bin="${FERRITE_BIN:-}"

    # Find Ferrite binary
    if [[ -z "$ferrite_bin" ]]; then
        for candidate in \
            "${SCRIPT_DIR}/../ferrite/target/release/ferrite" \
            "${SCRIPT_DIR}/../ferrite/target/debug/ferrite"; do
            if [[ -x "$candidate" ]]; then
                ferrite_bin="$candidate"
                break
            fi
        done
    fi

    if [[ -z "$ferrite_bin" || ! -x "$ferrite_bin" ]]; then
        error "Ferrite binary not found. Build with: cd ../ferrite && cargo build --release"
        error "Or set FERRITE_BIN=/path/to/ferrite"
        exit 1
    fi

    trap cleanup EXIT

    info "Starting Ferrite on port ${FERRITE_PORT}..."
    "$ferrite_bin" --port "$FERRITE_PORT" &
    FERRITE_PID=$!
    wait_for_server "Ferrite" "$FERRITE_HOST" "$FERRITE_PORT"

    if [[ "$FERRITE_ONLY" == false ]]; then
        if ! command -v redis-server &>/dev/null; then
            warn "redis-server not found, skipping Redis benchmark"
            FERRITE_ONLY=true
        else
            info "Starting Redis on port ${REDIS_PORT}..."
            redis-server --port "$REDIS_PORT" --save "" --appendonly no --daemonize no &
            REDIS_PID=$!
            wait_for_server "Redis" "$REDIS_HOST" "$REDIS_PORT"
        fi
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Full Benchmark Comparison — Ferrite vs Redis               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    mkdir -p "$RESULTS_DIR"

    if [[ "$START_SERVERS" == true ]]; then
        start_servers
    fi

    # Run Ferrite benchmarks
    info "═══ Running Ferrite benchmarks ═══"
    BENCH_HOST="$FERRITE_HOST" BENCH_PORT="$FERRITE_PORT" \
        "${SCRIPT_DIR}/benchmarks/ferrite_bench.sh"

    # Run Redis benchmarks
    if [[ "$FERRITE_ONLY" == false ]]; then
        echo ""
        info "═══ Running Redis benchmarks ═══"
        BENCH_HOST="$REDIS_HOST" BENCH_PORT="$REDIS_PORT" \
            "${SCRIPT_DIR}/benchmarks/redis_bench.sh"
    fi

    # Generate comparison report
    local ferrite_json="${RESULTS_DIR}/ferrite_latest.json"
    local redis_json="${RESULTS_DIR}/redis_latest.json"

    if [[ -f "$ferrite_json" && -f "$redis_json" && "$FERRITE_ONLY" == false ]]; then
        echo ""
        info "═══ Generating comparison report ═══"
        local timestamp
        timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
        local comparison_md="${RESULTS_DIR}/comparison_${timestamp}.md"
        local comparison_json="${RESULTS_DIR}/comparison_${timestamp}.json"

        python3 "${SCRIPT_DIR}/comparison/compare.py" \
            "$ferrite_json" "$redis_json" \
            -o "$comparison_md" \
            --json "$comparison_json"

        # Create latest symlinks
        ln -sf "$(basename "$comparison_md")" "${RESULTS_DIR}/comparison_latest.md"
        ln -sf "$(basename "$comparison_json")" "${RESULTS_DIR}/comparison_latest.json"

        echo ""
        ok "Comparison report → ${comparison_md}"
    elif [[ "$FERRITE_ONLY" == true ]]; then
        info "Ferrite-only mode — skipping comparison."
    else
        warn "Missing result files for comparison."
        [[ ! -f "$ferrite_json" ]] && warn "  Missing: ${ferrite_json}"
        [[ ! -f "$redis_json" ]] && warn "  Missing: ${redis_json}"
    fi

    echo ""
    ok "All benchmarks complete. Results in ${RESULTS_DIR}/"
}

main "$@"
