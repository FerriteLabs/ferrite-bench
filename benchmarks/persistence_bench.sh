#!/usr/bin/env bash
# persistence_bench.sh — Measure throughput impact of persistence modes
#
# Tests Ferrite with: no persistence, AOF-everysec, AOF-always
# Compares against Redis with same persistence configurations.
set -euo pipefail

FERRITE_PORT="${FERRITE_PORT:-6380}"
REDIS_PORT="${REDIS_PORT:-6381}"
CLIENTS="${CLIENTS:-8}"
THREADS="${THREADS:-4}"
DURATION="${DURATION:-30}"
DATA_SIZE="${DATA_SIZE:-256}"
OUTDIR="${OUTDIR:-results/persistence-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$OUTDIR"

echo "=== Persistence Impact Benchmark ==="
echo "Duration: ${DURATION}s per scenario | Data size: ${DATA_SIZE}B"
echo "Output:  $OUTDIR"
echo ""

run_bench() {
  local label="$1" port="$2" outfile="$3"
  echo "  Running: $label"
  memtier_benchmark \
    -s localhost -p "$port" \
    --protocol=redis \
    --threads="$THREADS" --clients="$CLIENTS" \
    --data-size="$DATA_SIZE" --key-maximum=1000000 \
    --ratio=1:1 --test-time="$DURATION" \
    --hide-histogram \
    --json-out-file="$outfile" \
    2>&1 | grep -E "Totals|Ops/sec" | head -2
}

configure_persistence() {
  local port="$1" mode="$2"
  case "$mode" in
    none)
      redis-cli -p "$port" CONFIG SET appendonly no 2>/dev/null || true
      redis-cli -p "$port" CONFIG SET save "" 2>/dev/null || true
      ;;
    aof-everysec)
      redis-cli -p "$port" CONFIG SET appendonly yes 2>/dev/null || true
      redis-cli -p "$port" CONFIG SET appendfsync everysec 2>/dev/null || true
      ;;
    aof-always)
      redis-cli -p "$port" CONFIG SET appendonly yes 2>/dev/null || true
      redis-cli -p "$port" CONFIG SET appendfsync always 2>/dev/null || true
      ;;
  esac
  sleep 1
}

for mode in none aof-everysec aof-always; do
  echo "--- Persistence mode: $mode ---"

  for db_name in ferrite redis; do
    port_var="${db_name^^}_PORT"
    port="${!port_var}"
    configure_persistence "$port" "$mode"
    run_bench "${db_name} ($mode)" "$port" "$OUTDIR/${db_name}_${mode}.json"
  done
  echo ""
done

echo "=== Summary ==="
echo "Compare results in: $OUTDIR"
echo "Use: python3 benchmarks/report_generator.py $OUTDIR/*.json"
