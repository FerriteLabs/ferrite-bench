#!/usr/bin/env bash
# =============================================================================
# Ferrite Benchmark Runner
# =============================================================================
# One-command benchmark execution with results publishing.
#
# Usage:
#   ./run-benchmarks.sh                    # Run all benchmarks
#   ./run-benchmarks.sh --quick            # Quick run (30s per scenario)
#   ./run-benchmarks.sh --publish          # Run + generate report
#
# Prerequisites:
#   - Docker and Docker Compose
#   - python3 (for report generation)

set -euo pipefail

MODE="${1:-full}"
DURATION=60
[[ "$MODE" == "--quick" ]] && DURATION=30

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

echo "═══════════════════════════════════════════════════════════════"
echo "  Ferrite Benchmark Suite"
echo "  Duration: ${DURATION}s per scenario"
echo "  Output: ${RESULTS_DIR}"
echo "═══════════════════════════════════════════════════════════════"

# ── Start servers ─────────────────────────────────────────────────────────────

echo ""
echo "Starting servers..."
docker compose -f "$SCRIPT_DIR/docker-compose.benchmark.yml" up -d 2>/dev/null || {
    echo "ERROR: Docker Compose failed. Ensure docker-compose.benchmark.yml exists."
    exit 1
}

# Wait for servers
sleep 5
echo "Servers ready."

# ── System info ───────────────────────────────────────────────────────────────

{
    echo "# Benchmark System Info"
    echo "Date: $(date -u)"
    echo "OS: $(uname -srm)"
    echo "CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || lscpu 2>/dev/null | grep 'Model name' | sed 's/.*: //')"
    echo "Memory: $(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.1f GB", $1/1073741824}' || free -h 2>/dev/null | awk '/Mem/{print $2}')"
    echo "Docker: $(docker --version)"
} > "$RESULTS_DIR/system-info.txt"

# ── Run benchmarks ────────────────────────────────────────────────────────────

if [[ -x "$SCRIPT_DIR/benchmarks/harness.sh" ]]; then
    "$SCRIPT_DIR/benchmarks/harness.sh" \
        --servers ferrite,redis \
        --scenarios get,set,mixed,pipeline \
        --duration "$DURATION" \
        --clients 50 \
        --output-dir "$RESULTS_DIR"
else
    echo "Running memtier benchmarks manually..."
    
    for server in ferrite redis; do
        case $server in
            ferrite) PORT=6379 ;;
            redis) PORT=6380 ;;
        esac
        
        for scenario in get set mixed; do
            case $scenario in
                get) RATIO="0:1" ;;
                set) RATIO="1:0" ;;
                mixed) RATIO="1:1" ;;
            esac
            
            echo "  Running $server/$scenario..."
            docker run --rm --network host redislabs/memtier_benchmark:latest \
                -s 127.0.0.1 -p "$PORT" \
                --ratio="$RATIO" --key-pattern=R:R \
                --data-size=128 --key-maximum=1000000 \
                -c 50 -t 4 --test-time="$DURATION" \
                --json-out-file="/dev/stdout" 2>/dev/null \
                > "$RESULTS_DIR/${server}_${scenario}.json" || true
        done
    done
fi

# ── Generate report ───────────────────────────────────────────────────────────

if [[ "$MODE" == "--publish" ]] && [[ -x "$SCRIPT_DIR/benchmarks/report_generator.py" ]]; then
    echo ""
    echo "Generating report..."
    python3 "$SCRIPT_DIR/benchmarks/report_generator.py" \
        --input "$RESULTS_DIR/data.csv" \
        --output "$RESULTS_DIR/report.md" 2>/dev/null || echo "Report generation skipped (no CSV)"
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────

echo ""
echo "Stopping servers..."
docker compose -f "$SCRIPT_DIR/docker-compose.benchmark.yml" down 2>/dev/null || true

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Benchmarks complete!"
echo "  Results: ${RESULTS_DIR}"
echo "═══════════════════════════════════════════════════════════════"
