from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from scripts import compare

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "compare.py"


class MoonshotComparisonTests(unittest.TestCase):
    def test_resolve_metric_handles_missing_and_non_numeric_values(self) -> None:
        self.assertEqual(compare.resolve_metric({"metrics": {"p50": "12.5"}}, "metrics.p50"), 12.5)
        self.assertIsNone(compare.resolve_metric({"metrics": {}}, "metrics.p50"))
        self.assertIsNone(compare.resolve_metric({"metrics": {"p50": "N/A"}}, "metrics.p50"))

    def test_compute_change_respects_direction_and_zero_baseline(self) -> None:
        self.assertEqual(compare.compute_change(100, 110, "lower_is_better"), (10.0, True))
        self.assertEqual(compare.compute_change(100, 110, "higher_is_better"), (-10.0, False))
        self.assertEqual(compare.compute_change(100, 90, "higher_is_better"), (10.0, True))
        self.assertEqual(compare.compute_change(0, 100, "lower_is_better"), (0.0, False))
        with self.assertRaisesRegex(compare.ComparisonError, "direction"):
            compare.compute_change(100, 90, "sideways")

    def test_compare_headlines_reports_missing_threshold_and_ceiling_failures(self) -> None:
        headlines = {
            "latency café": {
                "metric_path": "metrics.latency",
                "direction": "lower_is_better",
                "threshold_percent": 5,
                "hard_ceiling_us": 105,
                "unit": "µs",
            },
            "missing": {"metric_path": "metrics.absent"},
        }

        rows, failures = compare.compare_headlines(
            {"metrics": {"latency": 100}},
            {"metrics": {"latency": 110}},
            headlines,
        )

        self.assertEqual(rows[0][0], "latency café")
        self.assertEqual(rows[0][4], "CEIL")
        self.assertEqual(rows[1][1], "MISSING")
        self.assertEqual(len(failures), 3)

    def test_compare_headlines_rejects_invalid_numeric_configuration(self) -> None:
        baseline = {"metrics": {"latency": 100}}
        candidate = {"metrics": {"latency": 110}}

        for setting, value in (
            ("threshold_percent", "bad"),
            ("threshold_percent", -1),
            ("hard_ceiling_us", "bad"),
            ("hard_ceiling_us", float("inf")),
        ):
            with self.subTest(setting=setting, value=value):
                headlines = {
                    "latency": {
                        "metric_path": "metrics.latency",
                        setting: value,
                    }
                }
                with self.assertRaisesRegex(compare.ComparisonError, setting):
                    compare.compare_headlines(baseline, candidate, headlines)

    def test_cli_handles_success_regression_missing_rows_and_malformed_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            baseline_path = tmp_path / "baseline.json"
            candidate_path = tmp_path / "candidate.json"
            malformed_path = tmp_path / "malformed.json"
            baseline = {
                "moonshot": "mnemo",
                "metrics": {
                    "recall_latency_p50_us": 10,
                    "recall_latency_p99_us": 20,
                    "write_throughput_ops": 1000,
                },
            }
            candidate = {
                "moonshot": "mnemo",
                "metrics": {
                    "recall_latency_p50_us": 10,
                    "recall_latency_p99_us": 20,
                    "write_throughput_ops": 1000,
                },
            }
            baseline_path.write_text(json.dumps(baseline), encoding="utf-8")
            candidate_path.write_text(json.dumps(candidate), encoding="utf-8")
            malformed_path.write_text("{bad", encoding="utf-8")

            success = subprocess.run(
                [sys.executable, str(SCRIPT), str(baseline_path), str(candidate_path)],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

            candidate["metrics"]["write_throughput_ops"] = 900
            candidate_path.write_text(json.dumps(candidate), encoding="utf-8")
            regression = subprocess.run(
                [sys.executable, str(SCRIPT), str(baseline_path), str(candidate_path)],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

            candidate["metrics"].pop("recall_latency_p99_us")
            candidate_path.write_text(json.dumps(candidate), encoding="utf-8")
            missing = subprocess.run(
                [sys.executable, str(SCRIPT), str(baseline_path), str(candidate_path)],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

            malformed = subprocess.run(
                [sys.executable, str(SCRIPT), str(malformed_path), str(candidate_path)],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

        self.assertEqual(success.returncode, 0)
        self.assertIn("All headline metrics within threshold. ✓", success.stdout)
        self.assertEqual(regression.returncode, 1)
        self.assertIn("REGRESSIONS DETECTED", regression.stdout)
        self.assertEqual(missing.returncode, 1)
        self.assertIn("MISSING", missing.stdout)
        self.assertEqual(malformed.returncode, 2)
        self.assertIn("ERROR: Invalid JSON", malformed.stderr)
        self.assertNotIn("Traceback", malformed.stderr)


if __name__ == "__main__":
    unittest.main()
