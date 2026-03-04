#!/usr/bin/env bash
# tiered_storage_bench.sh — Benchmark Ferrite's tiered storage advantage
# Loads data beyond RAM capacity to show hot/warm/cold tier behavior.
#
# Prerequisites: memtier_benchmark, running Ferrite (port 6380) + Redis (port 6381)
set -euo pipefail

FERRITE_PORT="${FERRITE_PORT:-6380}"
REDIS_PORT="${REDIS_PORT:-6381}"
CLIENTS="${CLIENTS:-8}"
THREADS="${THREADS:-4}"
DURATION="${DURATION:-60}"
OUTDIR="${OUTDIR:-results/tiered-storage-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$OUTDIR"

echo "=== Tiered Storage Benchmark ==="
echo "Ferrite: localhost:$FERRITE_PORT"
echo "Redis:   localhost:$REDIS_PORT"
echo "Output:  $OUTDIR"
echo ""

# Capture system info
bash "$(dirname "$0")/system_info.sh" > "$OUTDIR/system_info.json" 2>/dev/null || true

# --- Scenario 1: Fill beyond memory limit ---
# Use 1KB values with 2M keys = ~2GB total data
# Ferrite should tier to disk; Redis may OOM or evict
echo "--- Phase 1: Loading 2M keys (1KB values) ---"

for db_name in ferrite redis; do
  port_var="${db_name^^}_PORT"
  port="${!port_var}"
  echo "Loading $db_name (port $port)..."
  memtier_benchmark \
    -s localhost -p "$port" \
    --protocol=redis \
    --threads="$THREADS" --clients="$CLIENTS" \
    --data-size=1024 --key-maximum=2000000 --key-prefix="ts:" \
    --ratio=1:0 --requests=2000000 \
    --hide-histogram \
    --json-out-file="$OUTDIR/${db_name}_load.json" \
    2>&1 | tail -5
  echo ""
done

# --- Scenario 2: Read workload (hot + cold keys) ---
# Zipfian-like: 80% of reads go to first 200K keys (hot), 20% to remaining (cold)
echo "--- Phase 2: Mixed read workload (hot keys + cold keys) ---"

for db_name in ferrite redis; do
  port_var="${db_name^^}_PORT"
  port="${!port_var}"

  echo "Benchmarking $db_name hot keys (0-200K)..."
  memtier_benchmark \
    -s localhost -p "$port" \
    --protocol=redis \
    --threads="$THREADS" --clients="$CLIENTS" \
    --data-size=1024 --key-maximum=200000 --key-prefix="ts:" \
    --ratio=0:1 --test-time="$DURATION" \
    --hide-histogram \
    --json-out-file="$OUTDIR/${db_name}_hot_reads.json" \
    2>&1 | tail -3

  echo "Benchmarking $db_name cold keys (1.8M-2M)..."
  memtier_benchmark \
    -s localhost -p "$port" \
    --protocol=redis \
    --threads="$THREADS" --clients="$CLIENTS" \
    --data-size=1024 --key-minimum=1800000 --key-maximum=2000000 --key-prefix="ts:" \
    --ratio=0:1 --test-time="$DURATION" \
    --hide-histogram \
    --json-out-file="$OUTDIR/${db_name}_cold_reads.json" \
    2>&1 | tail -3
  echo ""
done

# --- Scenario 3: Memory utilization comparison ---
echo "--- Phase 3: Memory utilization ---"
for db_name in ferrite redis; do
  port_var="${db_name^^}_PORT"
  port="${!port_var}"
  echo "$db_name memory usage:"
  redis-cli -p "$port" INFO memory 2>/dev/null | grep -E "used_memory_human|maxmemory_human" || echo "  (unable to connect)"
  echo ""
done

echo "=== Benchmark complete. Results in: $OUTDIR ==="
