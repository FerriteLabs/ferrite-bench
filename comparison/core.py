"""Pure benchmark comparison decisions."""

from __future__ import annotations

from typing import Any

SORTED_SET_OPS = {"zadd", "zrange", "zrangebyscore", "zrem", "zcard"}
METRIC_NAMES = (
    "ops_per_sec",
    "avg_latency_ms",
    "p50_latency_ms",
    "p99_latency_ms",
    "p999_latency_ms",
)


class ComparisonDataError(ValueError):
    """Raised when benchmark result data has an invalid shape."""


def build_ops_map(data: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Build an operation-to-metrics map from validated benchmark rows."""
    if "results" not in data:
        raise ComparisonDataError("benchmark data is missing required 'results'")
    results = data["results"]
    if not isinstance(results, list):
        raise ComparisonDataError("'results' must be a list")

    operations: dict[str, dict[str, Any]] = {}
    for index, row in enumerate(results, start=1):
        if not isinstance(row, dict):
            raise ComparisonDataError(f"results row {index} must be an object")
        operation = row.get("operation")
        if not isinstance(operation, str) or not operation.strip():
            raise ComparisonDataError(f"results row {index} has no valid operation")
        operations[operation] = row
    return operations


def is_sorted_set_op(operation: str) -> bool:
    """Return whether an operation is a sorted-set command."""
    return operation.lower() in SORTED_SET_OPS


def pct_diff(a: float | None, b: float | None) -> float | None:
    """Compute ``((a - b) / b) * 100`` when both values are comparable."""
    if a is None or b is None or b == 0:
        return None
    return ((a - b) / b) * 100


def _metric(row: dict[str, Any] | None, name: str) -> float | None:
    if row is None or name not in row or row[name] is None:
        return None
    value = row[name]
    if not isinstance(value, (int, float)):
        raise ComparisonDataError(f"metric '{name}' must be numeric")
    return float(value)


def generate_comparison(ferrite: dict[str, Any], redis: dict[str, Any]) -> dict[str, Any]:
    """Generate comparison data while preserving the documented output keys."""
    ferrite_ops = build_ops_map(ferrite)
    redis_ops = build_ops_map(redis)
    all_operations = sorted(ferrite_ops.keys() | redis_ops.keys())
    operations = []

    for operation in all_operations:
        ferrite_row = ferrite_ops.get(operation)
        redis_row = redis_ops.get(operation)
        entry: dict[str, Any] = {"operation": operation}

        for metric in METRIC_NAMES:
            output_name = {
                "ops_per_sec": "ops_sec",
                "avg_latency_ms": "avg_ms",
                "p50_latency_ms": "p50_ms",
                "p99_latency_ms": "p99_ms",
                "p999_latency_ms": "p999_ms",
            }[metric]
            entry[f"ferrite_{output_name}"] = _metric(ferrite_row, metric)
            entry[f"redis_{output_name}"] = _metric(redis_row, metric)

        entry["ops_sec_diff_pct"] = pct_diff(
            entry["ferrite_ops_sec"], entry["redis_ops_sec"]
        )
        entry["avg_latency_diff_pct"] = pct_diff(
            entry["ferrite_avg_ms"], entry["redis_avg_ms"]
        )
        entry["p99_latency_diff_pct"] = pct_diff(
            entry["ferrite_p99_ms"], entry["redis_p99_ms"]
        )
        operations.append(entry)

    return {
        "ferrite_config": ferrite.get("config", {}),
        "redis_config": redis.get("config", {}),
        "ferrite_timestamp": ferrite.get("timestamp", ""),
        "redis_timestamp": redis.get("timestamp", ""),
        "operations": operations,
    }
