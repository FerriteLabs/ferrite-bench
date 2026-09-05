"""Pure analysis decisions for benchmark reports."""

from __future__ import annotations

import math

try:
    from .report_data import ReportData
except ImportError:
    from report_data import ReportData


def geometric_mean(values: list[float]) -> float:
    """Compute the geometric mean of positive values."""
    positive = [value for value in values if value > 0]
    if not positive:
        return 0.0
    return math.exp(sum(math.log(value) for value in positive) / len(positive))


def compute_relative_performance(
    data: ReportData,
    baseline: str,
) -> dict[str, dict[str, float | None]]:
    """Compute per-scenario operations per second as a percentage of baseline."""
    result: dict[str, dict[str, float | None]] = {}

    for server in data.servers:
        if server == baseline:
            continue
        result[server] = {}
        for scenario in data.scenarios:
            baseline_row = data.get(baseline, scenario)
            server_row = data.get(server, scenario)
            if (
                baseline_row
                and server_row
                and baseline_row.ops_sec > 0
                and server_row.ops_sec > 0
            ):
                result[server][scenario] = (
                    server_row.ops_sec / baseline_row.ops_sec
                ) * 100
            else:
                result[server][scenario] = None

    return result


def find_best_in_class(data: ReportData) -> dict[str, str]:
    """Find the server with the highest positive throughput for each scenario."""
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
