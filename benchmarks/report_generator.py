#!/usr/bin/env python3
"""Generate Markdown benchmark reports from harness CSV files."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import TextIO

if __package__:
    from .report_analysis import (
        compute_relative_performance as _compute_relative_performance,
    )
    from .report_analysis import find_best_in_class, geometric_mean
    from .report_data import (
        EXPECTED_COLUMNS,
        BenchmarkRow,
        ReportData,
        load_csv,
        parse_float,
        parse_int,
    )
    from .report_rendering import (
        LATENCY_PERCENTILES,
        fmt_latency,
        fmt_mem,
        fmt_ops,
        fmt_pct,
    )
    from .report_rendering import generate_markdown as _generate_markdown
    from .report_system import get_system_info
else:
    from report_analysis import (
        compute_relative_performance as _compute_relative_performance,
    )
    from report_analysis import find_best_in_class, geometric_mean
    from report_data import (
        EXPECTED_COLUMNS,
        BenchmarkRow,
        ReportData,
        load_csv,
        parse_float,
        parse_int,
    )
    from report_rendering import (
        LATENCY_PERCENTILES,
        fmt_latency,
        fmt_mem,
        fmt_ops,
        fmt_pct,
    )
    from report_rendering import generate_markdown as _generate_markdown
    from report_system import get_system_info


BASELINE_SERVER = "redis"

__all__ = [
    "BASELINE_SERVER",
    "EXPECTED_COLUMNS",
    "LATENCY_PERCENTILES",
    "BenchmarkRow",
    "ReportData",
    "compute_relative_performance",
    "find_best_in_class",
    "fmt_latency",
    "fmt_mem",
    "fmt_ops",
    "fmt_pct",
    "generate_markdown",
    "geometric_mean",
    "get_system_info",
    "load_csv",
    "main",
    "parse_float",
    "parse_int",
]


def _update_baseline(server: str) -> None:
    global BASELINE_SERVER
    BASELINE_SERVER = server


def compute_relative_performance(
    data: ReportData,
    baseline: str | None = None,
) -> dict[str, dict[str, float | None]]:
    """Compatibility wrapper using the currently configured baseline by default."""
    return _compute_relative_performance(data, baseline or BASELINE_SERVER)


def generate_markdown(data: ReportData, out: TextIO) -> None:
    """Compatibility wrapper around the Markdown renderer."""
    _generate_markdown(
        data,
        out,
        baseline=BASELINE_SERVER,
        system_info=get_system_info(),
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate Markdown benchmark reports from CSV data.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
examples:
  %(prog)s results/data_20250101_120000.csv
  %(prog)s results/data_*.csv --output comparison.md
  %(prog)s results/data.csv | less
""",
    )
    parser.add_argument(
        "csv_files",
        nargs="+",
        metavar="CSV",
        help="One or more CSV files produced by the benchmark harness.",
    )
    parser.add_argument(
        "--output",
        "-o",
        metavar="FILE",
        default=None,
        help="Write report to FILE instead of stdout.",
    )
    parser.add_argument(
        "--baseline",
        metavar="SERVER",
        default=BASELINE_SERVER,
        help=f"Server to use as baseline for relative comparison (default: {BASELINE_SERVER}).",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    _update_baseline(args.baseline)
    data = load_csv(args.csv_files)

    if not data.rows:
        print(
            "Error: No valid benchmark data found in the provided CSV files.",
            file=sys.stderr,
        )
        return 1

    print(
        f"Loaded {len(data.rows)} measurements: "
        f"{len(data.servers)} servers x {len(data.scenarios)} scenarios",
        file=sys.stderr,
    )

    try:
        if args.output:
            output_path = Path(args.output)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            with open(output_path, "w", encoding="utf-8") as output:
                generate_markdown(data, output)
            print(f"Report written to {output_path}", file=sys.stderr)
        else:
            generate_markdown(data, sys.stdout)
    except OSError as exc:
        print(f"Error: Cannot write report: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
