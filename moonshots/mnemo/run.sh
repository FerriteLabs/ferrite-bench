#!/usr/bin/env bash
# Mnemo (M1) — Semantic Memory Benchmark Runner
# Usage: ./run.sh [workload]   (recall | write | longmemeval | all)
set -euo pipefail

MOONSHOT="mnemo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/results"
WORKLOAD="${1:-all}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RESULT_FILE="${RESULTS_DIR}/${MOONSHOT}-${TIMESTAMP}.json"

export FERRITE_BENCH_SEED="${FERRITE_BENCH_SEED:-42}"

# ---------------------------------------------------------------------------
# 1. Clean state
# ---------------------------------------------------------------------------
echo "=== [$MOONSHOT] Cleaning previous state ==="
docker compose -f "${SCRIPT_DIR}/../../docker-compose.benchmark.yml" down -v 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. Print versions
# ---------------------------------------------------------------------------
echo "=== [$MOONSHOT] Environment ==="
echo "ferrite:  $(ferrite --version 2>/dev/null || echo 'not found')"
echo "kernel:   $(uname -srm)"
echo "cpu:      $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null || sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')"
echo "libc:     $(ldd --version 2>&1 | head -1 || echo 'N/A')"
echo "seed:     ${FERRITE_BENCH_SEED}"
echo "workload: ${WORKLOAD}"
echo ""

# ---------------------------------------------------------------------------
# 3. Ensure results directory exists
# ---------------------------------------------------------------------------
mkdir -p "${RESULTS_DIR}"

# ---------------------------------------------------------------------------
# 4. Run workloads
# ---------------------------------------------------------------------------
MISSING_SIGNALS=()

run_recall_latency() {
    echo "--- recall-latency ---"
    # Stub: awaiting ferrite-bench CLI integration for recall-latency with params from workload.toml
    echo "  [placeholder] recall-latency benchmark not yet wired"
    MISSING_SIGNALS+=("recall-latency")
}

run_write_throughput() {
    echo "--- write-throughput ---"
    # Stub: awaiting ferrite-bench CLI integration for write-throughput with params from workload.toml
    echo "  [placeholder] write-throughput benchmark not yet wired"
    MISSING_SIGNALS+=("write-throughput")
}

run_longmemeval() {
    echo "--- eval-longmemeval ---"
    # Stub: awaiting ferrite-bench CLI integration for eval-longmemeval with params from workload.toml
    echo "  [placeholder] eval-longmemeval benchmark not yet wired"
    MISSING_SIGNALS+=("eval-longmemeval")
}

case "${WORKLOAD}" in
    recall)     run_recall_latency ;;
    write)      run_write_throughput ;;
    longmemeval) run_longmemeval ;;
    all)
        run_recall_latency
        run_write_throughput
        run_longmemeval
        ;;
    *)
        echo "Unknown workload: ${WORKLOAD}" >&2
        echo "Usage: $0 [recall | write | longmemeval | all]" >&2
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# 5. Write result stub
# ---------------------------------------------------------------------------
cat > "${RESULT_FILE}" <<EOF
{
  "moonshot": "${MOONSHOT}",
  "benchmark": "${WORKLOAD}",
  "version": "$(ferrite --version 2>/dev/null || echo 'unknown')",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "duration_s": 0,
  "seed": ${FERRITE_BENCH_SEED},
  "host": {
    "kernel": "$(uname -srm)",
    "cpu": "$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')",
    "ram_gib": 0
  },
  "params": {},
  "metrics": {}
}
EOF

echo ""
echo "=== [$MOONSHOT] Results written to ${RESULT_FILE} ==="

# ---------------------------------------------------------------------------
# 6. Exit non-zero if required signals are missing
# ---------------------------------------------------------------------------
if [ ${#MISSING_SIGNALS[@]} -gt 0 ]; then
    echo ""
    echo "ERROR: Missing signals: ${MISSING_SIGNALS[*]}" >&2
    echo "Wire the benchmark commands in run.sh before using in CI." >&2
    exit 1
fi
