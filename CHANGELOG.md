# Changelog

All notable changes to ferrite-bench will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-04-20

### Added

- Moonshot benchmark harness specification (`MOONSHOT_HARNESS.md`) defining the contract for M1–M6 benchmarks
- Benchmark workload configurations for all 6 moonshot crates (`moonshots/`): Chronicle, Concord, Forge, Lucidity, Mnemo, Pangea
- Each moonshot workload includes `workload.toml`, `headline-metrics.toml`, and a reproducible `run.sh` entrypoint
- Benchmark result comparison script (`scripts/compare.py`) for cross-release and cross-moonshot analysis

## [0.3.0] - 2026-03-09

### Added
- Tiered storage benchmark script for hot/warm/cold tier performance measurement
- Persistence impact benchmark script (AOF-always vs AOF-everysec vs no-persist)
- Hardware attestation script for benchmark reproducibility
- Zipfian and batch-ops scenarios in benchmark harness

## [0.2.0] - 2026-02-28

### Added
- Initial benchmark suite comparing Ferrite against Redis, Dragonfly, and KeyDB
- Throughput benchmarks using memtier_benchmark
- Latency percentile comparison scripts
- Vector search comparison benchmarks
- Docker Compose configuration for reproducible benchmark environments
- CI workflow for automated benchmark runs
- Nightly benchmark workflow for regression tracking
- GitHub issue and PR templates
- EditorConfig for consistent formatting

### Changed
- Updated CI workflow with gitleaks secret scanning
- Improved benchmark documentation in README

[Unreleased]: https://github.com/ferritelabs/ferrite-bench/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/ferritelabs/ferrite-bench/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ferritelabs/ferrite-bench/releases/tag/v0.2.0
