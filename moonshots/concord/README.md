# Concord (M5) — CRDT Multi-Region Benchmarks

## What it measures

Concord adds conflict-free replicated data types (CRDTs) for multi-region
active-active replication. These benchmarks quantify convergence speed,
metadata overhead, and conflict resolution effectiveness.

### Workloads

| Benchmark | Description |
|-----------|-------------|
| `convergence-time` | Time for 2-region updates to converge after partition heal |
| `metadata-overhead` | Bytes of CRDT metadata per key for COUNTER / OR-SET |
| `conflict-rate` | % of conflicting writes auto-resolved at given write skew |

## Interpreting results

- **convergence-time**: Wall-clock time from partition heal to full consistency.
  Lower is better. Tested with simulated 2-region topology.
- **metadata-overhead**: Bytes per key of CRDT vector clock / tombstone data.
  Lower is better. Tracked per data type (COUNTER, OR-SET). Regressions mean
  the CRDT encoding grew.
- **conflict-rate**: Percentage of concurrent writes that required conflict
  resolution. Lower indicates better partitioning or smarter merge strategy.

## Running

```bash
./run.sh            # full suite
./run.sh converge   # single workload
```

Results are written to `results/` as JSON (gitignored).
