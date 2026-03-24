# Lucidity (M3) — Verifiable Audit Benchmarks

## What it measures

Lucidity adds verifiable audit logging and zero-knowledge proofs to Ferrite.
These benchmarks quantify the throughput cost of audit and proof generation times.

### Workloads

| Benchmark | Description |
|-----------|-------------|
| `audit-overhead` | Write throughput delta with audit log enabled vs disabled |
| `proof-time` | Time to generate inclusion proof at log sizes 10⁵, 10⁶, 10⁷ |
| `zk-proof-time` | Time to generate selective-disclosure proof for a 1k-record window |

## Interpreting results

- **audit-overhead**: Measured as % throughput reduction. Lower is better.
  The headline metric is the delta at concurrency 64 — regressions above 5%
  absolute throughput loss trigger CI failure.
- **proof-time**: Time in milliseconds to generate a Merkle inclusion proof.
  Tested at three log sizes to verify sub-linear scaling. Regressions on any
  tier trigger alerts.
- **zk-proof-time**: Wall-clock time for a zero-knowledge selective-disclosure
  proof. Expected to be in the hundreds of milliseconds. Regressions above 5%
  trigger CI failure.

## Running

```bash
./run.sh            # full suite
./run.sh audit      # single workload
```

Results are written to `results/` as JSON (gitignored).
