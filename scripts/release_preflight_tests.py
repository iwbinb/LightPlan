#!/usr/bin/env python3
"""Regression tests for submission checks; all acceptance data here is synthetic."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
from unittest.mock import patch
import zlib

import release_preflight as release

COMMIT = "a" * 40


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def write_plist(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps(value))


def png(width, height):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
    pixels = (b"\0" + b"\xff\xff\xff" * width) * height
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b"")


class ReleasePreflightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.images = {"iphone": png(1320, 2868), "ipad": png(2064, 2752)}

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "site").mkdir()
        for name in ("privacy.html", "support.html"):
            (self.root / "site" / name).write_text("Synthetic final page; used only in release tests.")
        self.acceptance = {"status": "passed", "evidence": ["evidence.txt"], "reviewer": "Synthetic test reviewer"}
        (self.root / "evidence.txt").write_text("Synthetic acceptance fixture, not real product evidence.")
        self.config = {
            "distribution_model": "paid_upfront",
            "release_ready": True, "prices_confirmed_in_store": True,
            "bundle_id_registered": True, "app_group_registered": True,
            "name_and_trademark_reviewed": True, "legal_owner": "Synthetic Owner",
            "support_email": "support@lightplan.photo", "candidate_name": "LightPlan",
            "candidate_bundle_id": "com.arenovo.lightplan", "candidate_app_group_id": "group.com.arenovo.lightplan",
            "privacy_url": "https://lightplan.photo/privacy", "support_url": "https://lightplan.photo/support",
        }
        self.gates = {"gates": [dict(copy.deepcopy(self.acceptance), id=key, required=True) for key in sorted(release.GATES)]}
        self.manifest = {"schema_version": 1, "distribution_model": "paid_upfront", "source_commit": COMMIT,
                         "account_checks": {key: copy.deepcopy(self.acceptance) for key in release.ACCOUNT_CHECKS}, "screenshots": []}
        write_json(self.root / "appstore/release_config.json", self.config)
        self.public_fields = {key: self.config[field] for key, field in release.PUBLIC_FIELDS.items()}
        write_plist(self.root / "ios/LightPlan/Info.plist", self.public_fields)
        self.archive = self.root / "candidate.xcarchive"
        self.app = self.archive / "Products/Applications/LightPlan.app"
        self.widget = self.app / "PlugIns/LightPlanWidget.appex"
        self.manifest["archive"] = {"path": "candidate.xcarchive", "source_commit": COMMIT}
        source_license = self.root / "licenses/astronomia-MIT.txt"
        source_license.parent.mkdir()
        source_license.write_bytes(b"Synthetic license fixture")
        for bundle, name, suffix, hash_key in (
            (self.app, "LightPlan", "", "app_executable_sha256"),
            (self.widget, "LightPlanWidget", ".widget", "widget_executable_sha256"),
        ):
            info = {"CFBundleExecutable": name, "CFBundleIdentifier": self.config["candidate_bundle_id"] + suffix,
                    "AppGroupIdentifier": self.config["candidate_app_group_id"]}
            if not suffix:
                info.update(self.public_fields)
            write_plist(bundle / "Info.plist", info)
            executable = b"Synthetic binary, never installed or executed: " + name.encode()
            (bundle / name).write_bytes(executable)
            self.manifest["archive"][hash_key] = hashlib.sha256(executable).hexdigest()
            (bundle / "astronomia-MIT.txt").write_bytes(source_license.read_bytes())
        signature_patcher = patch.object(release, "signature_problem", return_value=None)
        self.signature = signature_patcher.start()
        self.addCleanup(signature_patcher.stop)
        for family, content in self.images.items():
            (self.root / f"{family}.png").write_bytes(content)
            for locale in release.LOCALES:
                self.manifest["screenshots"].append({"locale": locale, "family": family, "path": f"{family}.png",
                    "sha256": hashlib.sha256(content).hexdigest(), "source_commit": COMMIT,
                    "capture_kind": "native", "review_status": "passed", "reviewer": "Synthetic reviewer"})
        for locale in release.LOCALES:
            write_json(self.root / f"appstore/metadata/{locale}.json", {"locale": locale, "name": "LightPlan",
                "subtitle": "Plan a photo", "promotional_text": "Plan sunlight and moonlight.",
                "description": "Synthetic metadata for release validation tests.", "keywords": "sun,moon,photo",
                "status": "approved_for_submission",
                "privacy_url": self.config["privacy_url"], "support_url": self.config["support_url"]})
        patcher = patch.object(release, "git_state", return_value=(COMMIT, False))
        self.git_state = patcher.start()
        self.addCleanup(patcher.stop)

    def result(self, archive_path=None):
        write_json(self.root / "config.json", self.config)
        write_json(self.root / "manifest.json", self.manifest)
        write_json(self.root / "codex/release_gates.json", self.gates)
        return release.evaluate(self.root, self.root / "config.json", self.root / "manifest.json", archive_path)

    def assertBlocked(self, fragment):
        result = self.result()
        self.assertFalse(result["ready_for_submission"])
        self.assertTrue(any(fragment in item for item in result["blockers"]), result["blockers"])

    def test_complete_synthetic_package_passes(self):
        self.assertEqual(self.result()["blockers"], [])

    def test_external_audit_config_cannot_override_unshipped_public_fields(self):
        write_json(self.root / "appstore/release_config.json", dict(self.config, support_url=None))
        write_plist(self.root / "ios/LightPlan/Info.plist", dict(self.public_fields, SupportURL=""))
        self.assertBlocked("public field support_url differs")
        self.assertBlocked("Generated app: SupportURL differs")

    def test_stale_generated_plist_is_rejected_with_correct_tracked_config(self):
        write_plist(self.root / "ios/LightPlan/Info.plist", dict(self.public_fields, PrivacyPolicyURL=""))
        self.assertBlocked("Generated app: PrivacyPolicyURL differs")

    def test_passed_account_attestations_do_not_replace_an_archive(self):
        del self.manifest["archive"]
        self.assertBlocked("textual passed attestations do not replace the binary")

    def test_explicit_archive_argument_is_supported(self):
        del self.manifest["archive"]["path"]
        self.assertEqual(self.result(archive_path=self.archive)["blockers"], [])

    def test_archived_public_fields_and_identifiers_must_match(self):
        info = plistlib.loads((self.app / "Info.plist").read_bytes())
        info.update(SupportEmail="wrong@lightplan.photo", CFBundleIdentifier="wrong.bundle")
        write_plist(self.app / "Info.plist", info)
        self.assertBlocked("Archived app: SupportEmail differs")
        self.assertBlocked("Archived app: bundle identifier differs")

    def test_archive_must_identify_current_source_and_exact_executables(self):
        self.manifest["archive"]["source_commit"] = "b" * 40
        (self.widget / "LightPlanWidget").write_bytes(b"Changed binary")
        self.assertBlocked("Archive: recorded source_commit")
        self.assertBlocked("Archived widget: executable hash missing or mismatched")

    def test_shipping_test_configuration_is_rejected(self):
        (self.widget / "test.storekit").write_text("Synthetic test data")
        self.assertBlocked("StoreKit test configuration is present")

    def test_both_embedded_licenses_are_required_and_compared(self):
        (self.app / "astronomia-MIT.txt").write_bytes(b"Changed license")
        (self.widget / "astronomia-MIT.txt").unlink()
        self.assertBlocked("Archived app: bundled astronomy license differs")
        self.assertBlocked("Archived widget: required astronomy license is missing")

    def test_invalid_signature_blocks_submission(self):
        self.signature.return_value = "code signature verification failed (unsigned or invalid archive)"
        self.assertBlocked("code signature verification failed")

    def test_pending_account_never_passes_with_existing_evidence(self):
        self.manifest["account_checks"]["paid_app_configuration"]["status"] = "pending"
        self.assertBlocked("paid_app_configuration: acceptance is not passed")

    def test_missing_gate_or_waived_requirement_cannot_bypass(self):
        self.gates["gates"].pop()
        self.gates["gates"][0]["required"] = False
        self.assertBlocked("retain each agreed gate")
        self.assertBlocked("required gate cannot be waived")

    def test_nonexistent_empty_and_escaping_evidence_are_rejected(self):
        (self.root / "empty.txt").touch()
        for invalid in ("missing.txt", "empty.txt", "../outside.txt", str(self.root / "evidence.txt")):
            with self.subTest(invalid=invalid):
                self.gates["gates"][0]["evidence"] = [invalid]
                self.assertBlocked("existing nonempty file inside")

    def test_placeholder_reviewers_and_config_are_rejected(self):
        self.config["legal_owner"] = "OWNER_CONFIRM_LEGAL_ENTITY"
        self.gates["gates"][0]["reviewer"] = "TBD"
        self.assertBlocked("legal_owner missing or placeholder")
        self.assertBlocked("reviewer missing or placeholder")

    def test_public_url_rejects_private_credentials_and_placeholders(self):
        for value in (None, "http://lightplan.photo", "https://127.0.0.1/privacy", "https://192.168.1.1/privacy",
                      "https://user:secret@lightplan.photo", "https://example.com/privacy", "https://local.test/privacy"):
            with self.subTest(value=value):
                self.assertFalse(release.public_https(value))
        self.assertTrue(release.public_https("https://lightplan.photo/privacy"))

    def test_stale_commit_and_uncommitted_changes_block(self):
        self.git_state.return_value = ("b" * 40, True)
        self.assertBlocked("not clean")
        self.assertBlocked("does not match current HEAD")

    def test_draft_metadata_and_url_mismatch_block(self):
        write_json(self.root / "appstore/metadata/en.json", {"status": "draft", "privacy_url": "https://lightplan.photo/old"})
        self.assertBlocked("Metadata en: final review is incomplete")
        self.assertBlocked("privacy_url is missing or differs")

    def test_approved_but_empty_metadata_still_blocks(self):
        write_json(self.root / "appstore/metadata/en.json", {"status": "approved_for_submission"})
        self.assertBlocked("Metadata en: description is missing")

    def test_website_placeholders_block_even_with_confirmed_config(self):
        (self.root / "site/privacy.html").write_text("OWNER_CONFIRM_LEGAL_ENTITY")
        self.assertBlocked("Website privacy.html: unresolved")

    def test_screenshots_require_primary_dimensions_and_current_hash(self):
        self.manifest["screenshots"][0]["path"] = "wrong.png"
        (self.root / "wrong.png").write_bytes(png(1206, 2622))
        self.assertBlocked("dimensions do not match")
        self.assertBlocked("content hash missing or mismatched")

    def test_missing_locale_coverage_cannot_pass(self):
        self.manifest["screenshots"] = [item for item in self.manifest["screenshots"] if item["locale"] != "th"]
        self.assertBlocked("Screenshots th/ipad")

    def test_screenshot_pending_review_cannot_pass_with_reviewer_name(self):
        self.manifest["screenshots"][0]["review_status"] = "pending"
        self.assertBlocked("visual review status is not passed")

    def test_obsolete_in_app_purchase_model_blocks(self):
        self.config["distribution_model"] = "free_with_iap"
        self.assertBlocked("Distribution model must be paid_upfront")

    def test_malformed_top_level_records_fail_closed(self):
        self.manifest["account_checks"] = []
        self.manifest["screenshots"] = [None]
        self.gates["gates"] = None
        self.assertBlocked("missing acceptance record")
        self.assertBlocked("malformed record")


if __name__ == "__main__":
    unittest.main()
