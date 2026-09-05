"""Terminal and Markdown renderers for comparison data."""

from __future__ import annotations

from typing import Any


def format_pct(value: float | None) -> str:
    """Format a signed percentage."""
    if value is None:
        return "N/A"
    sign = "+" if value >= 0 else ""
    return f"{sign}{value:.1f}%"


def format_pct_md(value: float | None) -> str:
    """Format a percentage with the existing Markdown indicators."""
    if value is None:
        return "N/A"
    percentage = format_pct(value)
    if value > 5:
        return f"**{percentage}** 🟢"
    if value < -5:
        return f"**{percentage}** 🔴"
    return percentage


def format_metric(
    value: float | None,
    *,
    precision: int,
    grouped: bool = False,
) -> str:
    """Format a metric without applying numeric formatting to missing data."""
    if value is None:
        return "N/A"
    grouping = "," if grouped else ""
    return f"{value:{grouping}.{precision}f}"


def render_terminal(comp: dict[str, Any]) -> str:
    """Render comparison as a terminal-friendly table."""
    lines = [
        "",
        "═" * 95,
        "  Ferrite vs Redis — Benchmark Comparison",
        "═" * 95,
        "",
    ]

    config = comp["ferrite_config"]
    lines.append(
        f"  Ferrite: {config.get('host', '?')}:{config.get('port', '?')} | "
        f"Clients: {config.get('clients', '?')} | "
        f"Requests: {config.get('requests', '?')} | "
        f"Data: {config.get('data_size', '?')}B | "
        f"Pipeline: {config.get('pipeline', '?')}"
    )
    lines.extend(
        [
            "",
            "  Throughput (ops/sec) — higher is better",
            "  " + "─" * 52,
            f"  {'Operation':<10} {'Ferrite ops/s':>14} {'Redis ops/s':>14} {'Diff':>10}",
            "  " + "─" * 52,
        ]
    )

    for operation in comp["operations"]:
        lines.append(
            f"  {operation['operation']:<10} "
            f"{format_metric(operation['ferrite_ops_sec'], precision=2):>14} "
            f"{format_metric(operation['redis_ops_sec'], precision=2):>14} "
            f"{format_pct(operation['ops_sec_diff_pct']):>10}"
        )

    lines.extend(
        [
            "",
            "  Latency (ms) — lower is better",
            "  " + "─" * 80,
            (
                f"  {'Operation':<10} "
                f"{'Ferrite P50':>12} {'Redis P50':>12} "
                f"{'Ferrite P99':>12} {'Redis P99':>12} "
                f"{'P99 Diff':>10}"
            ),
            "  " + "─" * 80,
        ]
    )

    for operation in comp["operations"]:
        lines.append(
            f"  {operation['operation']:<10} "
            f"{format_metric(operation['ferrite_p50_ms'], precision=3):>12} "
            f"{format_metric(operation['redis_p50_ms'], precision=3):>12} "
            f"{format_metric(operation['ferrite_p99_ms'], precision=3):>12} "
            f"{format_metric(operation['redis_p99_ms'], precision=3):>12} "
            f"{format_pct(operation['p99_latency_diff_pct']):>10}"
        )
    lines.append("")
    return "\n".join(lines)


def render_markdown(comp: dict[str, Any]) -> str:
    """Render comparison as GitHub-flavored Markdown."""
    config = comp["ferrite_config"]
    lines = [
        "# Ferrite vs Redis — Benchmark Comparison",
        "",
        f"**Ferrite run:** {comp.get('ferrite_timestamp', 'N/A')}",
        f"**Redis run:** {comp.get('redis_timestamp', 'N/A')}",
        "",
        "## Configuration",
        "",
        "| Parameter | Value |",
        "|-----------|-------|",
        f"| Clients | {config.get('clients', 'N/A')} |",
        f"| Requests | {config.get('requests', 'N/A')} |",
        f"| Data size | {config.get('data_size', 'N/A')} bytes |",
        f"| Pipeline | {config.get('pipeline', 'N/A')} |",
        "",
        "## Throughput (ops/sec)",
        "",
        "Higher is better. Positive diff = Ferrite is faster.",
        "",
        "| Operation | Ferrite | Redis | Difference |",
        "|-----------|--------:|------:|-----------:|",
    ]

    for operation in comp["operations"]:
        lines.append(
            f"| {operation['operation']} "
            f"| {format_metric(operation['ferrite_ops_sec'], precision=2, grouped=True)} "
            f"| {format_metric(operation['redis_ops_sec'], precision=2, grouped=True)} "
            f"| {format_pct_md(operation['ops_sec_diff_pct'])} |"
        )

    lines.extend(
        [
            "",
            "## Latency (ms)",
            "",
            "Lower is better. Negative diff = Ferrite has lower latency.",
            "",
            (
                "| Operation | Ferrite P50 | Redis P50 | Ferrite P99 | Redis P99 "
                "| Ferrite P99.9 | Redis P99.9 |"
            ),
            (
                "|-----------|------------:|----------:|------------:|----------:"
                "|--------------:|------------:|"
            ),
        ]
    )

    for operation in comp["operations"]:
        lines.append(
            f"| {operation['operation']} "
            f"| {format_metric(operation['ferrite_p50_ms'], precision=3)} "
            f"| {format_metric(operation['redis_p50_ms'], precision=3)} "
            f"| {format_metric(operation['ferrite_p99_ms'], precision=3)} "
            f"| {format_metric(operation['redis_p99_ms'], precision=3)} "
            f"| {format_metric(operation['ferrite_p999_ms'], precision=3)} "
            f"| {format_metric(operation['redis_p999_ms'], precision=3)} |"
        )

    faster_count = sum(
        1
        for operation in comp["operations"]
        if operation["ops_sec_diff_pct"] is not None
        and operation["ops_sec_diff_pct"] > 0
    )
    differences = [
        operation["ops_sec_diff_pct"]
        for operation in comp["operations"]
        if operation["ops_sec_diff_pct"] is not None
    ]
    lines.extend(
        [
            "",
            "## Summary",
            "",
            (
                f"Ferrite is faster in **{faster_count}/{len(comp['operations'])}** "
                "operations by throughput."
            ),
            "",
        ]
    )
    if differences:
        lines.append(
            f"Average throughput difference: **{format_pct(sum(differences) / len(differences))}**"
        )
    lines.extend(["", "---", "*Generated by ferrite-bench compare.py*"])
    return "\n".join(lines)
