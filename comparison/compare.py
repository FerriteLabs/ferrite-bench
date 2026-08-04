#!/usr/bin/env python3
"""
Ferrite vs Redis Benchmark Comparison Tool

Reads JSON benchmark results from ferrite_bench.sh and redis_bench.sh,
generates a side-by-side comparison with percentage differences.

Usage:
    python3 compare.py <ferrite_results.json> <redis_results.json>
    python3 compare.py results/ferrite_latest.json results/redis_latest.json
    python3 compare.py results/ferrite_latest.json results/redis_latest.json -o results/comparison.md
"""

import argparse
import json
import sys
from pathlib import Path


def load_results(path: str) -> dict:
    """Load benchmark results from a JSON file."""
    try:
        with open(path) as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Error: benchmark results file not found: {path}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: invalid JSON in {path}: {e}", file=sys.stderr)
        sys.exit(1)
    if "results" not in data:
        print(f"Warning: no 'results' key in {path}", file=sys.stderr)
    return data


SORTED_SET_OPS = {"zadd", "zrange", "zrangebyscore", "zrem", "zcard"}


def build_ops_map(data: dict) -> dict[str, dict]:
    """Build a map of operation name -> metrics from benchmark results."""
    return {r["operation"]: r for r in data.get("results", [])}


def is_sorted_set_op(operation: str) -> bool:
    """Check if an operation is a sorted set command."""
    return operation.lower() in SORTED_SET_OPS


def pct_diff(a: float | None, b: float | None) -> float | None:
    """Compute percentage difference: ((a - b) / b) * 100."""
    if a is None or b is None or b == 0:
        return None
    return ((a - b) / b) * 100


def format_pct(value: float | None) -> str:
    """Format percentage with color indicator for terminal output."""
    if value is None:
        return "N/A"
    sign = "+" if value >= 0 else ""
    return f"{sign}{value:.1f}%"


def format_pct_md(value: float | None) -> str:
    """Format percentage for GitHub markdown."""
    if value is None:
        return "N/A"
    sign = "+" if value >= 0 else ""
    pct = f"{sign}{value:.1f}%"
    if value > 5:
        return f"**{pct}** 🟢"
    elif value < -5:
        return f"**{pct}** 🔴"
    return pct


def generate_comparison(ferrite: dict, redis: dict) -> dict:
    """Generate comparison data between Ferrite and Redis results."""
    f_ops = build_ops_map(ferrite)
    r_ops = build_ops_map(redis)

    all_ops = sorted(set(list(f_ops.keys()) + list(r_ops.keys())))
    comparison = []

    for op in all_ops:
        f = f_ops.get(op, {})
        r = r_ops.get(op, {})

        # Use None for missing data instead of 0 to distinguish "not tested" from "zero"
        f_missing = op not in f_ops
        r_missing = op not in r_ops

        entry = {
            "operation": op,
            "ferrite_ops_sec": None if f_missing else f.get("ops_per_sec", 0),
            "redis_ops_sec": None if r_missing else r.get("ops_per_sec", 0),
            "ferrite_avg_ms": None if f_missing else f.get("avg_latency_ms", 0),
            "redis_avg_ms": None if r_missing else r.get("avg_latency_ms", 0),
            "ferrite_p50_ms": None if f_missing else f.get("p50_latency_ms", 0),
            "redis_p50_ms": None if r_missing else r.get("p50_latency_ms", 0),
            "ferrite_p99_ms": None if f_missing else f.get("p99_latency_ms", 0),
            "redis_p99_ms": None if r_missing else r.get("p99_latency_ms", 0),
            "ferrite_p999_ms": None if f_missing else f.get("p999_latency_ms", 0),
            "redis_p999_ms": None if r_missing else r.get("p999_latency_ms", 0),
        }

        # Throughput: higher is better
        entry["ops_sec_diff_pct"] = pct_diff(
            entry["ferrite_ops_sec"], entry["redis_ops_sec"]
        )
        # Latency: lower is better, so we invert (negative diff = Ferrite is faster)
        entry["avg_latency_diff_pct"] = pct_diff(
            entry["ferrite_avg_ms"], entry["redis_avg_ms"]
        )
        entry["p99_latency_diff_pct"] = pct_diff(
            entry["ferrite_p99_ms"], entry["redis_p99_ms"]
        )

        comparison.append(entry)

    return {
        "ferrite_config": ferrite.get("config", {}),
        "redis_config": redis.get("config", {}),
        "ferrite_timestamp": ferrite.get("timestamp", ""),
        "redis_timestamp": redis.get("timestamp", ""),
        "operations": comparison,
    }


def render_terminal(comp: dict) -> str:
    """Render comparison as a terminal-friendly table."""
    lines = []
    lines.append("")
    lines.append("═" * 95)
    lines.append("  Ferrite vs Redis — Benchmark Comparison")
    lines.append("═" * 95)
    lines.append("")

    # Config summary
    fc = comp["ferrite_config"]
    lines.append(f"  Ferrite: {fc.get('host', '?')}:{fc.get('port', '?')} | "
                 f"Clients: {fc.get('clients', '?')} | "
                 f"Requests: {fc.get('requests', '?')} | "
                 f"Data: {fc.get('data_size', '?')}B | "
                 f"Pipeline: {fc.get('pipeline', '?')}")
    lines.append("")

    # Throughput table
    header = f"  {'Operation':<10} {'Ferrite ops/s':>14} {'Redis ops/s':>14} {'Diff':>10}"
    lines.append("  Throughput (ops/sec) — higher is better")
    lines.append("  " + "─" * 52)
    lines.append(header)
    lines.append("  " + "─" * 52)

    for op in comp["operations"]:
        diff = format_pct(op["ops_sec_diff_pct"])
        lines.append(
            f"  {op['operation']:<10} "
            f"{op['ferrite_ops_sec']:>14.2f} "
            f"{op['redis_ops_sec']:>14.2f} "
            f"{diff:>10}"
        )
    lines.append("")

    # Latency table
    lines.append("  Latency (ms) — lower is better")
    lines.append("  " + "─" * 80)
    header2 = (
        f"  {'Operation':<10} "
        f"{'Ferrite P50':>12} {'Redis P50':>12} "
        f"{'Ferrite P99':>12} {'Redis P99':>12} "
        f"{'P99 Diff':>10}"
    )
    lines.append(header2)
    lines.append("  " + "─" * 80)

    for op in comp["operations"]:
        diff = format_pct(op["p99_latency_diff_pct"])
        # For latency, negative diff means Ferrite is faster (lower latency)
        lines.append(
            f"  {op['operation']:<10} "
            f"{op['ferrite_p50_ms']:>12.3f} {op['redis_p50_ms']:>12.3f} "
            f"{op['ferrite_p99_ms']:>12.3f} {op['redis_p99_ms']:>12.3f} "
            f"{diff:>10}"
        )
    lines.append("")

    return "\n".join(lines)


def render_markdown(comp: dict) -> str:
    """Render comparison as GitHub-flavored markdown."""
    lines = []
    lines.append("# Ferrite vs Redis — Benchmark Comparison")
    lines.append("")

    fc = comp["ferrite_config"]
    lines.append(f"**Ferrite run:** {comp.get('ferrite_timestamp', 'N/A')}")
    lines.append(f"**Redis run:** {comp.get('redis_timestamp', 'N/A')}")
    lines.append("")

    lines.append("## Configuration")
    lines.append("")
    lines.append("| Parameter | Value |")
    lines.append("|-----------|-------|")
    lines.append(f"| Clients | {fc.get('clients', 'N/A')} |")
    lines.append(f"| Requests | {fc.get('requests', 'N/A')} |")
    lines.append(f"| Data size | {fc.get('data_size', 'N/A')} bytes |")
    lines.append(f"| Pipeline | {fc.get('pipeline', 'N/A')} |")
    lines.append("")

    # Throughput comparison
    lines.append("## Throughput (ops/sec)")
    lines.append("")
    lines.append("Higher is better. Positive diff = Ferrite is faster.")
    lines.append("")
    lines.append("| Operation | Ferrite | Redis | Difference |")
    lines.append("|-----------|--------:|------:|-----------:|")

    for op in comp["operations"]:
        diff = format_pct_md(op["ops_sec_diff_pct"])
        lines.append(
            f"| {op['operation']} "
            f"| {op['ferrite_ops_sec']:,.2f} "
            f"| {op['redis_ops_sec']:,.2f} "
            f"| {diff} |"
        )
    lines.append("")

    # Latency comparison
    lines.append("## Latency (ms)")
    lines.append("")
    lines.append("Lower is better. Negative diff = Ferrite has lower latency.")
    lines.append("")
    lines.append(
        "| Operation | Ferrite P50 | Redis P50 | Ferrite P99 | Redis P99 | Ferrite P99.9 | Redis P99.9 |"
    )
    lines.append(
        "|-----------|------------:|----------:|------------:|----------:|--------------:|------------:|"
    )

    for op in comp["operations"]:
        lines.append(
            f"| {op['operation']} "
            f"| {op['ferrite_p50_ms']:.3f} "
            f"| {op['redis_p50_ms']:.3f} "
            f"| {op['ferrite_p99_ms']:.3f} "
            f"| {op['redis_p99_ms']:.3f} "
            f"| {op['ferrite_p999_ms']:.3f} "
            f"| {op['redis_p999_ms']:.3f} |"
        )
    lines.append("")

    # Summary
    lines.append("## Summary")
    lines.append("")

    faster_count = sum(
        1
        for op in comp["operations"]
        if op["ops_sec_diff_pct"] is not None and op["ops_sec_diff_pct"] > 0
    )
    total = len(comp["operations"])
    lines.append(
        f"Ferrite is faster in **{faster_count}/{total}** operations by throughput."
    )
    lines.append("")

    # Average throughput difference
    diffs = [
        op["ops_sec_diff_pct"]
        for op in comp["operations"]
        if op["ops_sec_diff_pct"] is not None
    ]
    if diffs:
        avg_diff = sum(diffs) / len(diffs)
        lines.append(
            f"Average throughput difference: **{format_pct(avg_diff)}**"
        )
    lines.append("")

    lines.append("---")
    lines.append("*Generated by ferrite-bench compare.py*")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Compare Ferrite and Redis benchmark results"
    )
    parser.add_argument("ferrite_json", help="Path to Ferrite benchmark JSON")
    parser.add_argument("redis_json", help="Path to Redis benchmark JSON")
    parser.add_argument(
        "-o",
        "--output",
        help="Output markdown file (default: stdout)",
        default=None,
    )
    parser.add_argument(
        "--json",
        help="Also output comparison as JSON",
        default=None,
    )
    args = parser.parse_args()

    # Load results
    ferrite = load_results(args.ferrite_json)
    redis = load_results(args.redis_json)

    # Generate comparison
    comp = generate_comparison(ferrite, redis)

    # Terminal output
    print(render_terminal(comp))

    # Markdown output
    md = render_markdown(comp)
    if args.output:
        Path(args.output).write_text(md + "\n")
        print(f"  Markdown report → {args.output}")
    else:
        print(md)

    # Optional JSON output
    if args.json:
        Path(args.json).write_text(json.dumps(comp, indent=2) + "\n")
        print(f"  JSON comparison → {args.json}")


if __name__ == "__main__":
    main()
