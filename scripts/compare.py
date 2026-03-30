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

import json
import sys
from pathlib import Path

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


def compute_change(baseline: float, candidate: float, direction: str) -> tuple[float, bool]:
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
    else:
        # Decrease is bad
        return (-raw_pct, raw_pct < 0)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <baseline.json> <candidate.json>", file=sys.stderr)
        return 2

    baseline_path = Path(sys.argv[1])
    candidate_path = Path(sys.argv[2])

    for p in (baseline_path, candidate_path):
        if not p.exists():
            print(f"ERROR: File not found: {p}", file=sys.stderr)
            return 2

    with open(baseline_path) as f:
        baseline = json.load(f)
    with open(candidate_path) as f:
        candidate = json.load(f)

    moonshot = baseline.get("moonshot", candidate.get("moonshot"))
    if not moonshot:
        print("ERROR: Cannot determine moonshot name from result files.", file=sys.stderr)
        return 2

    # Locate headline-metrics.toml relative to this script
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent
    metrics_file = repo_root / "moonshots" / moonshot / "headline-metrics.toml"

    if not metrics_file.exists():
        print(f"ERROR: Headline metrics not found: {metrics_file}", file=sys.stderr)
        return 2

    with open(metrics_file, "rb") as f:
        headlines = tomllib.load(f)

    # --- Compare ---
    failures = []
    rows = []

    for name, spec in headlines.items():
        metric_path = spec["metric_path"]
        direction = spec.get("direction", "lower_is_better")
        threshold = spec.get("threshold_percent", 5.0)
        unit = spec.get("unit", "")

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

        rows.append((name, f"{base_val:.4g}", f"{cand_val:.4g}", f"{pct_change:+.2f}%", status, unit))

        # Check hard ceiling if present (e.g., warm_call_p99 must be < 50 µs)
        hard_ceiling = spec.get("hard_ceiling_us")
        if hard_ceiling is not None and cand_val is not None and cand_val > hard_ceiling:
            failures.append(
                f"{name}: candidate {cand_val:.2f} µs exceeds hard ceiling {hard_ceiling} µs"
            )
            # Override status in last row
            rows[-1] = (name, f"{base_val:.4g}", f"{cand_val:.4g}", f"{pct_change:+.2f}%", "CEIL", unit)

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
