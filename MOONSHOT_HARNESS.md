# Moonshot Benchmark Harness

This document defines the contract every moonshot (M1–M6) must follow when adding
benchmarks to `ferrite-bench/`. The goals are reproducibility, comparability across
releases, and one-command execution for a contributor.

## Layout

```
ferrite-bench/
├── benchmarks/              # existing core benchmarks
├── moonshots/               # NEW — one subdir per moonshot
│   ├── mnemo/
│   │   ├── README.md        # what it measures, how to interpret
│   │   ├── workload.toml    # parameters: dataset, op mix, concurrency
│   │   ├── run.sh           # entrypoint — reproducible, no manual steps
│   │   └── results/         # gitignored — generated CSV/JSON
│   ├── forge/
│   ├── lucidity/
│   ├── chronicle/
│   ├── concord/
│   └── pangea/
└── results/
    └── <moonshot>-<version>.md   # published results per release
```

## Per-moonshot required benchmarks

Every moonshot **must** ship at least these workloads before its GA gate:

### Mnemo (M1)

- `recall-latency`: p50 / p99 latency of `MEMORY.RECALL` over a 1M-record corpus.
- `eval-longmemeval`: accuracy on the LongMemEval public benchmark.
- `write-throughput`: ops/sec for `MEMORY.WRITE` at concurrencies 1, 8, 64.

### Forge (M2)

- `warm-call-p99`: warm `FN.CALL` p99 latency (must be < 50 µs at GA).
- `cold-load-time`: time from `FN.LOAD` to first successful `FN.CALL`.
- `kv-throughput-overhead`: cost of routing a `GET` through a no-op WASM function.

### Lucidity (M3)

- `audit-overhead`: write throughput delta with audit log on vs off.
- `proof-time`: time to generate inclusion proof at log sizes 10⁵, 10⁶, 10⁷.
- `zk-proof-time`: time to generate selective-disclosure proof for a 1k-record window.

### Chronicle (M4)

- `branch-create-time`: latency to branch a 1M / 10M / 100M-key dataset.
- `merge-time`: latency for 3-way merge with 10⁴ conflicting keys.
- `pitr-restore`: time to materialise an `AS OF` snapshot.

### Concord (M5)

- `convergence-time`: time for 2-region updates to converge after partition heal.
- `metadata-overhead`: bytes of CRDT metadata per key for COUNTER / OR-SET.
- `conflict-rate`: % of conflicting writes auto-resolved at given write skew.

### Pangea (M6)

- `tier-promotion-cost`: latency penalty when reading a key migrated CXL → DRAM.
- `working-set-perf`: throughput at 0.5×, 1×, 2× DRAM-only working-set sizes.
- `numa-locality`: cross-socket vs same-socket access latency on CXL.

## Reproducibility contract

Every `run.sh` MUST:

1. Start from a clean state (`docker compose down -v`).
2. Print exact versions: `ferrite --version`, kernel, CPU model, libc.
3. Pin random seeds (`FERRITE_BENCH_SEED=42` by default).
4. Write results to `results/<bench>-<utc-iso>.json`.
5. Exit non-zero if any required signal is missing from output.

## Result format

Each result file is a JSON document:

```json
{
  "moonshot": "mnemo",
  "benchmark": "recall-latency",
  "version": "0.42.0",
  "started_at": "2026-04-17T10:00:00Z",
  "duration_s": 600,
  "host": {
    "kernel": "Linux 6.8",
    "cpu": "AMD EPYC 9554P",
    "ram_gib": 256
  },
  "params": { "dataset_size": 1000000, "concurrency": 64 },
  "metrics": {
    "p50_us": 145.2,
    "p99_us": 612.8,
    "throughput_ops": 87432
  }
}
```

## Comparison & regression detection

`scripts/compare.py` (to be added) compares two result JSONs and fails CI if any
metric regresses by > 5% on the headline-metric set. Each moonshot declares its
headline metrics in `moonshots/<name>/headline-metrics.toml`.

## Adding a new moonshot benchmark — checklist

- [ ] `moonshots/<name>/README.md` describing intent and interpretation.
- [ ] `workload.toml` with all parameters, no hardcoded values in `run.sh`.
- [ ] `run.sh` reproducible from a clean checkout.
- [ ] `headline-metrics.toml` with regression thresholds.
- [ ] At least one published baseline in `../results/`.
- [ ] Linked from this document.

## CI integration

Moonshot benchmarks run nightly (not per-PR — they are too expensive). Per-PR runs are
opt-in via `/bench <moonshot>` label-trigger (to be added to CI workflow).
