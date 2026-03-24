# Chronicle (M4) — Git-style Versioning Benchmarks

## What it measures

Chronicle adds git-style branching, merging, and point-in-time restore to
Ferrite. These benchmarks quantify the cost of versioning operations at scale.

### Workloads

| Benchmark | Description |
|-----------|-------------|
| `branch-create-time` | Latency to branch a 1M / 10M / 100M-key dataset |
| `merge-time` | Latency for 3-way merge with 10⁴ conflicting keys |
| `pitr-restore` | Time to materialise an `AS OF` snapshot |

## Interpreting results

- **branch-create-time**: Should be near-constant regardless of dataset size
  (copy-on-write). Tested at three tiers to verify O(1) scaling. Regressions
  at any tier trigger alerts.
- **merge-time**: Measures conflict resolution throughput. The headline metric
  is wall-clock time for 10K conflicting keys. Lower is better.
- **pitr-restore**: Time to reconstruct a point-in-time snapshot from the
  version DAG. Lower is better. This is the user-facing latency for
  `AS OF <timestamp>` queries.

## Running

```bash
./run.sh            # full suite
./run.sh branch     # single workload
```

Results are written to `results/` as JSON (gitignored).
