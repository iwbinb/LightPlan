#!/usr/bin/env python3
"""Tests for CI plumbing only; these do not execute or certify the iOS app."""
import contextlib
import io
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import unittest

import ci_baseline as ci


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "ios/LightPlanVisualUITests"
        self.source.mkdir(parents=True)
        for name in ci.PHONE.values():
            methods = "func testOne() throws {}\nfunc testTwo() async throws {}"
            if name == "VisualUITests":
                methods += "\nfunc testDarkScreenAndRotationContinuity() throws {}"
            (self.source / (name + ".swift")).write_text(
                f"final class {name}: XCTestCase {{\n{methods}\n}}")

    def test_phone_shards_cover_every_test_once(self):
        found = ci.inventory(self.root)
        expected = {f"LightPlanUITests/{name}/{method}" for name, methods in found.items() for method in methods}
        shards = [ci.selection(self.root, stage) for stage in ci.PHONE]
        actual = [item for shard in shards for item in shard]
        self.assertEqual(expected, set(actual))
        self.assertEqual(len(actual), len(set(actual)))

    def test_ipad_retains_real_rotation_case(self):
        self.assertEqual(ci.selection(self.root, "ipad-rotation"), ["LightPlanUITests/" + ci.IPAD])

    def test_new_class_requires_assignment(self):
        (self.source / "New.swift").write_text("class New: XCTestCase { func testNew() {} }")
        with self.assertRaises(ValueError): ci.inventory(self.root)

    def test_missing_class_fails(self):
        (self.source / "VisualUITests.swift").unlink()
        with self.assertRaises(ValueError): ci.inventory(self.root)

    def test_helper_without_tests_is_allowed(self):
        (self.source / "Helper.swift").write_text("func helper() {}")
        self.assertEqual(len(ci.inventory(self.root)), len(ci.PHONE))

    def test_unassigned_test_extension_fails(self):
        (self.source / "Extension.swift").write_text("extension ProductUITests { func testNew() {} }")
        with self.assertRaises(ValueError): ci.inventory(self.root)

    def test_renamed_ipad_method_fails(self):
        path = self.source / "VisualUITests.swift"
        path.write_text(path.read_text().replace("testDarkScreenAndRotationContinuity", "testRenamed"))
        with self.assertRaises(ValueError): ci.selection(self.root, "ipad-rotation")

    def test_unknown_stage_fails(self):
        with self.assertRaises(ValueError): ci.selection(self.root, "typo")

    def test_duplicate_method_fails(self):
        path = self.source / "ProductUITests.swift"
        path.write_text(path.read_text().replace("testTwo", "testOne"))
        with self.assertRaises(ValueError): ci.inventory(self.root)


class DeviceTests(unittest.TestCase):
    def test_selects_numeric_latest_runtime(self):
        row = lambda id: {"name": "iPhone 17 Pro", "udid": id, "isAvailable": True}
        data = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-2": [row("old")],
                            "com.apple.CoreSimulator.SimRuntime.iOS-26-10": [row("new")],
                            "com.apple.CoreSimulator.SimRuntime.tvOS-26-20": [row("wrong")],
                            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [row("wrong-27")]}}
        self.assertEqual(ci.device(data, "iPhone 17 Pro"), "new")

    def test_missing_ipad_is_not_replaced_with_phone(self):
        with self.assertRaises(ValueError): ci.device({"devices": {}}, "iPad Pro 11-inch (M4)")

    def test_unavailable_simulator_rejected(self):
        data = {"devices": {"x.iOS-26-2": [{"name": "Phone", "udid": "x", "isAvailable": False}]}}
        with self.assertRaises(ValueError): ci.device(data, "Phone")


class SummaryTests(unittest.TestCase):
    def test_exact_positive_result(self):
        ci.validate_summary({"passedTests": 3, "failedTests": 0, "skippedTests": 0}, 3)

    def test_zero_test_false_green_rejected(self):
        with self.assertRaises(ValueError):
            ci.validate_summary({"passedTests": 0, "failedTests": 0, "skippedTests": 0}, 1)

    def test_empty_expected_set_rejected(self):
        with self.assertRaises(ValueError):
            ci.validate_summary({"passedTests": 0, "failedTests": 0, "skippedTests": 0}, 0)

    def test_failure_rejected(self):
        with self.assertRaises(ValueError):
            ci.validate_summary({"passedTests": 3, "failedTests": 1, "skippedTests": 0}, 3)

    def test_skip_rejected(self):
        with self.assertRaises(ValueError):
            ci.validate_summary({"passedTests": 2, "failedTests": 0, "skippedTests": 1}, 3)

    def test_unknown_schema_rejected(self):
        with self.assertRaises(ValueError): ci.validate_summary({}, 1)

    def test_boolean_is_not_a_test_count(self):
        with self.assertRaises(ValueError):
            ci.validate_summary({"passedTests": True, "failedTests": 0, "skippedTests": 0}, 1)

    def test_unexpected_extra_tests_rejected(self):
        with self.assertRaises(ValueError):
            ci.validate_summary({"passedTests": 4, "failedTests": 0, "skippedTests": 0}, 3)


class DeadlineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.log = Path(self.temp.name) / "stage.log"

    def run_code(self, code, timeout=5):
        with contextlib.redirect_stdout(io.StringIO()):
            result = ci.bounded_run([sys.executable, "-S", "-u", "-c", code], self.log, timeout, grace=0.1)
        return result, json.loads(self.log.with_suffix(".json").read_text())

    def test_success_retains_log_and_exit(self):
        code, data = self.run_code("print('retained')")
        self.assertEqual(code, 0)
        self.assertEqual(data["exit_code"], 0)
        self.assertIn("retained", self.log.read_text())

    def test_failure_is_not_masked(self):
        code, data = self.run_code("import sys; print('failure'); sys.exit(17)")
        self.assertEqual(code, 17)
        self.assertFalse(data["timed_out"])

    def test_timeout_preserves_partial_output(self):
        code, data = self.run_code("import time; print('before timeout'); time.sleep(10)", 1.0)
        self.assertEqual(code, 124)
        self.assertTrue(data["timed_out"])
        self.assertIn("before timeout", self.log.read_text())

    def test_sigterm_ignoring_child_is_killed(self):
        code, data = self.run_code("import time,signal; signal.signal(signal.SIGTERM, signal.SIG_IGN); print('alive'); time.sleep(10)", 1.0)
        self.assertEqual(code, 124)
        self.assertLess(data["duration_seconds"], 3)

    def test_signal_exit_is_nonzero(self):
        code, _ = self.run_code("import os,signal; os.kill(os.getpid(),signal.SIGTERM)")
        self.assertEqual(code, 128 + signal.SIGTERM)

    def test_old_evidence_is_not_overwritten(self):
        self.log.write_text("old result")
        with self.assertRaises(FileExistsError):
            self.run_code("print('new result')")
        self.assertEqual(self.log.read_text(), "old result")

    def test_invalid_timeout_rejected(self):
        for seconds in (0, -1, math.inf, math.nan):
            with self.subTest(seconds=seconds), self.assertRaises(ValueError):
                ci.bounded_run(["true"], self.log, seconds)

    def test_missing_command_fails_with_evidence(self):
        with contextlib.redirect_stdout(io.StringIO()):
            code = ci.bounded_run([str(self.log.parent / "not-a-command")], self.log, 2)
        self.assertEqual(code, 125)
        self.assertIn("error", json.loads(self.log.with_suffix(".json").read_text()))


class WiringTests(unittest.TestCase):
    def test_workflow_and_cli_stages_match(self):
        workflow = (Path(__file__).resolve().parents[1] / ".github/workflows/ci.yml").read_text()
        stages = re.findall(r"^          - ([a-z][a-z-]+)$", workflow, re.M)
        self.assertEqual(stages, list(ci.STAGES))
        self.assertIn("fail-fast: false", workflow)
        self.assertIn("if: ${{ always() }}", workflow)
        self.assertIn("--seconds 1800", workflow)
        self.assertNotIn("continue-on-error", workflow)

    def test_all_mode_propagates_stage_discovery_failure(self):
        self.assertNotEqual(self.run_all_with_fake_helper("import sys; sys.exit(7)"), 0)

    def test_all_mode_rejects_empty_stage_list(self):
        self.assertNotEqual(self.run_all_with_fake_helper("pass"), 0)

    def run_all_with_fake_helper(self, source):
        with tempfile.TemporaryDirectory() as temp:
            scripts = Path(temp) / "scripts"
            scripts.mkdir()
            (scripts / "ci_native.sh").write_text(Path(__file__).with_name("ci_native.sh").read_text())
            (scripts / "ci_baseline.py").write_text(source)
            return subprocess.run(["bash", str(scripts / "ci_native.sh")],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  timeout=10).returncode

    def test_shell_parses(self):
        script = Path(__file__).with_name("ci_native.sh")
        subprocess.run(["bash", "-n", str(script)], check=True)

    def test_existing_coordinate_and_parallel_controls_preserved(self):
        script = Path(__file__).with_name("ci_native.sh").read_text()
        self.assertIn("24.4478,118.0679", script)
        self.assertIn("-parallel-testing-enabled NO", script)
        self.assertIn("test-count-check", script)


if __name__ == "__main__":
    unittest.main(verbosity=2)
