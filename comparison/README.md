# Ferrite vs Redis Comparison Benchmarks

External benchmark comparisons using `redis-benchmark` to measure Ferrite against Redis and other key-value stores.

## Quick Start

```bash
# Start Ferrite on port 6380
cargo run --release --manifest-path ../../ferrite/Cargo.toml -- --port 6380 &

# Start Redis on port 6379 (optional, for comparison)
redis-server --port 6379 &

# Run comparison
./run_comparison.sh
```

## Configuration

All settings are configurable via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `FERRITE_HOST` | `127.0.0.1` | Ferrite server host |
| `FERRITE_PORT` | `6380` | Ferrite server port |
| `REDIS_HOST` | `127.0.0.1` | Redis server host |
| `REDIS_PORT` | `6379` | Redis server port |
| `BENCH_CLIENTS` | `50` | Number of concurrent clients |
| `BENCH_REQUESTS` | `100000` | Total number of requests |
| `BENCH_DATA_SIZE` | `256` | Payload size in bytes |
| `BENCH_PIPELINE` | `1` | Pipeline depth (1 = no pipelining) |

## Examples

```bash
# Benchmark Ferrite only
./run_comparison.sh --ferrite-only

# High-concurrency test
BENCH_CLIENTS=200 BENCH_REQUESTS=1000000 ./run_comparison.sh

# Pipelined throughput test
BENCH_PIPELINE=16 ./run_comparison.sh

# Large payload test
BENCH_DATA_SIZE=4096 ./run_comparison.sh
```

## Output

Results are saved as CSV files in `results/` with timestamps. The script outputs:

1. **Per-system results** — Requests/sec and average latency per command
2. **Side-by-side comparison** — Ferrite/Redis ratio for each command (when both are available)

## Prerequisites

- `redis-benchmark` — Install with `brew install redis` (macOS) or `apt install redis-tools` (Linux)

## Methodology

- All benchmarks use `redis-benchmark` for consistency
- Each run tests: SET, GET, INCR, LPUSH, RPUSH, LPOP, RPOP, SADD, HSET, PING
- Results include raw CSV for downstream analysis
- Run on identical hardware for fair comparison
