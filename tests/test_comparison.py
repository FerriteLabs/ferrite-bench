from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from comparison.compare import (
    ComparisonDataError,
    ComparisonInputError,
    build_ops_map,
    generate_comparison,
    load_results,
    pct_diff,
    render_markdown,
    render_terminal,
)


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "comparison" / "compare.py"


class ComparisonTests(unittest.TestCase):
    def test_pct_diff_handles_relative_zero_and_missing_values(self) -> None:
        self.assertEqual(pct_diff(150.0, 100.0), 50.0)
        self.assertEqual(pct_diff(50.0, 100.0), -50.0)
        self.assertIsNone(pct_diff(10.0, 0.0))
        self.assertIsNone(pct_diff(None, 10.0))

    def test_build_ops_map_rejects_malformed_rows_explicitly(self) -> None:
        with self.assertRaisesRegex(ComparisonDataError, "missing required 'results'"):
            build_ops_map({})
        with self.assertRaisesRegex(ComparisonDataError, "row 1"):
            build_ops_map({"results": [{"ops_per_sec": 1}]})
        with self.assertRaisesRegex(ComparisonDataError, "must be a list"):
            build_ops_map({"results": "invalid"})

    def test_renderers_format_missing_metrics_without_formatting_none(self) -> None:
        ferrite = {
            "timestamp": "2026-08-04T00:00:00Z",
            "config": {"clients": 10},
            "results": [
                {
                    "operation": "GET ☕",
                    "p50_latency_ms": 0,
                    "p99_latency_ms": 0.5,
                }
            ],
        }
        redis = {
            "timestamp": "2026-08-03T00:00:00Z",
            "config": {"clients": 10},
            "results": [
                {
                    "operation": "GET ☕",
                    "ops_per_sec": 100,
                    "avg_latency_ms": 1,
                    "p50_latency_ms": 0.4,
                    "p99_latency_ms": 0.8,
                    "p999_latency_ms": 1.2,
                },
                {
                    "operation": "SET",
                    "ops_per_sec": 0,
                    "avg_latency_ms": 0,
                    "p50_latency_ms": 0,
                    "p99_latency_ms": 0,
                    "p999_latency_ms": 0,
                },
            ],
        }

        comparison = generate_comparison(ferrite, redis)
        terminal = render_terminal(comparison)
        markdown = render_markdown(comparison)

        get_row = next(row for row in comparison["operations"] if row["operation"] == "GET ☕")
        self.assertIsNone(get_row["ferrite_ops_sec"])
        self.assertIn("GET ☕", terminal)
        self.assertIn("N/A", terminal)
        self.assertIn("| GET ☕ | N/A | 100.00 | N/A |", markdown)
        self.assertIn("| SET | N/A | 0.00 | N/A |", markdown)

    def test_generate_comparison_preserves_relative_performance_shape(self) -> None:
        metrics = {
            "avg_latency_ms": 1,
            "p50_latency_ms": 1,
            "p99_latency_ms": 1,
            "p999_latency_ms": 1,
        }
        ferrite = {"results": [{"operation": "get", "ops_per_sec": 125, **metrics}]}
        redis = {"results": [{"operation": "get", "ops_per_sec": 100, **metrics}]}

        comparison = generate_comparison(ferrite, redis)

        self.assertEqual(comparison["operations"][0]["ops_sec_diff_pct"], 25.0)
        self.assertEqual(
            set(comparison),
            {
                "ferrite_config",
                "redis_config",
                "ferrite_timestamp",
                "redis_timestamp",
                "operations",
            },
        )

    def test_load_results_raises_explicit_errors(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            malformed = Path(tmp) / "bad.json"
            malformed.write_text("{bad", encoding="utf-8")
            with self.assertRaisesRegex(ComparisonInputError, "invalid JSON"):
                load_results(str(malformed))
        with self.assertRaisesRegex(ComparisonInputError, "not found"):
            load_results("missing.json")

    def test_cli_writes_reports_and_fails_without_tracebacks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            ferrite_path = tmp_path / "ferrite.json"
            redis_path = tmp_path / "redis.json"
            markdown_path = tmp_path / "report.md"
            json_path = tmp_path / "comparison.json"
            payload = {
                "timestamp": "2026-08-04",
                "config": {"clients": 1},
                "results": [
                    {
                        "operation": "get",
                        "ops_per_sec": 100,
                        "avg_latency_ms": 1,
                        "p50_latency_ms": 1,
                        "p99_latency_ms": 1,
                        "p999_latency_ms": 1,
                    }
                ],
            }
            ferrite_path.write_text(json.dumps(payload), encoding="utf-8")
            redis_path.write_text(json.dumps(payload), encoding="utf-8")

            success = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    str(ferrite_path),
                    str(redis_path),
                    "--output",
                    str(markdown_path),
                    "--json",
                    str(json_path),
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            failure = subprocess.run(
                [sys.executable, str(SCRIPT), "missing.json", str(redis_path)],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(success.returncode, 0)
            self.assertIn("Ferrite vs Redis", success.stdout)
            self.assertTrue(markdown_path.read_text(encoding="utf-8").endswith("\n"))
            self.assertEqual(json.loads(json_path.read_text(encoding="utf-8"))["operations"][0]["operation"], "get")
            self.assertEqual(failure.returncode, 1)
            self.assertIn("Error: benchmark results file not found", failure.stderr)
            self.assertNotIn("Traceback", failure.stderr)


if __name__ == "__main__":
    unittest.main()
