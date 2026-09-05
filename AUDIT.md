# Clean-Code and SRP Audit

## Summary

- The audit covered every current Python and shell file over 150 lines and every broad or mixed-responsibility filename; size was used only to select files, while findings were based on actors and reasons to change.
- No P0 issue was found; the highest-confidence P1 defects were missing deterministic coverage, unsafe/missing-data rendering, implicit CLI failures, and report/comparison modules serving unrelated actors.
- Completed work added 17 dependency-free Python unit tests plus Bash helper tests, repaired baseline correctness, and preserved benchmark protocols and output schemas.
- Report generation and Ferrite/Redis comparison now separate data/decision/rendering/CLI actors while retaining the existing CLI paths, options, executable modes, imports, and output keys.
- Docker/server orchestration and benchmark-engine adapters remain intentionally out of scope because safe unit verification would require protocol changes, external services, or lower-confidence restructuring.

## Method

An SRP issue exists when code changes for different actors: benchmark operators, result-format consumers, release-gate maintainers, CI maintainers, or documentation maintainers. Line count alone is not a finding. The audit used current post-refactor line counts and also reviewed broad names such as `harness`, `compare`, `report_generator`, `vector_comparison`, and `run_*`.

## Findings

| ID | location | category | P0-P2 | actors | cost | size | risk |
|----|----------|----------|-------|--------|------|------|------|
| FB-001 | `tests/`, `benchmarks/harness.sh`, `benchmarks/vector_comparison.sh`, shell lint fixes | Testability/correctness — completed | P1 | Benchmark maintainers; result consumers | Medium | M | Low |
| FB-002 | `comparison/compare.py`, `comparison/core.py`, `comparison/renderers.py` | SRP/missing metrics — completed | P1 | Comparison-policy maintainers; terminal/Markdown consumers; CLI users | Medium | M | Medium |
| FB-003 | `scripts/compare.py` | Error handling/release gate — completed | P1 | Moonshot metric owners; CI/release engineers | Small | S | Low |
| FB-004 | `benchmarks/report_generator.py`, `report_data.py`, `report_analysis.py`, `report_rendering.py`, `report_system.py` | SRP/baseline correctness — completed | P1 | Harness-data producers; analysis maintainers; report consumers; CLI users | Large | L | Medium |
| FB-005 | `.github/workflows/ci.yml` | CI ordering/coverage — completed | P1 | CI maintainers; contributors | Small | S | Low |
| FB-006 | `AUDIT.md` | Audit traceability — completed | P2 | Maintainers; reviewers | Small | S | Low |

## Ordered Sequence

1. **FB-001 — Regression seams first.** Added `tests/run.sh`, Python `unittest` coverage, Bash helper tests, safely sourceable harness/vector helpers, explicit memtier parse failures, and a green static-analysis baseline. Commit: `test(FB-001): establish deterministic regression seams`.
2. **FB-002 — Comparison correctness and SRP.** Moved comparison decisions and renderers out of the CLI, validated malformed rows, and rendered missing operation metrics as `N/A` without formatting `None`. Commit: `refactor(FB-002): separate comparison actors`.
3. **FB-003 — Moonshot comparison hardening.** Added deterministic metric tests and explicit file, JSON, direction, missing-metric, threshold, and ceiling behavior. Commit: `fix(FB-003): harden moonshot comparison errors`.
4. **FB-004 — Report-generation SRP.** Split ingestion, analysis, host inspection, rendering, and CLI compatibility; fixed custom-baseline calculations and retained report shape. Commit: `refactor(FB-004): separate report generation actors`.
5. **FB-005 — CI gate.** Made deterministic tests precede both lint jobs and retained ShellCheck and Ruff, including `scripts/`. Commit: `ci(FB-005): gate lint on deterministic tests`.
6. **FB-006 — Audit record.** Recorded scope, actor analysis, completed findings, sequence, and explicit exclusions. Commit: `docs(FB-006): document clean-code audit`.

## Files Over 150 Lines

| File | Lines | Actor assessment | Result |
|------|------:|------------------|--------|
| `benchmarks/vector_comparison.sh` | 805 | Benchmark operator, three engine adapters, and result presenter are distinct actors. | P1 orchestration remains out of scope; safe result parsing and source guards completed in FB-001. |
| `benchmarks/harness.sh` | 751 | Operator configuration, Docker lifecycle, benchmark execution, parsing, and reporting have distinct reasons to change. | P1 orchestration remains out of scope; deterministic parser/decision seams completed in FB-001. |
| `run_memtier_comparison.sh` | 361 | Compose orchestration, memtier execution, summary rendering, and threshold policy are mixed. | Deferred as integration-heavy orchestration; ShellCheck defects corrected in FB-001. |
| `benchmarks/ferrite_bench.sh` | 282 | Runner, JSON producer, Markdown producer, and regression policy are mixed. | Deferred to avoid changing established benchmark/result protocols without integration fixtures. |
| `benchmarks/redis_bench.sh` | 269 | Runner, JSON producer, and Markdown producer are mixed and duplicate Ferrite behavior. | Deferred with the paired Ferrite runner to avoid asymmetric protocol changes. |
| `benchmarks/report_rendering.py` | 246 | All functions serve the Markdown presentation actor despite the file length. | No SRP finding after FB-004. |
| `scripts/compare.py` | 235 | Loading, policy evaluation, and output support one moonshot release-gate workflow and actor. | Correctness/testability completed in FB-003; no forced length-only split. |
| `run_full_comparison.sh` | 204 | Server lifecycle and benchmark sequencing serve the benchmark operator. | No high-confidence unit-level extraction beyond existing helpers; deferred orchestration. |
| `comparison/renderers.py` | 196 | Terminal and Markdown outputs share the presentation actor and comparison view model. | No additional SRP finding after FB-002. |
| `benchmarks/report_data.py` | 178 | Data model and CSV ingestion serve the benchmark-data producer/consumer boundary. | No additional SRP finding after FB-004. |
| `tests/test_comparison.py` | 176 | All cases protect the Ferrite/Redis comparison contract for test maintainers. | No production SRP finding. |
| `benchmarks/report_generator.py` | 172 | Compatibility exports and CLI coordination serve the public report-generator interface. | Reduced to a facade in FB-004. |
| `comparison/run_comparison.sh` | 159 | Local runner, summary, and side-by-side display are operator-facing integration behavior. | Deferred because meaningful validation requires live benchmark endpoints. |

## Mixed-Responsibility Name Coverage

| Name/group | Review |
|------------|--------|
| `benchmarks/harness.sh` | Confirmed mixed actors; only sourceable parser/decision units were changed. |
| `benchmarks/vector_comparison.sh` | Confirmed mixed engine/orchestration/presentation actors; only safe, independently testable helpers were changed. |
| `benchmarks/report_generator.py` | Confirmed pre-refactor mixed actors; completed FB-004 facade extraction. |
| `comparison/compare.py` | Confirmed pre-refactor policy/rendering/CLI actors; completed FB-002 extraction. |
| `scripts/compare.py` | Reviewed as one release-gate workflow; hardened in FB-003 without a speculative split. |
| `run_memtier_comparison.sh`, `run_full_comparison.sh`, `comparison/run_comparison.sh`, `run-benchmarks.sh` | Reviewed as orchestration entrypoints; integration-heavy decomposition deferred. |
| `benchmarks/ferrite_bench.sh`, `benchmarks/redis_bench.sh` | Reviewed together because their runner and report responsibilities are duplicated; protocol-preserving consolidation deferred. |
| `moonshots/*/run.sh` | Reviewed as uniform per-moonshot orchestration stubs; each serves one moonshot benchmark actor and is below the size threshold. |

## Out of Scope

- Full decomposition of `benchmarks/harness.sh` and `benchmarks/vector_comparison.sh`; the remaining units coordinate Docker, network services, timing, and benchmark protocols and cannot be meaningfully unit-tested without external servers or protocol changes.
- Consolidation of `benchmarks/ferrite_bench.sh` and `benchmarks/redis_bench.sh`; doing so safely needs integration fixtures proving byte-for-byte JSON and Markdown compatibility.
- Refactoring `run_memtier_comparison.sh`, `run_full_comparison.sh`, and `comparison/run_comparison.sh` beyond static-cleanliness fixes; their decisions are tightly coupled to live process and service lifecycle behavior.
- Benchmark protocol, CSV/JSON output-schema, dependency-version, or server-startup changes, as explicitly excluded from this work.
