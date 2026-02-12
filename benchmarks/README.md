# Ferrite Benchmark Suite

Comprehensive benchmark scripts for measuring Ferrite and Redis performance across common data structure operations.

## What's Measured

Each benchmark script tests the following operations using `redis-benchmark`:

| Operation | Description |
|-----------|-------------|
| `SET` | String write |
| `GET` | String read |
| `HSET` | Hash field write |
| `HGET` | Hash field read |
| `LPUSH` | List push (head) |
| `LPOP` | List pop (head) |
| `SADD` | Set member add |
| `ZADD` | Sorted set member add |

For each operation, the following metrics are captured:

- **Throughput** — Requests per second (ops/sec)
- **Latency** — Average, P50, P99, P99.9

Results are saved in both **JSON** and **Markdown table** formats under `results/` with timestamps.

## Prerequisites

- **redis-benchmark** — Install with `brew install redis` (macOS) or `apt install redis-tools` (Linux)
- **jq** — Install with `brew install jq` (macOS) or `apt install jq` (Linux)
- **Ferrite** and/or **Redis** server running and accessible

## Hardware Requirements

For reproducible, production-representative results:

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 4 cores | 8+ cores (dedicated, no hyperthreading noise) |
| RAM | 4 GB | 16+ GB |
| Network | localhost | localhost (avoids network jitter) |
| Disk | SSD | NVMe SSD |
| OS | Linux / macOS | Linux (kernel 5.10+ for io_uring) |

**Tips for consistent results:**

- Disable CPU frequency scaling (`cpupower frequency-set -g performance`)
- Close background applications
- Run benchmarks at least 3 times and compare for stability
- Use the same hardware for both Ferrite and Redis runs

## Quick Start

```bash
# 1. Start Ferrite (default port 6380)
cargo run --release --manifest-path ../ferrite/Cargo.toml -- --port 6380 &

# 2. Run Ferrite benchmark
./ferrite_bench.sh

# 3. Start Redis (default port 6379)
redis-server --port 6379 --save "" --appendonly no &

# 4. Run Redis benchmark
./redis_bench.sh

# 5. Compare results (from repo root)
cd ..
python3 comparison/compare.py results/ferrite_latest.json results/redis_latest.json
```

Or use the orchestrator from the repo root:

```bash
./run_full_comparison.sh
```

## Configuration

All scripts accept environment variable overrides:

| Variable | Default | Description |
|----------|---------|-------------|
| `BENCH_HOST` | `127.0.0.1` | Server host |
| `BENCH_PORT` | `6380` / `6379` | Server port (Ferrite / Redis) |
| `BENCH_CLIENTS` | `50` | Number of concurrent clients |
| `BENCH_REQUESTS` | `100000` | Total requests per operation |
| `BENCH_DATA_SIZE` | `256` | Value payload size in bytes |
| `BENCH_PIPELINE` | `1` | Pipeline depth |
| `BENCH_THREADS` | `4` | Number of benchmark threads |

### Examples

```bash
# High-concurrency test
BENCH_CLIENTS=200 BENCH_REQUESTS=500000 ./ferrite_bench.sh

# Pipelined throughput
BENCH_PIPELINE=16 ./ferrite_bench.sh

# Large payloads
BENCH_DATA_SIZE=4096 ./ferrite_bench.sh
```

## Output Format

### JSON (`results/<server>_<timestamp>.json`)

```json
{
  "server": "ferrite",
  "timestamp": "2025-01-15T10:30:00Z",
  "config": {
    "host": "127.0.0.1",
    "port": 6380,
    "clients": 50,
    "requests": 100000,
    "data_size": 256,
    "pipeline": 1,
    "threads": 4
  },
  "results": [
    {
      "operation": "SET",
      "ops_per_sec": 125000.00,
      "avg_latency_ms": 0.400,
      "p50_latency_ms": 0.350,
      "p99_latency_ms": 1.200,
      "p999_latency_ms": 2.500
    }
  ]
}
```

### Markdown (`results/<server>_<timestamp>.md`)

A GitHub-flavored markdown table with all operations and metrics, suitable for pasting into PRs or issues.

## Other Benchmarks

- **[vector_comparison.sh](vector_comparison.sh)** — Vector search (KNN) benchmark comparing Ferrite vs Redis+RedisSearch
- **[comparison/run_comparison.sh](../comparison/run_comparison.sh)** — Lightweight `redis-benchmark` comparison
- **[run_memtier_comparison.sh](../run_memtier_comparison.sh)** — Docker-based memtier competitive benchmark (Ferrite vs Redis vs Dragonfly vs KeyDB)
