#!/usr/bin/env bash
# Concord (M5) — CRDT Multi-Region Benchmark Runner
# Usage: ./run.sh [workload]   (converge | metadata | conflict | all)
set -euo pipefail

MOONSHOT="concord"
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

run_convergence() {
    echo "--- convergence-time ---"
    # Stub: awaiting ferrite-bench CLI integration for convergence-time with params from workload.toml
    echo "  [placeholder] convergence-time benchmark not yet wired"
    MISSING_SIGNALS+=("convergence-time")
}

run_metadata_overhead() {
    echo "--- metadata-overhead ---"
    # Stub: awaiting ferrite-bench CLI integration for metadata-overhead with params from workload.toml
    echo "  [placeholder] metadata-overhead benchmark not yet wired"
    MISSING_SIGNALS+=("metadata-overhead")
}

run_conflict_rate() {
    echo "--- conflict-rate ---"
    # Stub: awaiting ferrite-bench CLI integration for conflict-rate with params from workload.toml
    echo "  [placeholder] conflict-rate benchmark not yet wired"
    MISSING_SIGNALS+=("conflict-rate")
}

case "${WORKLOAD}" in
    converge)   run_convergence ;;
    metadata)   run_metadata_overhead ;;
    conflict)   run_conflict_rate ;;
    all)
        run_convergence
        run_metadata_overhead
        run_conflict_rate
        ;;
    *)
        echo "Unknown workload: ${WORKLOAD}" >&2
        echo "Usage: $0 [converge | metadata | conflict | all]" >&2
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
