# Changelog

All notable changes to ferrite-bench will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
