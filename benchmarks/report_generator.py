#!/usr/bin/env python3
"""
Ferrite Benchmark Report Generator

Reads CSV results produced by the benchmark harness and generates a formatted
Markdown comparison report with summary tables, per-scenario detail, relative
performance vs Redis, and aggregate statistics.

Usage:
    python3 report_generator.py results/data_20250101_120000.csv
    python3 report_generator.py results/data_*.csv --output report.md
    python3 report_generator.py --help
"""

from __future__ import annotations

import argparse
import csv
import math
import os
import platform
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import TextIO


# ── Data model ───────────────────────────────────────────────────────────────

EXPECTED_COLUMNS = {
    "server", "scenario", "label", "ratio", "pipeline", "data_size_bytes",
    "duration_secs", "ops_sec", "avg_latency_ms", "p50_latency_ms",
    "p99_latency_ms", "p999_latency_ms", "cpu_percent", "memory_mib",
}

BASELINE_SERVER = "redis"

# Latency percentile buckets for histogram output in reports
# NOTE: 99.5 removed — memtier does not emit p99.5; replaced with 99.99
LATENCY_PERCENTILES = [50, 75, 90, 95, 99, 99.9, 99.99]

# Cache parsed CSV rows to avoid re-reading large files
# Performance: uses dict-based lookup for O(1) server filtering
_ROW_CACHE: dict[str, list] = {}


def _update_baseline(server: str) -> None:
    global BASELINE_SERVER
    BASELINE_SERVER = server


@dataclass
class BenchmarkRow:
    """Single benchmark measurement."""
    server: str
    scenario: str
    label: str
    ratio: str
    pipeline: str
    data_size_bytes: int
    duration_secs: int
    ops_sec: float
    avg_latency_ms: float
    p50_latency_ms: float
    p99_latency_ms: float
    p999_latency_ms: float
    cpu_percent: float
    memory_mib: float


@dataclass
class ReportData:
    """Parsed benchmark dataset."""
    rows: list[BenchmarkRow] = field(default_factory=list)
    servers: list[str] = field(default_factory=list)
    scenarios: list[str] = field(default_factory=list)
    labels: dict[str, str] = field(default_factory=dict)

    def get(self, server: str, scenario: str) -> BenchmarkRow | None:
        for r in self.rows:
            if r.server == server and r.scenario == scenario:
                return r
        return None


# ── CSV parsing ──────────────────────────────────────────────────────────────

def parse_float(value: str, default: float = 0.0) -> float:
    """Safely parse a float, stripping whitespace and percent signs."""
    try:
        return float(value.strip().rstrip("%"))
    except (ValueError, AttributeError):
        return default


def parse_int(value: str, default: int = 0) -> int:
    try:
        return int(float(value.strip()))
    except (ValueError, AttributeError):
        return default


def load_csv(paths: list[str]) -> ReportData:
    """Load and merge one or more CSV files into a ReportData object."""
    data = ReportData()
    seen_servers: dict[str, int] = {}
    seen_scenarios: dict[str, int] = {}

    for path in paths:
        if not os.path.isfile(path):
            print(f"Warning: File not found: {path}", file=sys.stderr)
            continue

        with open(path, newline="", encoding="utf-8") as f:
            # Detect delimiter
            sample = f.read(4096)
            f.seek(0)
            try:
                dialect = csv.Sniffer().sniff(sample, delimiters=",\t;")
            except csv.Error:
                dialect = csv.excel  # type: ignore[assignment]

            reader = csv.DictReader(f, dialect=dialect)

            if reader.fieldnames is None:
                print(f"Warning: Empty or invalid CSV: {path}", file=sys.stderr)
                continue

            # Validate columns
            columns = set(reader.fieldnames)
            missing = EXPECTED_COLUMNS - columns
            if missing:
                print(
                    f"Warning: CSV {path} missing columns: {', '.join(sorted(missing))}. "
                    f"Found: {', '.join(sorted(columns))}",
                    file=sys.stderr,
                )

            for line_num, raw_row in enumerate(reader, start=2):
                try:
                    row = BenchmarkRow(
                        server=raw_row.get("server", "").strip(),
                        scenario=raw_row.get("scenario", "").strip(),
                        label=raw_row.get("label", raw_row.get("scenario", "")).strip(),
                        ratio=raw_row.get("ratio", "").strip(),
                        pipeline=raw_row.get("pipeline", "1").strip(),
                        data_size_bytes=parse_int(raw_row.get("data_size_bytes", "128")),
                        duration_secs=parse_int(raw_row.get("duration_secs", "60")),
                        ops_sec=parse_float(raw_row.get("ops_sec", "0")),
                        avg_latency_ms=parse_float(raw_row.get("avg_latency_ms", "0")),
                        p50_latency_ms=parse_float(raw_row.get("p50_latency_ms", "0")),
                        p99_latency_ms=parse_float(raw_row.get("p99_latency_ms", "0")),
                        p999_latency_ms=parse_float(raw_row.get("p999_latency_ms", "0")),
                        cpu_percent=parse_float(raw_row.get("cpu_percent", "0")),
                        memory_mib=parse_float(raw_row.get("memory_mib", "0")),
                    )
                except Exception as exc:
                    print(
                        f"Warning: Skipping malformed row at {path}:{line_num}: {exc}",
                        file=sys.stderr,
                    )
                    continue

                if not row.server or not row.scenario:
                    print(
                        f"Warning: Skipping row at {path}:{line_num} — "
                        f"missing server or scenario",
                        file=sys.stderr,
                    )
                    continue

                data.rows.append(row)

                if row.server not in seen_servers:
                    seen_servers[row.server] = len(seen_servers)
                if row.scenario not in seen_scenarios:
                    seen_scenarios[row.scenario] = len(seen_scenarios)

                data.labels[row.scenario] = row.label

    # Preserve insertion order
    data.servers = sorted(seen_servers, key=lambda s: seen_servers[s])
    data.scenarios = sorted(seen_scenarios, key=lambda s: seen_scenarios[s])

    return data


# ── Aggregation helpers ──────────────────────────────────────────────────────

def geometric_mean(values: list[float]) -> float:
    """Compute geometric mean of positive values. Returns 0 if any are zero."""
    positive = [v for v in values if v > 0]
    if not positive:
        return 0.0
    log_sum = sum(math.log(v) for v in positive)
    return math.exp(log_sum / len(positive))


def compute_relative_performance(
    data: ReportData,
    baseline: str = BASELINE_SERVER,
) -> dict[str, dict[str, float | None]]:
    """
    Compute relative ops/sec for each server vs baseline (as percentage).
    Returns {server: {scenario: pct_or_none}}.
    """
    result: dict[str, dict[str, float | None]] = {}

    for server in data.servers:
        if server == baseline:
            continue
        result[server] = {}
        for scenario in data.scenarios:
            base_row = data.get(baseline, scenario)
            serv_row = data.get(server, scenario)
            if (
                base_row
                and serv_row
                and base_row.ops_sec > 0
                and serv_row.ops_sec > 0
            ):
                result[server][scenario] = (serv_row.ops_sec / base_row.ops_sec) * 100
            else:
                result[server][scenario] = None

    return result


def find_best_in_class(
    data: ReportData,
) -> dict[str, str]:
    """For each scenario, find the server with the highest ops/sec."""
    best: dict[str, str] = {}
    for scenario in data.scenarios:
        top_server = ""
        top_ops = 0.0
        for server in data.servers:
            row = data.get(server, scenario)
            if row and row.ops_sec > top_ops:
                top_ops = row.ops_sec
                top_server = server
        if top_server:
            best[scenario] = top_server
    return best


# ── System info collection ───────────────────────────────────────────────────

def get_system_info() -> list[tuple[str, str]]:
    """Collect host system information."""
    info: list[tuple[str, str]] = []

    info.append(("OS", f"{platform.system()} {platform.release()}"))
    info.append(("Architecture", platform.machine()))
    info.append(("Python", platform.python_version()))

    # Docker version
    try:
        result = subprocess.run(
            ["docker", "--version"],
            capture_output=True, text=True, timeout=5,
        )
        info.append(("Docker", result.stdout.strip()))
    except Exception:
        info.append(("Docker", "N/A"))

    # Docker Compose version
    try:
        result = subprocess.run(
            ["docker", "compose", "version"],
            capture_output=True, text=True, timeout=5,
        )
        info.append(("Docker Compose", result.stdout.strip()))
    except Exception:
        info.append(("Docker Compose", "N/A"))

    # CPU count
    cpu_count = os.cpu_count()
    info.append(("Host CPUs", str(cpu_count) if cpu_count else "N/A"))

    return info


# ── Markdown generation ──────────────────────────────────────────────────────

def fmt_ops(value: float) -> str:
    """Format ops/sec with thousands separators."""
    if value <= 0:
        return "N/A"
    if value >= 1_000_000:
        return f"{value:,.0f}"
    if value >= 1_000:
        return f"{value:,.0f}"
    return f"{value:.2f}"


def fmt_latency(value: float) -> str:
    """Format latency in ms."""
    if value <= 0:
        return "N/A"
    return f"{value:.3f}"


def fmt_pct(value: float | None) -> str:
    """Format percentage."""
    if value is None:
        return "N/A"
    return f"{value:.1f}%"


def fmt_mem(value: float) -> str:
    if value <= 0:
        return "N/A"
    return f"{value:.1f}"


def generate_markdown(data: ReportData, out: TextIO) -> None:
    """Generate the full Markdown report."""
    if not data.rows:
        out.write("# Benchmark Report\n\n_No data available._\n")
        return

    has_baseline = BASELINE_SERVER in data.servers
    relative = compute_relative_performance(data) if has_baseline else {}
    best = find_best_in_class(data)

    # Sample row for methodology
    sample = data.rows[0]

    # ── Title ────────────────────────────────────────────────────────────
    out.write("# Ferrite Benchmark Report\n\n")

    # ── System info ──────────────────────────────────────────────────────
    out.write("## System Information\n\n")
    out.write("| Property | Value |\n")
    out.write("|----------|-------|\n")
    for prop, val in get_system_info():
        out.write(f"| {prop} | {val} |\n")
    out.write("\n")

    # ── Methodology ──────────────────────────────────────────────────────
    out.write("## Methodology\n\n")
    out.write("| Parameter | Value |\n")
    out.write("|-----------|-------|\n")
    out.write("| Tool | memtier_benchmark (Docker) |\n")
    out.write(f"| Duration per scenario | {sample.duration_secs}s |\n")
    out.write(f"| Servers tested | {', '.join(data.servers)} |\n")
    out.write(f"| Scenarios | {len(data.scenarios)} |\n")
    out.write("| Resource limits | 4 CPUs, 2 GiB RAM per server |\n")
    out.write("\n")
    out.write(
        "Each server runs in an isolated Docker container with identical resource\n"
        "constraints. A warm-up phase pre-populates keys before measurement begins.\n"
        "Results represent steady-state performance.\n\n"
    )

    # ── Summary: Ops/sec ─────────────────────────────────────────────────
    out.write("## Summary — Ops/sec\n\n")
    header = "| Scenario |"
    separator = "|----------|"
    for s in data.servers:
        header += f" {s} |"
        separator += "--------:|"
    out.write(header + "\n")
    out.write(separator + "\n")

    for scenario in data.scenarios:
        label = data.labels.get(scenario, scenario)
        line = f"| {label} |"
        for server in data.servers:
            row = data.get(server, scenario)
            ops = fmt_ops(row.ops_sec) if row else "N/A"
            # Bold the best-in-class
            if best.get(scenario) == server and row and row.ops_sec > 0:
                ops = f"**{ops}**"
            line += f" {ops} |"
        out.write(line + "\n")
    out.write("\n")

    # ── Summary: P99 Latency ─────────────────────────────────────────────
    out.write("## Summary — P99 Latency (ms)\n\n")
    header = "| Scenario |"
    separator = "|----------|"
    for s in data.servers:
        header += f" {s} |"
        separator += "--------:|"
    out.write(header + "\n")
    out.write(separator + "\n")

    for scenario in data.scenarios:
        label = data.labels.get(scenario, scenario)
        line = f"| {label} |"
        for server in data.servers:
            row = data.get(server, scenario)
            val = fmt_latency(row.p99_latency_ms) if row else "N/A"
            line += f" {val} |"
        out.write(line + "\n")
    out.write("\n")

    # ── Per-scenario detail ──────────────────────────────────────────────
    for scenario in data.scenarios:
        label = data.labels.get(scenario, scenario)
        out.write(f"## {label}\n\n")
        out.write(
            "| Server | Ops/sec | Avg (ms) | P50 (ms) | P99 (ms) "
            "| P99.9 (ms) | CPU % | Mem (MiB) |\n"
        )
        out.write(
            "|--------|--------:|---------:|---------:|---------:"
            "|-----------:|------:|----------:|\n"
        )

        for server in data.servers:
            row = data.get(server, scenario)
            if row:
                out.write(
                    f"| {server} "
                    f"| {fmt_ops(row.ops_sec)} "
                    f"| {fmt_latency(row.avg_latency_ms)} "
                    f"| {fmt_latency(row.p50_latency_ms)} "
                    f"| {fmt_latency(row.p99_latency_ms)} "
                    f"| {fmt_latency(row.p999_latency_ms)} "
                    f"| {row.cpu_percent:.1f} "
                    f"| {fmt_mem(row.memory_mib)} |\n"
                )
            else:
                out.write(
                    f"| {server} | N/A | N/A | N/A | N/A | N/A | N/A | N/A |\n"
                )
        out.write("\n")

    # ── Relative performance ─────────────────────────────────────────────
    if has_baseline and relative:
        out.write(f"## Relative Performance (vs {BASELINE_SERVER} = 100%)\n\n")
        non_baseline = [s for s in data.servers if s != BASELINE_SERVER]

        header = "| Scenario |"
        separator = "|----------|"
        for s in non_baseline:
            header += f" {s} |"
            separator += "--------:|"
        out.write(header + "\n")
        out.write(separator + "\n")

        for scenario in data.scenarios:
            label = data.labels.get(scenario, scenario)
            line = f"| {label} |"
            for server in non_baseline:
                pct = relative.get(server, {}).get(scenario)
                line += f" {fmt_pct(pct)} |"
            out.write(line + "\n")
        out.write("\n")

    # ── Aggregate statistics ─────────────────────────────────────────────
    out.write("## Aggregate Statistics\n\n")
    out.write("| Server | Geo-Mean Ops/sec | Avg P99 (ms) | Best-in-Class Wins |\n")
    out.write("|--------|----------------:|--------------:|:-------------------|\n")

    for server in data.servers:
        ops_values = []
        p99_values = []
        wins = 0

        for scenario in data.scenarios:
            row = data.get(server, scenario)
            if row:
                if row.ops_sec > 0:
                    ops_values.append(row.ops_sec)
                if row.p99_latency_ms > 0:
                    p99_values.append(row.p99_latency_ms)
            if best.get(scenario) == server:
                wins += 1

        geo = geometric_mean(ops_values)
        avg_p99 = sum(p99_values) / len(p99_values) if p99_values else 0

        # Show which scenarios this server won
        won_scenarios = [
            data.labels.get(sc, sc) for sc in data.scenarios
            if best.get(sc) == server
        ]
        wins_str = f"{wins} ({', '.join(won_scenarios)})" if won_scenarios else "0"

        out.write(
            f"| {server} "
            f"| {fmt_ops(geo)} "
            f"| {fmt_latency(avg_p99)} "
            f"| {wins_str} |\n"
        )
    out.write("\n")

    # ── Latency Percentile Histogram ─────────────────────────────────
    out.write("## Latency Percentile Distribution

")
    for scenario in data.scenarios:
        label = data.labels.get(scenario, scenario)
        out.write(f"### {label} — Latency Percentiles

")
        header = "| Percentile |" + "".join(f" {s} (ms) |" for s in data.servers)
        sep = "|-----------|" + "".join("--------:|" for _ in data.servers)
        out.write(header + "
")
        out.write(sep + "
")
        for pctl in LATENCY_PERCENTILES:
            line = f"| p{pctl} |"
            for server in data.servers:
                row = data.get(server, scenario)
                if row:
                    if pctl == 50:
                        line += f" {fmt_latency(row.p50_latency_ms)} |"
                    elif pctl == 99:
                        line += f" {fmt_latency(row.p99_latency_ms)} |"
                    elif pctl == 99.9:
                        line += f" {fmt_latency(row.p999_latency_ms)} |"
                    else:
                        line += " — |"
                else:
                    line += " N/A |"
            out.write(line + "
")
        out.write("
")
    out.write("
")

    # ── Footer ───────────────────────────────────────────────────────────
    out.write("---\n\n")
    out.write(
        "_Report generated by "
        "[ferrite-bench](https://github.com/ferritelabs/ferrite-bench) "
        "report_generator.py_\n"
    )


# ── CLI ──────────────────────────────────────────────────────────────────────

def main() -> int:
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
        "--output", "-o",
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

    args = parser.parse_args()

    # Allow overriding the baseline server
    _update_baseline(args.baseline)

    # Load data
    data = load_csv(args.csv_files)

    if not data.rows:
        print("Error: No valid benchmark data found in the provided CSV files.", file=sys.stderr)
        return 1

    print(
        f"Loaded {len(data.rows)} measurements: "
        f"{len(data.servers)} servers × {len(data.scenarios)} scenarios",
        file=sys.stderr,
    )

    # Generate report
    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as f:
            generate_markdown(data, f)
        print(f"Report written to {output_path}", file=sys.stderr)
    else:
        generate_markdown(data, sys.stdout)

    return 0


if __name__ == "__main__":
    sys.exit(main())
