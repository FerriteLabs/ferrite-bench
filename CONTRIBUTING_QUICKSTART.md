# Contributing Quickstart — ferrite-bench

Get up and running in 5 minutes.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) 24+ and Docker Compose v2+
- [Python](https://www.python.org/) 3.10+ (for report generation)
- [memtier_benchmark](https://github.com/RedisLabs/memtier_benchmark) (optional, for local runs)
- Bash 4+

## Fork & Clone

```bash
gh repo fork ferritelabs/ferrite-bench --clone
cd ferrite-bench
```

## Run Benchmarks

```bash
# Quick comparison (Docker-based, no local installs needed)
./run-benchmarks.sh

# Full competitive comparison (Ferrite vs Redis vs Dragonfly vs KeyDB)
./run_full_comparison.sh

# Memtier-only comparison
./run_memtier_comparison.sh
```

## Individual Benchmarks

```bash
cd benchmarks/

# Single server benchmarks
./ferrite_bench.sh
./redis_bench.sh

# Specialized
./persistence_bench.sh
./tiered_storage_bench.sh
./vector_comparison.sh

# Generate report from results
python3 report_generator.py results/
```

## What to Work On

- Look for [good first issues](https://github.com/ferritelabs/ferrite-bench/labels/good%20first%20issue)
- Add new benchmark scenarios in `benchmarks/`
- Improve the comparison analysis in `comparison/`
- Enhance report generation (`report_generator.py`)

## Methodology

Read [METHODOLOGY.md](METHODOLOGY.md) before changing benchmark configurations to ensure results remain reproducible and fair.

## Submitting Changes

1. Create a feature branch: `git checkout -b my-change`
2. Make your changes
3. Test locally with `./run-benchmarks.sh`
4. Commit using [Conventional Commits](https://www.conventionalcommits.org/)
5. Push and open a PR

See [CONTRIBUTING.md](CONTRIBUTING.md) for full guidelines.

---

**Part of [FerriteLabs](https://github.com/ferritelabs)** — see the [core engine](https://github.com/ferritelabs/ferrite) for the full project.
