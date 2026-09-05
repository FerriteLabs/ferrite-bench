#!/usr/bin/env python3
"""Ferrite-versus-Redis benchmark comparison CLI."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

if __package__:
    from .core import (
        SORTED_SET_OPS,
        ComparisonDataError,
        build_ops_map,
        generate_comparison,
        is_sorted_set_op,
        pct_diff,
    )
    from .renderers import format_pct, format_pct_md, render_markdown, render_terminal
else:
    from core import (  # type: ignore[no-redef]
        SORTED_SET_OPS,
        ComparisonDataError,
        build_ops_map,
        generate_comparison,
        is_sorted_set_op,
        pct_diff,
    )
    from renderers import (  # type: ignore[no-redef]
        format_pct,
        format_pct_md,
        render_markdown,
        render_terminal,
    )

__all__ = [
    "SORTED_SET_OPS",
    "ComparisonDataError",
    "ComparisonInputError",
    "build_ops_map",
    "format_pct",
    "format_pct_md",
    "generate_comparison",
    "is_sorted_set_op",
    "load_results",
    "main",
    "pct_diff",
    "render_markdown",
    "render_terminal",
]


class ComparisonInputError(ValueError):
    """Raised when a comparison input file cannot be loaded."""


def load_results(path: str) -> dict[str, Any]:
    """Load benchmark results from a JSON file."""
    try:
        with open(path, encoding="utf-8") as file:
            data = json.load(file)
    except FileNotFoundError as exc:
        raise ComparisonInputError(
            f"benchmark results file not found: {path}"
        ) from exc
    except OSError as exc:
        raise ComparisonInputError(
            f"cannot read benchmark results file {path}: {exc}"
        ) from exc
    except json.JSONDecodeError as exc:
        raise ComparisonInputError(f"invalid JSON in {path}: {exc}") from exc

    if not isinstance(data, dict):
        raise ComparisonInputError(f"benchmark results root must be an object: {path}")
    return data


def build_parser() -> argparse.ArgumentParser:
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
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    try:
        ferrite = load_results(args.ferrite_json)
        redis = load_results(args.redis_json)
        comparison = generate_comparison(ferrite, redis)
    except (ComparisonInputError, ComparisonDataError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    print(render_terminal(comparison))
    markdown = render_markdown(comparison)

    try:
        if args.output:
            Path(args.output).write_text(markdown + "\n", encoding="utf-8")
            print(f"  Markdown report → {args.output}")
        else:
            print(markdown)

        if args.json:
            Path(args.json).write_text(
                json.dumps(comparison, indent=2) + "\n",
                encoding="utf-8",
            )
            print(f"  JSON comparison → {args.json}")
    except OSError as exc:
        print(f"Error: cannot write comparison output: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
