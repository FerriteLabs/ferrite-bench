"""Benchmark report data model and CSV loading."""

from __future__ import annotations

import csv
import os
import sys
from dataclasses import dataclass, field

EXPECTED_COLUMNS = {
    "server",
    "scenario",
    "label",
    "ratio",
    "pipeline",
    "data_size_bytes",
    "duration_secs",
    "ops_sec",
    "avg_latency_ms",
    "p50_latency_ms",
    "p99_latency_ms",
    "p999_latency_ms",
    "cpu_percent",
    "memory_mib",
}


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
        for row in self.rows:
            if row.server == server and row.scenario == scenario:
                return row
        return None


def parse_float(value: str | None, default: float = 0.0) -> float:
    """Parse a float after trimming whitespace and a trailing percent sign."""
    if value is None:
        return default
    try:
        return float(value.strip().rstrip("%"))
    except (AttributeError, ValueError):
        return default


def parse_int(value: str | None, default: int = 0) -> int:
    """Parse integer-like CSV values, including values written as floats."""
    if value is None:
        return default
    try:
        return int(float(value.strip()))
    except (AttributeError, ValueError):
        return default


def _text(row: dict[str, str | None], name: str, default: str = "") -> str:
    value = row.get(name)
    return default if value is None else value.strip()


def _dialect(file, path: str):
    sample = file.read(4096)
    file.seek(0)
    try:
        return csv.Sniffer().sniff(sample, delimiters=",\t;")
    except csv.Error:
        if sample:
            print(
                f"Warning: Could not detect delimiter for {path}; assuming comma.",
                file=sys.stderr,
            )
        return csv.excel


def _open_csv(path: str):
    return open(path, newline="", encoding="utf-8")


def load_csv(paths: list[str]) -> ReportData:
    """Load and merge one or more benchmark CSV files."""
    data = ReportData()
    seen_servers: dict[str, int] = {}
    seen_scenarios: dict[str, int] = {}

    for path in paths:
        if not os.path.isfile(path):
            print(f"Warning: File not found: {path}", file=sys.stderr)
            continue

        try:
            file = _open_csv(path)
        except OSError as exc:
            print(f"Warning: Cannot read CSV {path}: {exc}", file=sys.stderr)
            continue

        with file:
            reader = csv.DictReader(file, dialect=_dialect(file, path))
            if reader.fieldnames is None:
                print(f"Warning: Empty or invalid CSV: {path}", file=sys.stderr)
                continue

            columns = set(reader.fieldnames)
            missing = EXPECTED_COLUMNS - columns
            if missing:
                print(
                    f"Warning: CSV {path} missing columns: {', '.join(sorted(missing))}. "
                    f"Found: {', '.join(sorted(columns))}",
                    file=sys.stderr,
                )

            for line_number, raw_row in enumerate(reader, start=2):
                server = _text(raw_row, "server")
                scenario = _text(raw_row, "scenario")
                if not server or not scenario:
                    print(
                        f"Warning: Skipping row at {path}:{line_number} — "
                        "missing server or scenario",
                        file=sys.stderr,
                    )
                    continue

                row = BenchmarkRow(
                    server=server,
                    scenario=scenario,
                    label=_text(raw_row, "label", scenario),
                    ratio=_text(raw_row, "ratio"),
                    pipeline=_text(raw_row, "pipeline", "1"),
                    data_size_bytes=parse_int(
                        raw_row.get("data_size_bytes") or "128"
                    ),
                    duration_secs=parse_int(raw_row.get("duration_secs") or "60"),
                    ops_sec=parse_float(raw_row.get("ops_sec")),
                    avg_latency_ms=parse_float(raw_row.get("avg_latency_ms")),
                    p50_latency_ms=parse_float(raw_row.get("p50_latency_ms")),
                    p99_latency_ms=parse_float(raw_row.get("p99_latency_ms")),
                    p999_latency_ms=parse_float(raw_row.get("p999_latency_ms")),
                    cpu_percent=parse_float(raw_row.get("cpu_percent")),
                    memory_mib=parse_float(raw_row.get("memory_mib")),
                )
                data.rows.append(row)

                if server not in seen_servers:
                    seen_servers[server] = len(seen_servers)
                if scenario not in seen_scenarios:
                    seen_scenarios[scenario] = len(seen_scenarios)
                data.labels[scenario] = row.label

    data.servers = sorted(seen_servers, key=seen_servers.get)
    data.scenarios = sorted(seen_scenarios, key=seen_scenarios.get)
    return data
