#!/usr/bin/env python3
"""Synthetic attachment tests; these fixtures are never product screenshots."""
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

import package_store_screenshots as package
from release_preflight_tests import png, write_json


class ScreenshotPackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.images = {"iphone": png(1320, 2868), "ipad": png(2064, 2752)}

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.output = self.root / "draft-output"
        for locale in package.LOCALES:
            write_json(self.root / f"appstore/metadata/{locale}.json", {"locale": locale})
        write_json(self.root / "appstore/submission_manifest.json", {"schema_version": 1,
            "distribution_model": "paid_upfront", "account_checks": {"owner_submission_approval": {
                "status": "passed", "reviewer": "Must not propagate", "evidence": ["old"]}}})
        self.exports = {}
        self.bundles = {}
        for family, image in self.images.items():
            exported = self.root / f"exported-{family}"
            exported.mkdir()
            (exported / "capture.png").write_bytes(image)
            attachments = []
            for locale in package.LOCALES:
                for screen in package.SCREENS:
                    attachments.append({"exportedFileName": "capture.png", "isAssociatedWithFailure": False,
                        "suggestedHumanReadableName": f"v3-{screen}-{locale}-light_0_SYNTHETIC.png",
                        "deviceId": "PRIVATE-DEVICE-ID", "deviceName": "PRIVATE-DEVICE-NAME"})
            write_json(exported / "manifest.json", [{"testIdentifier": package.CAPTURE_TEST + "()", "attachments": attachments}])
            self.exports[family] = exported
            bundle = self.root / f"{family}.xcresult"
            bundle.mkdir()
            self.bundles[family] = bundle
        patcher = patch.object(package, "git_state", return_value=("a" * 40, True))
        patcher.start()
        self.addCleanup(patcher.stop)

    def change_attachments(self, family, mutate):
        path = self.exports[family] / "manifest.json"
        manifest = json.loads(path.read_text())
        mutate(manifest[0]["attachments"])
        write_json(path, manifest)

    def run_package(self, commit=None):
        def export(bundle, destination):
            shutil.copytree(self.exports[bundle.stem], destination)
        with patch.object(package, "export_attachments", side_effect=export):
            return package.package(self.root, self.bundles, self.output, "Synthetic uncommitted capture fixture", commit)

    def test_complete_package_preserves_bytes_and_marks_all_reviews_pending(self):
        result = self.run_package()
        self.assertEqual(result["screenshots"], 54)
        data = json.loads((self.output / "submission-draft.json").read_text())
        self.assertIsNone(data["source_commit"])
        self.assertEqual(data["distribution_model"], "paid_upfront")
        for item in data["screenshots"]:
            self.assertEqual((self.root / item["path"]).read_bytes(), self.images[item["family"]])
            self.assertEqual(item["review_status"], "pending")
            self.assertIsNone(item["reviewer"])
            self.assertIsNone(item["source_commit"])
        self.assertEqual(data["account_checks"]["owner_submission_approval"]["status"], "pending")
        text = json.dumps(data)
        self.assertNotIn("PRIVATE-DEVICE", text)

    def test_explicit_commit_is_retained_as_caller_assertion(self):
        result = self.run_package("b" * 40)
        self.assertEqual(result["source_commit"], "b" * 40)

    def test_existing_output_is_never_overwritten(self):
        self.output.mkdir()
        marker = self.output / "keep.txt"
        marker.write_text("preserve")
        with self.assertRaisesRegex(package.PackageError, "already exists"):
            self.run_package()
        self.assertEqual(marker.read_text(), "preserve")

    def test_missing_locale_screen_fails_without_partial_package(self):
        self.change_attachments("ipad", lambda items: items.pop())
        with self.assertRaisesRegex(package.PackageError, "missing 1 required captures"):
            self.run_package()
        self.assertFalse(self.output.exists())

    def test_primary_dimensions_required(self):
        (self.exports["iphone"] / "capture.png").write_bytes(png(1206, 2622))
        with self.assertRaisesRegex(package.PackageError, "not an accepted primary"):
            self.run_package()

    def test_test_retries_do_not_silently_choose_a_capture(self):
        self.change_attachments("iphone", lambda items: items.append(dict(items[0])))
        with self.assertRaisesRegex(package.PackageError, "duplicate capture"):
            self.run_package()

    def test_failure_associated_capture_is_rejected(self):
        self.change_attachments("iphone", lambda items: items[0].update(isAssociatedWithFailure=True))
        with self.assertRaisesRegex(package.PackageError, "failure status"):
            self.run_package()

    def test_export_path_traversal_rejected(self):
        self.change_attachments("iphone", lambda items: items[0].update(exportedFileName="../capture.png"))
        with self.assertRaisesRegex(package.PackageError, "unsafe exported filename"):
            self.run_package()

    def test_metadata_locale_mismatch_rejected(self):
        write_json(self.root / "appstore/metadata/pt-PT.json", {"locale": "pt-BR"})
        with self.assertRaisesRegex(package.PackageError, "does not match filename"):
            self.run_package()

    def test_invalid_commit_does_not_get_assigned_to_captures(self):
        with self.assertRaisesRegex(package.PackageError, "full 40-character"):
            self.run_package("HEAD")


if __name__ == "__main__":
    unittest.main()
