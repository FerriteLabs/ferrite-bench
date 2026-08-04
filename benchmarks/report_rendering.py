"""Markdown rendering for benchmark reports."""

from __future__ import annotations

from typing import TextIO

try:
    from .report_analysis import (
        compute_relative_performance,
        find_best_in_class,
        geometric_mean,
    )
    from .report_data import ReportData
except ImportError:
    from report_analysis import (
        compute_relative_performance,
        find_best_in_class,
        geometric_mean,
    )
    from report_data import ReportData


LATENCY_PERCENTILES = [50, 75, 90, 95, 99, 99.9, 99.99]


def fmt_ops(value: float) -> str:
    """Format operations per second."""
    if value <= 0:
        return "N/A"
    if value >= 1_000:
        return f"{value:,.0f}"
    return f"{value:.2f}"


def fmt_latency(value: float) -> str:
    """Format latency in milliseconds."""
    if value <= 0:
        return "N/A"
    return f"{value:.3f}"


def fmt_pct(value: float | None) -> str:
    """Format a relative percentage."""
    if value is None:
        return "N/A"
    return f"{value:.1f}%"


def fmt_mem(value: float) -> str:
    """Format memory in MiB."""
    if value <= 0:
        return "N/A"
    return f"{value:.1f}"


def generate_markdown(
    data: ReportData,
    out: TextIO,
    *,
    baseline: str,
    system_info: list[tuple[str, str]],
) -> None:
    """Generate the full Markdown report."""
    if not data.rows:
        out.write("# Benchmark Report\n\n_No data available._\n")
        return

    has_baseline = baseline in data.servers
    relative = (
        compute_relative_performance(data, baseline) if has_baseline else {}
    )
    best = find_best_in_class(data)
    sample = data.rows[0]

    out.write("# Ferrite Benchmark Report\n\n")
    out.write("## System Information\n\n")
    out.write("| Property | Value |\n")
    out.write("|----------|-------|\n")
    for property_name, value in system_info:
        out.write(f"| {property_name} | {value} |\n")
    out.write("\n")

    out.write("## Methodology\n\n")
    out.write("| Parameter | Value |\n")
    out.write("|-----------|-------|\n")
    out.write("| Tool | memtier_benchmark (Docker) |\n")
    duration = f"{sample.duration_secs}s" if sample.duration_secs > 0 else "N/A"
    out.write(f"| Duration per scenario | {duration} |\n")
    out.write(f"| Servers tested | {', '.join(data.servers)} |\n")
    out.write(f"| Scenarios | {len(data.scenarios)} |\n")
    out.write("| Resource limits | 4 CPUs, 2 GiB RAM per server |\n\n")
    out.write(
        "Each server runs in an isolated Docker container with identical resource\n"
        "constraints. A warm-up phase pre-populates keys before measurement begins.\n"
        "Results represent steady-state performance.\n\n"
    )

    out.write("## Summary — Ops/sec\n\n")
    header = "| Scenario |"
    separator = "|----------|"
    for server in data.servers:
        header += f" {server} |"
        separator += "--------:|"
    out.write(header + "\n")
    out.write(separator + "\n")
    for scenario in data.scenarios:
        line = f"| {data.labels.get(scenario, scenario)} |"
        for server in data.servers:
            row = data.get(server, scenario)
            operations = fmt_ops(row.ops_sec) if row else "N/A"
            if best.get(scenario) == server and row and row.ops_sec > 0:
                operations = f"**{operations}**"
            line += f" {operations} |"
        out.write(line + "\n")
    out.write("\n")

    out.write("## Summary — P99 Latency (ms)\n\n")
    header = "| Scenario |"
    separator = "|----------|"
    for server in data.servers:
        header += f" {server} |"
        separator += "--------:|"
    out.write(header + "\n")
    out.write(separator + "\n")
    for scenario in data.scenarios:
        line = f"| {data.labels.get(scenario, scenario)} |"
        for server in data.servers:
            row = data.get(server, scenario)
            line += f" {fmt_latency(row.p99_latency_ms) if row else 'N/A'} |"
        out.write(line + "\n")
    out.write("\n")

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

    if relative:
        out.write(f"## Relative Performance (vs {baseline} = 100%)\n\n")
        non_baseline = [server for server in data.servers if server != baseline]
        header = "| Scenario |"
        separator = "|----------|"
        for server in non_baseline:
            header += f" {server} |"
            separator += "--------:|"
        out.write(header + "\n")
        out.write(separator + "\n")
        for scenario in data.scenarios:
            line = f"| {data.labels.get(scenario, scenario)} |"
            for server in non_baseline:
                line += f" {fmt_pct(relative.get(server, {}).get(scenario))} |"
            out.write(line + "\n")
        out.write("\n")

    out.write("## Aggregate Statistics\n\n")
    out.write("| Server | Geo-Mean Ops/sec | Avg P99 (ms) | Best-in-Class Wins |\n")
    out.write("|--------|----------------:|--------------:|:-------------------|\n")
    for server in data.servers:
        operations_values = []
        p99_values = []
        wins = 0
        for scenario in data.scenarios:
            row = data.get(server, scenario)
            if row:
                if row.ops_sec > 0:
                    operations_values.append(row.ops_sec)
                if row.p99_latency_ms > 0:
                    p99_values.append(row.p99_latency_ms)
            if best.get(scenario) == server:
                wins += 1

        average_p99 = sum(p99_values) / len(p99_values) if p99_values else 0
        won_scenarios = [
            data.labels.get(scenario, scenario)
            for scenario in data.scenarios
            if best.get(scenario) == server
        ]
        wins_description = (
            f"{wins} ({', '.join(won_scenarios)})" if won_scenarios else "0"
        )
        out.write(
            f"| {server} "
            f"| {fmt_ops(geometric_mean(operations_values))} "
            f"| {fmt_latency(average_p99)} "
            f"| {wins_description} |\n"
        )
    out.write("\n")

    out.write("## Latency Percentile Distribution\n\n")
    for scenario in data.scenarios:
        label = data.labels.get(scenario, scenario)
        out.write(f"### {label} — Latency Percentiles\n\n")
        header = "| Percentile |" + "".join(
            f" {server} (ms) |" for server in data.servers
        )
        separator = "|-----------|" + "".join(
            "--------:|" for _ in data.servers
        )
        out.write(header + "\n")
        out.write(separator + "\n")
        for percentile in LATENCY_PERCENTILES:
            line = f"| p{percentile} |"
            for server in data.servers:
                row = data.get(server, scenario)
                if not row:
                    line += " N/A |"
                elif percentile == 50:
                    line += f" {fmt_latency(row.p50_latency_ms)} |"
                elif percentile == 99:
                    line += f" {fmt_latency(row.p99_latency_ms)} |"
                elif percentile == 99.9:
                    line += f" {fmt_latency(row.p999_latency_ms)} |"
                else:
                    line += " — |"
            out.write(line + "\n")
        out.write("\n")
    out.write("\n---\n\n")
    out.write(
        "_Report generated by "
        "[ferrite-bench](https://github.com/ferritelabs/ferrite-bench) "
        "report_generator.py_\n"
    )
