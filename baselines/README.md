# Baseline Benchmark Results

Reference benchmark results for Ferrite v0.2.0 compared against Redis 7.4, Dragonfly 1.x, and KeyDB latest.

## Hardware

| Component | Specification |
|-----------|--------------|
| Instance | AWS c5.2xlarge |
| vCPU | 8 (Intel Xeon Platinum 8275CL) |
| Memory | 16 GB |
| Storage | 100 GB gp3 SSD (3000 IOPS) |
| Network | Up to 10 Gbps |
| OS | Ubuntu 22.04 LTS (kernel 6.5) |

## Tool

- **memtier_benchmark** v2.0.0
- 4 threads, 50 clients per thread (200 total)
- 1,000,000 requests per scenario
- 256-byte values, key range 1–1,000,000

## Files

| File | Description |
|------|-------------|
| `v0.2.0-throughput.csv` | Throughput comparison (ops/sec) |
| `v0.2.0-latency.csv` | Latency percentiles (ms) |
| `v0.2.0-summary.md` | Human-readable summary table |

## How to Reproduce

```bash
# Start all servers via Docker Compose
docker compose -f docker-compose.benchmark.yml up -d

# Run the full comparison
./run_memtier_comparison.sh

# Results are saved to comparison/results/
```

## Updating Baselines

After a new release, run the benchmarks on the reference hardware and copy the results:

```bash
cp comparison/results/data_*.csv baselines/v<VERSION>-throughput.csv
cp comparison/results/summary_*.md baselines/v<VERSION>-summary.md
```

Baselines are committed to the repository (not gitignored) to serve as published reference points.

## Disclaimer

Results are specific to the test hardware and configuration. Your results may vary based on hardware, OS, kernel version, and workload patterns. Always benchmark on your own infrastructure before making production decisions.
