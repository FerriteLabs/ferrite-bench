# Contributing to Ferrite Benchmarks

Thank you for your interest in contributing! This repository contains external performance benchmarks comparing Ferrite against other key-value stores.

## Getting Started

- Familiarize yourself with the [main Ferrite contributing guide](https://github.com/ferritelabs/ferrite/blob/main/CONTRIBUTING.md) for general project standards
- Cargo-integrated benchmarks (`criterion`) live in the main [ferrite](https://github.com/ferritelabs/ferrite) repo under `benches/`
- This repo focuses on external, cross-system comparisons

## How to Contribute

### Reporting Issues

- Use [GitHub Issues](https://github.com/ferritelabs/ferrite-bench/issues) for benchmark bugs or requests

### Adding Benchmarks

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-benchmark`)
3. Add your benchmark under `comparison/`
4. Include a README explaining methodology and how to reproduce
5. Commit with a clear message and open a Pull Request

## Benchmark Guidelines

- **Reproducibility**: All benchmarks must include exact steps to reproduce
- **Fair comparison**: Use identical hardware, dataset size, and concurrency for all systems tested
- **Methodology**: Document warmup period, iteration count, and measurement approach
- **Environment**: Record OS, kernel version, CPU, RAM, and disk type
- **Tooling**: Prefer `memtier_benchmark`, `redis-benchmark`, or `criterion` for consistency

## Commit Message Format

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <description>

Types: feat, fix, docs, chore, refactor, bench
```

## Code of Conduct

Please be respectful, inclusive, and constructive in all interactions. See the [main project Code of Conduct](https://github.com/ferritelabs/ferrite/blob/main/CONTRIBUTING.md#code-of-conduct).

## License

By contributing, you agree that your contributions will be licensed under Apache-2.0.
