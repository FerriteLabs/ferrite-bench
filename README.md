# Ferrite Benchmarks

[![Nightly Benchmark](https://github.com/ferritelabs/ferrite-bench/actions/workflows/nightly-bench.yml/badge.svg)](https://github.com/ferritelabs/ferrite-bench/actions/workflows/nightly-bench.yml)

Performance comparison benchmarks for [Ferrite](https://github.com/ferritelabs/ferrite).

External benchmarks comparing Ferrite against Redis, Dragonfly, KeyDB, and other key-value stores.

> **Note:** Cargo-integrated benchmarks (`criterion`) live in the main [ferrite](https://github.com/ferritelabs/ferrite) repository under `benches/`.

## Structure

```
comparison/
├── run_comparison.sh   # Automated Ferrite vs Redis benchmark script
├── README.md           # Detailed usage and configuration
└── results/            # Generated CSV output (gitignored)
```

## Quick Start

```bash
# Prerequisites: redis-benchmark (brew install redis / apt install redis-tools)

# Start Ferrite and Redis, then:
cd comparison
./run_comparison.sh
```

See [comparison/README.md](comparison/README.md) for detailed configuration and examples.

## Competitive Benchmarks (memtier)

Docker-based benchmark suite comparing Ferrite against Redis 7, Dragonfly, and KeyDB using [memtier_benchmark](https://github.com/RedisLabs/memtier_benchmark).

### Prerequisites

- Docker and Docker Compose v2
- Python 3 (for JSON result parsing)

### Quick Start

```bash
# Run the full competitive benchmark (all 4 servers)
./run_memtier_comparison.sh

# Benchmark Ferrite only
./run_memtier_comparison.sh --ferrite-only
```

### What It Does

1. Starts Ferrite, Redis 7, Dragonfly, and KeyDB in Docker containers
2. Runs memtier_benchmark against each server with identical settings
3. Tests 6 scenarios: SET-only, GET-only, mixed 50/50 — each with pipeline=1 and pipeline=16
4. Outputs CSV results to `comparison/results/`
5. Generates a markdown summary table with ops/sec, avg latency, p50, and p99

### Default Parameters

| Parameter | Value |
|-----------|-------|
| Threads | 4 |
| Clients per thread | 50 (200 total) |
| Requests | 1,000,000 |
| Data size | 256 bytes |
| Key range | 1–1,000,000 |
| Pipeline sizes | 1 (no pipeline), 16 |

### Configuration

Override defaults via environment variables:

```bash
MEMTIER_THREADS=8 MEMTIER_CLIENTS=100 MEMTIER_REQUESTS=2000000 ./run_memtier_comparison.sh
```

| Variable | Default | Description |
|----------|---------|-------------|
| `MEMTIER_THREADS` | `4` | memtier worker threads |
| `MEMTIER_CLIENTS` | `50` | Clients per thread |
| `MEMTIER_REQUESTS` | `1000000` | Total requests per scenario |
| `MEMTIER_DATA_SIZE` | `256` | Value payload size in bytes |
| `MEMTIER_KEY_MIN` | `1` | Key range minimum |
| `MEMTIER_KEY_MAX` | `1000000` | Key range maximum |

### Servers Under Test

| Server | Image | Port |
|--------|-------|------|
| Ferrite | `ferritelabs/ferrite:latest` | 6380 |
| Redis 7 | `redis:7-alpine` | 6381 |
| Dragonfly | `docker.dragonflydb.io/dragonflydb/dragonfly` | 6382 |
| KeyDB | `eqalpha/keydb` | 6383 |

### Output

- **CSV** — `comparison/results/memtier_YYYYMMDD_HHMMSS.csv`
- **Markdown** — `comparison/results/summary_YYYYMMDD_HHMMSS.md`

### Architecture

```
docker-compose.benchmark.yml    # Defines all server containers + memtier runner
run_memtier_comparison.sh       # Orchestrates benchmark scenarios
comparison/results/             # Generated output (gitignored)
```

## Vector Search Benchmarks

Compare Ferrite's vector search (HNSW) against Qdrant and Redis with RedisSearch:

```bash
# Run vector benchmarks (requires Ferrite on port 6380)
./benchmarks/vector_comparison.sh

# Ferrite only (skip competitors)
./benchmarks/vector_comparison.sh --ferrite-only

# Quick smoke test (1k vectors, 100 queries)
./benchmarks/vector_comparison.sh --quick

# Customize parameters
VECTOR_DIM=768 VECTOR_COUNT=50000 NUM_QUERIES=5000 ./benchmarks/vector_comparison.sh
```

### Starting Competitor Services

```bash
# Start all services (including Qdrant) via Docker Compose
docker compose -f docker-compose.benchmark.yml up -d

# Or run Qdrant standalone
docker run -p 6333:6333 qdrant/qdrant

# Redis with RedisSearch
docker run -p 6379:6379 redis/redis-stack-server:latest
```

### What It Measures

| Metric | Description |
|--------|-------------|
| Index throughput | Vectors inserted per second |
| Search QPS | Queries per second (sequential, no pipelining) |
| Latency p50/p95/p99 | KNN search latency percentiles (ms) |

### Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `VECTOR_DIM` | `384` | Vector dimensionality |
| `VECTOR_COUNT` | `10000` | Number of vectors to index |
| `SEARCH_K` | `10` | Neighbors to retrieve per query |
| `NUM_QUERIES` | `1000` | Number of search queries |
| `QDRANT_HOST` | `127.0.0.1` | Qdrant host |
| `QDRANT_PORT` | `6333` | Qdrant HTTP port |

Results are saved to `benchmarks/results/` with a markdown comparison report.

## Environment Requirements

| Requirement | Minimum Version | Notes |
|---|---|---|
| Docker | 24.0+ | Docker Engine with Compose v2 |
| Python | 3.8+ | For JSON result parsing scripts |
| Bash | 4.0+ | Required for associative arrays |
| GNU coreutils | — | `date`, `awk`, `sort` used in scripts |

Ensure Docker has at least **4 GB of RAM** allocated when running the full competitive benchmark suite (all 4 servers run concurrently).

## License

Apache-2.0
