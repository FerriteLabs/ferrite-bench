# Forge (M2) — Embedded Functions Benchmarks

## What it measures

Forge enables embedded WASM/JS functions inside Ferrite. These benchmarks
quantify function invocation overhead and its impact on KV throughput.

### Workloads

| Benchmark | Description |
|-----------|-------------|
| `warm-call-p99` | Warm `FN.CALL` p99 latency (GA gate: < 50 µs) |
| `cold-load-time` | Time from `FN.LOAD` to first successful `FN.CALL` |
| `kv-throughput-overhead` | Cost of routing a `GET` through a no-op WASM function |

## Interpreting results

- **warm-call-p99**: The hard GA gate. Must be under 50 µs. Measures the
  overhead of the function dispatch path when the WASM module is already
  compiled and cached.
- **cold-load-time**: Measures module compilation + instantiation. Expected to
  be in the low milliseconds. Not a regression-alert metric but tracked for
  visibility.
- **kv-throughput-overhead**: Ratio of throughput with a no-op function vs
  native GET. Ideally < 5% overhead. Headline metric tracks the absolute
  throughput in ops/sec.

## Running

```bash
./run.sh            # full suite
./run.sh warm       # single workload
```

Results are written to `results/` as JSON (gitignored).
