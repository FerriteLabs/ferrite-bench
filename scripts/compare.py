#!/usr/bin/env python3
"""
Compare two Ferrite moonshot benchmark result JSON files.

Loads headline-metrics.toml for the moonshot to determine which metrics
to compare and their regression thresholds. Exits non-zero if any
headline metric regresses beyond the configured threshold.

Usage:
    python compare.py <baseline.json> <candidate.json>

Example:
    python scripts/compare.py \
        moonshots/mnemo/results/mnemo-20260417T100000Z.json \
        moonshots/mnemo/results/mnemo-20260418T100000Z.json
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:
    try:
        import tomli as tomllib  # pip install tomli for Python <3.11
    except ModuleNotFoundError:
        print(
            "ERROR: Python 3.11+ required (tomllib), or install 'tomli' package.",
            file=sys.stderr,
        )
        sys.exit(2)


def resolve_metric(data: dict, path: str) -> float | None:
    """Walk a dotted path like 'metrics.p50_us' into a nested dict."""
    current = data
    for key in path.split("."):
        if isinstance(current, dict) and key in current:
            current = current[key]
        else:
            return None
    try:
        return float(current)
    except (TypeError, ValueError):
        return None


class ComparisonError(ValueError):
    """Raised when result data or metric configuration is invalid."""


def numeric_setting(
    spec: dict[str, Any],
    name: str,
    metric_name: str,
    default: float | None = None,
) -> float | None:
    """Return a finite numeric metric setting or raise an explicit config error."""
    value = spec.get(name, default)
    if value is None:
        return None
    if isinstance(value, bool):
        raise ComparisonError(
            f"Invalid {name} for headline metric {metric_name}: {value!r}"
        )
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise ComparisonError(
            f"Invalid {name} for headline metric {metric_name}: {value!r}"
        ) from exc
    if not math.isfinite(number):
        raise ComparisonError(
            f"Invalid {name} for headline metric {metric_name}: {value!r}"
        )
    return number


def compute_change(
    baseline: float,
    candidate: float,
    direction: str,
) -> tuple[float, bool]:
    """
    Return (percent_change, is_regression).

    percent_change is positive when the metric moved in the worse direction.
    """
    if baseline == 0:
        return (0.0, False)

    raw_pct = ((candidate - baseline) / abs(baseline)) * 100.0

    if direction == "lower_is_better":
        # Increase is bad
        return (raw_pct, raw_pct > 0)
    if direction == "higher_is_better":
        # Decrease is bad
        return (-raw_pct, raw_pct < 0)
    raise ComparisonError(f"Unsupported metric direction: {direction}")


def load_json(path: Path) -> dict[str, Any]:
    try:
        with open(path, encoding="utf-8") as file:
            data = json.load(file)
    except FileNotFoundError as exc:
        raise ComparisonError(f"File not found: {path}") from exc
    except OSError as exc:
        raise ComparisonError(f"Cannot read {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ComparisonError(f"Invalid JSON in {path}: {exc}") from exc

    if not isinstance(data, dict):
        raise ComparisonError(f"Result root must be an object: {path}")
    return data


def load_headlines(path: Path) -> dict[str, dict[str, Any]]:
    try:
        with open(path, "rb") as file:
            data = tomllib.load(file)
    except FileNotFoundError as exc:
        raise ComparisonError(f"Headline metrics not found: {path}") from exc
    except OSError as exc:
        raise ComparisonError(f"Cannot read headline metrics {path}: {exc}") from exc
    except tomllib.TOMLDecodeError as exc:
        raise ComparisonError(f"Invalid headline metrics TOML in {path}: {exc}") from exc

    if not isinstance(data, dict):
        raise ComparisonError(f"Headline metrics root must be a table: {path}")
    return data


def compare_headlines(
    baseline: dict[str, Any],
    candidate: dict[str, Any],
    headlines: dict[str, dict[str, Any]],
) -> tuple[list[tuple[str, str, str, str, str, str]], list[str]]:
    """Compare configured headline metrics and return display rows and failures."""
    failures = []
    rows = []

    for name, spec in headlines.items():
        if not isinstance(spec, dict) or "metric_path" not in spec:
            raise ComparisonError(f"Invalid headline metric specification: {name}")
        metric_path = str(spec["metric_path"])
        direction = spec.get("direction", "lower_is_better")
        threshold = numeric_setting(spec, "threshold_percent", name, 5.0)
        assert threshold is not None
        if threshold < 0:
            raise ComparisonError(
                f"Invalid threshold_percent for headline metric {name}: "
                "must not be negative"
            )
        unit = str(spec.get("unit", ""))

        base_val = resolve_metric(baseline, metric_path)
        cand_val = resolve_metric(candidate, metric_path)

        if base_val is None or cand_val is None:
            rows.append((name, "MISSING", "-", "-", "-", unit))
            failures.append(f"{name}: metric not found in one or both result files")
            continue

        pct_change, is_regression = compute_change(base_val, cand_val, direction)
        status = "OK"

        if is_regression and abs(pct_change) > threshold:
            status = "FAIL"
            failures.append(
                f"{name}: regressed {pct_change:+.2f}% (threshold: {threshold}%)"
            )

        rows.append(
            (
                name,
                f"{base_val:.4g}",
                f"{cand_val:.4g}",
                f"{pct_change:+.2f}%",
                status,
                unit,
            )
        )

        hard_ceiling = numeric_setting(spec, "hard_ceiling_us", name)
        if hard_ceiling is not None and cand_val > hard_ceiling:
            failures.append(
                f"{name}: candidate {cand_val:.2f} µs exceeds hard ceiling {hard_ceiling} µs"
            )
            rows[-1] = (
                name,
                f"{base_val:.4g}",
                f"{cand_val:.4g}",
                f"{pct_change:+.2f}%",
                "CEIL",
                unit,
            )

    return rows, failures


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 2:
        print(f"Usage: {sys.argv[0]} <baseline.json> <candidate.json>", file=sys.stderr)
        return 2

    baseline_path = Path(args[0])
    candidate_path = Path(args[1])

    try:
        baseline = load_json(baseline_path)
        candidate = load_json(candidate_path)

        baseline_moonshot = baseline.get("moonshot")
        candidate_moonshot = candidate.get("moonshot")
        if baseline_moonshot and candidate_moonshot and baseline_moonshot != candidate_moonshot:
            raise ComparisonError(
                "Result files describe different moonshots: "
                f"{baseline_moonshot} and {candidate_moonshot}"
            )
        moonshot = baseline_moonshot or candidate_moonshot
        if not isinstance(moonshot, str) or not moonshot:
            raise ComparisonError("Cannot determine moonshot name from result files.")

        repo_root = Path(__file__).resolve().parent.parent
        metrics_file = repo_root / "moonshots" / moonshot / "headline-metrics.toml"
        headlines = load_headlines(metrics_file)
        rows, failures = compare_headlines(baseline, candidate, headlines)
    except ComparisonError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    # --- Print table ---
    print(f"\n{'='*72}")
    print(f"  Moonshot: {moonshot}")
    print(f"  Baseline:  {baseline_path.name}")
    print(f"  Candidate: {candidate_path.name}")
    print(f"{'='*72}\n")

    header = f"  {'Metric':<30} {'Base':>10} {'Cand':>10} {'Change':>10} {'Status':>6} {'Unit':>10}"
    print(header)
    print(f"  {'-'*len(header.strip())}")

    for name, base_s, cand_s, change_s, status, unit in rows:
        indicator = "✓" if status == "OK" else "✗"
        print(f"  {name:<30} {base_s:>10} {cand_s:>10} {change_s:>10} {indicator:>4} {status:>2} {unit:>8}")

    print()

    if failures:
        print("REGRESSIONS DETECTED:")
        for f in failures:
            print(f"  ✗ {f}")
        print()
        return 1

    print("All headline metrics within threshold. ✓\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
