# Mnemo (M1) — Semantic Memory Benchmarks

## What it measures

Mnemo adds semantic memory (write / recall / forget) to Ferrite. These benchmarks
quantify the latency and throughput of memory operations over large corpora.

### Workloads

| Benchmark | Description |
|-----------|-------------|
| `recall-latency` | p50 / p99 latency of `MEMORY.RECALL` over a 1M-record corpus |
| `eval-longmemeval` | Accuracy on the LongMemEval public benchmark |
| `write-throughput` | ops/sec for `MEMORY.WRITE` at concurrencies 1, 8, 64 |

## Interpreting results

- **recall-latency**: Lower is better. p99 should stay within 5× of p50 for
  production readiness. Regressions above 5% on p50 or p99 trigger CI failure.
- **write-throughput**: Higher is better. Measured at multiple concurrency levels
  to detect lock contention. The headline metric is the ops/sec at concurrency 64.
- **eval-longmemeval**: Accuracy percentage — higher is better. This is an
  end-to-end quality gate, not a performance benchmark.

## Running

```bash
./run.sh            # full suite
./run.sh recall     # single workload
```

Results are written to `results/` as JSON (gitignored).
