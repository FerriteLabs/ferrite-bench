#!/usr/bin/env bash
set -euo pipefail

# Resource Efficiency Benchmark
# Measures: keys/MB, bytes overhead per key, ops/CPU-second
#
# Usage: ./resource_efficiency.sh [--ferrite-port PORT] [--output-dir DIR]

FERRITE_PORT="${FERRITE_PORT:-6379}"
OUTPUT_DIR="${OUTPUT_DIR:-.}"
REDIS_CLI="${REDIS_CLI:-redis-cli}"

SIZES=(1000 10000 100000)
VALUE_SIZES=(64 256 1024 4096)

echo "=== Ferrite Resource Efficiency Benchmark ==="
echo "Port: $FERRITE_PORT"
echo "Output: $OUTPUT_DIR"
echo ""

# CSV header
OUTPUT="$OUTPUT_DIR/resource_efficiency_$(date +%Y%m%d_%H%M%S).csv"
echo "num_keys,value_size_bytes,rss_kb,keys_per_mb,overhead_per_key_bytes,theoretical_bytes,actual_bytes" > "$OUTPUT"

for num_keys in "${SIZES[@]}"; do
  for vsize in "${VALUE_SIZES[@]}"; do
    echo "Testing: $num_keys keys × ${vsize}B values..."

    # Flush
    $REDIS_CLI -p "$FERRITE_PORT" FLUSHALL > /dev/null 2>&1 || true
    sleep 0.5

    # Get baseline memory
    baseline_rss=$($REDIS_CLI -p "$FERRITE_PORT" INFO memory 2>/dev/null | grep "used_memory:" | cut -d: -f2 | tr -d '\r' || echo "0")

    # Populate
    for i in $(seq 1 "$num_keys"); do
      value=$(head -c "$vsize" /dev/urandom | base64 | head -c "$vsize")
      $REDIS_CLI -p "$FERRITE_PORT" SET "bench:key:$i" "$value" > /dev/null 2>&1
    done

    # Measure memory after population
    after_rss=$($REDIS_CLI -p "$FERRITE_PORT" INFO memory 2>/dev/null | grep "used_memory:" | cut -d: -f2 | tr -d '\r' || echo "0")

    # Calculate metrics
    delta_bytes=$((after_rss - baseline_rss))
    delta_kb=$((delta_bytes / 1024))
    theoretical_bytes=$((num_keys * (vsize + 20)))  # key + value + ~20 bytes overhead estimate

    if [ "$delta_bytes" -gt 0 ]; then
      keys_per_mb=$((num_keys * 1048576 / delta_bytes))
      overhead_per_key=$((delta_bytes / num_keys - vsize))
    else
      keys_per_mb=0
      overhead_per_key=0
    fi

    echo "  RSS delta: ${delta_kb}KB, Keys/MB: $keys_per_mb, Overhead/key: ${overhead_per_key}B"
    echo "$num_keys,$vsize,$delta_kb,$keys_per_mb,$overhead_per_key,$theoretical_bytes,$delta_bytes" >> "$OUTPUT"

    # Cleanup
    $REDIS_CLI -p "$FERRITE_PORT" FLUSHALL > /dev/null 2>&1 || true
  done
done

echo ""
echo "Results written to: $OUTPUT"
echo ""
echo "=== Summary ==="
column -t -s, "$OUTPUT"
