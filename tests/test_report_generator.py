from __future__ import annotations

import contextlib
import importlib
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "benchmarks" / "report_generator.py"
report_generator = importlib.import_module("benchmarks.report_generator")


class ReportGeneratorTests(unittest.TestCase):
    def setUp(self) -> None:
        report_generator._update_baseline("redis")

    def write_csv(self, directory: Path, content: str, name: str = "data.csv") -> Path:
        path = directory / name
        path.write_text(content, encoding="utf-8")
        return path

    def test_load_csv_detects_delimiter_and_preserves_unicode(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write_csv(
                Path(tmp),
                "server;scenario;label;ratio;pipeline;data_size_bytes;duration_secs;"
                "ops_sec;avg_latency_ms;p50_latency_ms;p99_latency_ms;p999_latency_ms;"
                "cpu_percent;memory_mib\n"
                "redis;get;Lecture café ☕;0:1;1;128;60;1000;1;0.5;2;3;10%;64\n",
            )

            data = report_generator.load_csv([str(path)])

        self.assertEqual(data.servers, ["redis"])
        self.assertEqual(data.scenarios, ["get"])
        self.assertEqual(data.labels["get"], "Lecture café ☕")
        self.assertEqual(data.rows[0].cpu_percent, 10.0)

    def test_load_csv_skips_rows_missing_identity_and_defaults_bad_metrics(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write_csv(
                Path(tmp),
                "server,scenario,label,ratio,pipeline,data_size_bytes,duration_secs,"
                "ops_sec,avg_latency_ms,p50_latency_ms,p99_latency_ms,p999_latency_ms,"
                "cpu_percent,memory_mib\n"
                ",get,missing server,0:1,1,128,60,100,1,1,1,1,1,1\n"
                "ferrite,set,Malformed metrics,1:0,1,nope,invalid,not-a-number,,,,,,\n",
            )
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                data = report_generator.load_csv([str(path)])

        self.assertEqual(len(data.rows), 1)
        self.assertEqual(data.rows[0].server, "ferrite")
        self.assertEqual(data.rows[0].ops_sec, 0.0)
        self.assertEqual(data.rows[0].duration_secs, 0)
        self.assertIn("missing server or scenario", stderr.getvalue())

    def test_relative_performance_marks_zero_or_missing_data_unavailable(self) -> None:
        row = report_generator.BenchmarkRow
        data = report_generator.ReportData(
            rows=[
                row("redis", "get", "GET", "0:1", "1", 128, 60, 100.0, 1, 1, 1, 1, 1, 1),
                row("ferrite", "get", "GET", "0:1", "1", 128, 60, 125.0, 1, 1, 1, 1, 1, 1),
                row("redis", "set", "SET", "1:0", "1", 128, 60, 0.0, 1, 1, 1, 1, 1, 1),
            ],
            servers=["redis", "ferrite"],
            scenarios=["get", "set", "missing"],
            labels={"get": "GET", "set": "SET"},
        )

        relative = report_generator.compute_relative_performance(data)

        self.assertEqual(relative["ferrite"]["get"], 125.0)
        self.assertIsNone(relative["ferrite"]["set"])
        self.assertIsNone(relative["ferrite"]["missing"])

    def test_blank_duration_is_not_replaced_with_plausible_default(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write_csv(
                Path(tmp),
                "server,scenario,label,ratio,pipeline,data_size_bytes,duration_secs,"
                "ops_sec,avg_latency_ms,p50_latency_ms,p99_latency_ms,p999_latency_ms,"
                "cpu_percent,memory_mib\n"
                "redis,get,GET,0:1,1,128,,1000,1,0.5,2,3,10,64\n",
            )
            data = report_generator.load_csv([str(path)])

        output = io.StringIO()
        with mock.patch.object(report_generator, "get_system_info", return_value=[]):
            report_generator.generate_markdown(data, output)

        self.assertEqual(data.rows[0].duration_secs, 0)
        self.assertIn("| Duration per scenario | N/A |", output.getvalue())

    def test_generate_markdown_formats_missing_and_unicode_data(self) -> None:
        row = report_generator.BenchmarkRow
        data = report_generator.ReportData(
            rows=[
                row("redis", "get", "GET — café", "0:1", "1", 128, 60, 100.0, 1, 0.5, 2, 3, 0, 0),
                row("ferrite", "get", "GET — café", "0:1", "1", 128, 60, 125.0, 0, 0, 0, 0, 0, 0),
            ],
            servers=["redis", "ferrite"],
            scenarios=["get", "set"],
            labels={"get": "GET — café", "set": "SET"},
        )
        output = io.StringIO()

        with mock.patch.object(report_generator, "get_system_info", return_value=[("OS", "Test")]):
            report_generator.generate_markdown(data, output)

        markdown = output.getvalue()
        self.assertIn("GET — café", markdown)
        self.assertIn("| SET | N/A | N/A |", markdown)
        self.assertIn("| ferrite | 125.00 | N/A | N/A | N/A | N/A | 0.0 | N/A |", markdown)
        self.assertIn("| GET — café | 125.0% |", markdown)
        self.assertIn("## Latency Percentile Distribution", markdown)

    def test_generate_markdown_uses_updated_baseline_for_relative_performance(self) -> None:
        row = report_generator.BenchmarkRow
        data = report_generator.ReportData(
            rows=[
                row("redis", "get", "GET", "0:1", "1", 128, 60, 100.0, 1, 1, 1, 1, 1, 1),
                row("valkey", "get", "GET", "0:1", "1", 128, 60, 50.0, 1, 1, 1, 1, 1, 1),
                row("ferrite", "get", "GET", "0:1", "1", 128, 60, 200.0, 1, 1, 1, 1, 1, 1),
            ],
            servers=["redis", "valkey", "ferrite"],
            scenarios=["get"],
            labels={"get": "GET"},
        )
        output = io.StringIO()
        report_generator._update_baseline("valkey")

        with mock.patch.object(report_generator, "get_system_info", return_value=[]):
            report_generator.generate_markdown(data, output)

        markdown = output.getvalue()
        self.assertIn("Relative Performance (vs valkey = 100%)", markdown)
        self.assertIn("| GET | 200.0% | 400.0% |", markdown)

    def test_cli_fails_explicitly_when_no_valid_input_exists(self) -> None:
        result = subprocess.run(
            [sys.executable, str(MODULE_PATH), "does-not-exist.csv"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("Error: No valid benchmark data", result.stderr)
        self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
