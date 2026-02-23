# Ferrite Benchmark Methodology

## Overview

This document describes the standardized benchmark methodology for comparing
Ferrite against Redis, Dragonfly, Valkey, and KeyDB. All results published by
the Ferrite project follow this methodology for reproducibility.

## Hardware Specification

All benchmarks run on equivalent hardware:
- **Cloud**: AWS c5.2xlarge (8 vCPUs, 16 GB RAM, EBS gp3)
- **CPU**: Intel Xeon Platinum 8275CL @ 3.0 GHz
- **Memory**: 16 GB DDR4
- **Storage**: 100 GB gp3 SSD (3000 IOPS, 125 MB/s)
- **Network**: Up to 10 Gbps
- **OS**: Ubuntu 22.04 LTS, kernel 5.15+

## Software Versions

| Server | Version | Config |
|--------|---------|--------|
| Ferrite | v0.2.0 | Default (no persistence) |
| Redis | 7.4.x | Default (no persistence, `save ""`) |
| Dragonfly | 1.x | Default |
| Valkey | 8.x | Default (no persistence) |
| KeyDB | latest | Default (server-threads 4) |

## Benchmark Tool

- **memtier_benchmark** v2.0+ (Redis Labs)
- Installed via: `apt-get install memtier-benchmark` or Docker

## Standardized Scenarios

### Scenario 1: GET-only (Cache Read)
```bash
memtier_benchmark -s 127.0.0.1 -p 6379 \
  --ratio=0:1 --key-pattern=R:R \
  --data-size=128 --key-maximum=1000000 \
  -c 50 -t 4 --test-time=60 --hide-histogram
```

### Scenario 2: SET-only (Cache Write)
```bash
memtier_benchmark -s 127.0.0.1 -p 6379 \
  --ratio=1:0 --key-pattern=R:R \
  --data-size=128 --key-maximum=1000000 \
  -c 50 -t 4 --test-time=60 --hide-histogram
```

### Scenario 3: Mixed (50/50 Read/Write)
```bash
memtier_benchmark -s 127.0.0.1 -p 6379 \
  --ratio=1:1 --key-pattern=R:R \
  --data-size=128 --key-maximum=1000000 \
  -c 50 -t 4 --test-time=60 --hide-histogram
```

### Scenario 4: Pipeline 16 (Batched)
```bash
memtier_benchmark -s 127.0.0.1 -p 6379 \
  --ratio=1:1 --key-pattern=R:R \
  --data-size=128 --key-maximum=1000000 \
  --pipeline=16 \
  -c 50 -t 4 --test-time=60 --hide-histogram
```

### Scenario 5: Large Values (10 KB)
```bash
memtier_benchmark -s 127.0.0.1 -p 6379 \
  --ratio=1:1 --key-pattern=R:R \
  --data-size=10240 --key-maximum=100000 \
  -c 50 -t 4 --test-time=60 --hide-histogram
```

### Scenario 6: High Concurrency (200 clients)
```bash
memtier_benchmark -s 127.0.0.1 -p 6379 \
  --ratio=1:1 --key-pattern=R:R \
  --data-size=128 --key-maximum=1000000 \
  -c 200 -t 4 --test-time=60 --hide-histogram
```

## Warm-Up

Each scenario is preceded by a 10-second warm-up run (discarded) to
eliminate cold-start effects and populate caches.

## Metrics Collected

| Metric | Source | Unit |
|--------|--------|------|
| Throughput (ops/sec) | memtier output | ops/sec |
| P50 latency | memtier output | ms |
| P99 latency | memtier output | ms |
| P99.9 latency | memtier output | ms |
| Memory usage (RSS) | `ps -o rss=` | KB |
| CPU usage | `top -bn1` | % |

## Fairness Guarantees

1. **Same hardware**: All servers run on identical instance types
2. **No persistence**: All servers configured with persistence disabled
3. **Default config**: No custom tuning beyond what's listed above
4. **Same client**: Same memtier version, same parameters
5. **Dedicated instances**: No co-located workloads during benchmarks
6. **Multiple runs**: Each scenario run 3 times; median reported
7. **Warm-up**: 10s warm-up before measurement

## Reproducing Results

```bash
cd ferrite-bench
docker compose -f docker-compose.benchmark.yml up -d
./benchmarks/harness.sh --servers ferrite,redis,dragonfly,valkey \
  --scenarios get,set,mixed,pipeline,large-values,high-concurrency \
  --duration 60 --clients 50 --output-dir results/
python3 benchmarks/report_generator.py --input results/data.csv --output results/report.md
```

## Tiered Storage Scenarios (Ferrite Advantage)

These scenarios are unique to Ferrite and demonstrate the tiered storage value:

### Scenario T1: Dataset Exceeding RAM
```bash
# Pre-load 20GB of data (exceeds 16GB RAM)
# Ferrite: transparent disk tiering
# Redis/Dragonfly/Valkey: OOM crash
memtier_benchmark -s 127.0.0.1 -p 6379 \
  --ratio=1:1 --key-pattern=S:S \
  --data-size=1024 --key-maximum=20000000 \
  -c 50 -t 4 --test-time=120
```

### Scenario T2: Hot/Cold Access Pattern
```bash
# 10M keys, 80% reads to 20% of keys (Pareto)
# Measures: hot keys stay in memory, cold keys on disk
memtier_benchmark -s 127.0.0.1 -p 6379 \
  --ratio=0:1 --key-pattern=P:P \
  --data-size=512 --key-maximum=10000000 \
  -c 50 -t 4 --test-time=120
```

## Reporting

Results are published at: https://ferrite.dev/benchmarks/
Raw data (CSV) available at: https://github.com/ferritelabs/ferrite-bench/results/
