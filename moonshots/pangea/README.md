# Pangea (M6) — CXL / Tiered-Memory Benchmarks

## What it measures

Pangea extends Ferrite's storage hierarchy to CXL-attached memory tiers.
These benchmarks quantify promotion costs, working-set sensitivity, and
NUMA-aware placement effectiveness.

### Workloads

| Benchmark | Description |
|-----------|-------------|
| `tier-promotion-cost` | Latency penalty when reading a key migrated CXL → DRAM |
| `working-set-perf` | Throughput at 0.5×, 1×, 2× DRAM-only working-set sizes |
| `numa-locality` | Cross-socket vs same-socket access latency on CXL |

## Interpreting results

- **tier-promotion-cost**: Microseconds of additional latency when a cold key
  is promoted from CXL to DRAM tier. Lower is better. Measures the hot-path
  cost of the tiering engine.
- **working-set-perf**: Throughput (ops/sec) as the working set exceeds DRAM
  capacity. At 0.5× everything fits in DRAM; at 2× half is on CXL. The ratio
  between tiers reveals tiering effectiveness.
- **numa-locality**: Ratio of cross-socket to same-socket latency. Closer to
  1.0 is better. Tests whether the allocator respects NUMA topology for CXL
  devices.

## Running

```bash
./run.sh            # full suite
./run.sh tier       # single workload
```

Results are written to `results/` as JSON (gitignored).

## Hardware requirements

These benchmarks require CXL-capable hardware or can be simulated with
`numactl --membind` on multi-socket systems. See `workload.toml` for
simulation mode settings.
