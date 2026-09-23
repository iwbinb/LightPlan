#!/usr/bin/env python3
"""Fail closed on incomplete submission evidence; never write to an Apple account.

This checks local completeness and consistency, not App Review approval or the
truth of reviewer attestations. Use --report-only during development. Final
evidence is supplied through an ignored local copy of submission_manifest.json.
"""
from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
from pathlib import Path
import plistlib
import re
import struct
import subprocess
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
LOCALES = {"en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "th", "pt-PT"}
GATES = {f"G{i:02}" for i in range(1, 21)}
ACCOUNT_CHECKS = {
    "app_record_and_identifiers", "paid_app_configuration", "paid_agreement_tax_banking",
    "privacy_age_rating_export_compliance", "territories_and_trader_status",
    "public_urls_and_contact", "testflight_full_access_and_offline", "distribution_validation",
    "owner_submission_approval",
}
# Apple specifications checked 2026-09-22; recheck before each submission.
SCREENSHOT_SIZES = {
    "iphone": {(1260, 2736), (1290, 2796), (1320, 2868), (1284, 2778), (1242, 2688)},
    "ipad": {(2064, 2752), (2048, 2732)},
}
PLACEHOLDER = re.compile(r"OWNER_CONFIRM|placeholder|example\.(com|org|net)|\$\(|\b(TODO|TBD|pending)\b", re.I)
PUBLIC_FIELDS = {"SupportEmail": "support_email", "SupportURL": "support_url", "PrivacyPolicyURL": "privacy_url"}


def meaningful(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip()) and not PLACEHOLDER.search(value)


def public_https(value: object) -> bool:
    if not meaningful(value):
        return False
    try:
        url = urlsplit(value)
        host = url.hostname or ""
        if url.scheme != "https" or url.username or url.password or not host or url.fragment:
            return False
        if "." not in host or host.endswith((".local", ".localhost", ".invalid", ".test")):
            return False
        try:
            return ipaddress.ip_address(host).is_global
        except ValueError:
            return True
    except ValueError:
        return False


def read_json(path: Path, blockers: list[str]) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(value, dict):
            raise ValueError("expected an object")
        return value
    except (OSError, ValueError) as error:
        blockers.append(f"Cannot read {path.name}: {error}")
        return {}


def evidence_file(root: Path, value: object) -> Path | None:
    if not isinstance(value, str) or not value or Path(value).is_absolute():
        return None
    path = (root / value).resolve()
    try:
        path.relative_to(root.resolve())
        return path if path.is_file() and path.stat().st_size > 0 else None
    except (ValueError, OSError):
        return None


def attestation(root: Path, label: str, record: object, blockers: list[str]) -> None:
    if not isinstance(record, dict):
        blockers.append(f"{label}: missing acceptance record")
        return
    if record.get("status") != "passed":
        blockers.append(f"{label}: acceptance is not passed")
    if not meaningful(record.get("reviewer")):
        blockers.append(f"{label}: reviewer missing or placeholder")
    evidence = record.get("evidence")
    if not isinstance(evidence, list) or not evidence:
        blockers.append(f"{label}: evidence missing")
    else:
        for item in evidence:
            if evidence_file(root, item) is None:
                blockers.append(f"{label}: evidence must be an existing nonempty file inside the repository: {item!r}")


def git_state(root: Path) -> tuple[str, bool]:
    try:
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True, stderr=subprocess.DEVNULL).strip()
        dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=root, text=True, stderr=subprocess.DEVNULL).strip())
        return head, dirty
    except (OSError, subprocess.CalledProcessError):
        return "", True


def png_size(path: Path) -> tuple[int, int] | None:
    try:
        with path.open("rb") as stream:
            header = stream.read(24)
        if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
            return None
        return struct.unpack(">II", header[16:24])
    except OSError:
        return None


def read_plist(path: Path, label: str, blockers: list[str]) -> dict:
    try:
        value = plistlib.loads(path.read_bytes())
        if not isinstance(value, dict):
            raise ValueError("expected a dictionary")
        return value
    except (OSError, ValueError, plistlib.InvalidFileException):
        blockers.append(f"{label}: missing or malformed Info.plist")
        return {}


def check_public_fields(info: dict, config: dict, label: str, blockers: list[str]) -> None:
    for key, field in PUBLIC_FIELDS.items():
        if info.get(key) != (config.get(field) or ""):
            blockers.append(f"{label}: {key} differs from selected release configuration; regenerate and rebuild from approved tracked public fields")


def signature_problem(app: Path) -> str | None:
    try:
        result = subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)],
                                capture_output=True, text=True, timeout=30, check=False)
        return None if result.returncode == 0 else "code signature verification failed (unsigned or invalid archive)"
    except (OSError, subprocess.TimeoutExpired):
        return "code signature verification could not complete on this host"


def check_archive(root: Path, config: dict, manifest: dict, head: str,
                  archive_path: Path | None, blockers: list[str]) -> None:
    record = manifest.get("archive")
    if not isinstance(record, dict):
        blockers.append("Archive: manifest requires source_commit and app/widget executable SHA-256 records")
        record = {}
    if record.get("source_commit") != head or not head:
        blockers.append("Archive: recorded source_commit does not match current HEAD")
    if archive_path is None:
        value = record.get("path")
        if isinstance(value, str) and value and not Path(value).is_absolute():
            candidate = (root / value).resolve()
            if candidate.is_relative_to(root.resolve()):
                archive_path = candidate
    if archive_path is None:
        blockers.append("Archive: supply --archive or a repository-relative archive.path; textual passed attestations do not replace the binary")
        return
    archive_path = archive_path.resolve()
    if archive_path.suffix != ".xcarchive" or not archive_path.is_dir():
        blockers.append("Archive: the supplied xcarchive directory does not exist")
        return
    app = archive_path / "Products/Applications/LightPlan.app"
    widget = app / "PlugIns/LightPlanWidget.appex"
    app_info = read_plist(app / "Info.plist", "Archived app", blockers)
    widget_info = read_plist(widget / "Info.plist", "Archived widget", blockers)
    check_public_fields(app_info, config, "Archived app", blockers)
    for label, bundle, info, suffix, hash_key in (
        ("Archived app", app, app_info, "", "app_executable_sha256"),
        ("Archived widget", widget, widget_info, ".widget", "widget_executable_sha256"),
    ):
        if info.get("CFBundleIdentifier") != str(config.get("candidate_bundle_id", "")) + suffix:
            blockers.append(f"{label}: bundle identifier differs from release configuration")
        if info.get("AppGroupIdentifier") != config.get("candidate_app_group_id"):
            blockers.append(f"{label}: App Group identifier differs from release configuration")
        executable_name = info.get("CFBundleExecutable")
        if not isinstance(executable_name, str) or not executable_name or Path(executable_name).name != executable_name:
            blockers.append(f"{label}: missing or invalid CFBundleExecutable")
        else:
            executable = bundle / executable_name
            try:
                data = executable.read_bytes()
                if not data or hashlib.sha256(data).hexdigest() != record.get(hash_key):
                    blockers.append(f"{label}: executable hash missing or mismatched")
            except OSError:
                blockers.append(f"{label}: executable is missing")
        try:
            expected_license = (root / "licenses/astronomia-MIT.txt").read_bytes()
            actual_license = (bundle / "astronomia-MIT.txt").read_bytes()
            if not expected_license or actual_license != expected_license:
                blockers.append(f"{label}: bundled astronomy license differs from the source license")
        except OSError:
            blockers.append(f"{label}: required astronomy license is missing")
    if any(app.rglob("*.storekit")):
        blockers.append("Archive: StoreKit test configuration is present in the shipping app")
    if app.is_dir():
        problem = signature_problem(app)
        if problem:
            blockers.append("Archive: " + problem)


def evaluate(root: Path, config_path: Path, manifest_path: Path, archive_path: Path | None = None) -> dict:
    blockers: list[str] = []
    config = read_json(config_path, blockers)
    manifest = read_json(manifest_path, blockers)
    head, dirty = git_state(root)
    if dirty:
        blockers.append("Source worktree is not clean; final evidence must identify the committed source")
    if not head or manifest.get("source_commit") != head:
        blockers.append("Submission manifest source_commit does not match current HEAD")
    if manifest.get("schema_version") != 1:
        blockers.append("Submission manifest schema_version must be 1")
    if config.get("distribution_model") != "paid_upfront" or manifest.get("distribution_model") != "paid_upfront":
        blockers.append("Distribution model must be paid_upfront in release config and submission manifest")
    for key in ("release_ready", "prices_confirmed_in_store", "bundle_id_registered", "app_group_registered", "name_and_trademark_reviewed"):
        if config.get(key) is not True:
            blockers.append(f"Release configuration: {key} is not confirmed")
    for key in ("legal_owner", "support_email", "candidate_name", "candidate_bundle_id", "candidate_app_group_id"):
        if not meaningful(config.get(key)):
            blockers.append(f"Release configuration: {key} missing or placeholder")
    email = config.get("support_email")
    if not isinstance(email, str) or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email):
        blockers.append("Release configuration: support_email is not a usable address")
    for key in ("privacy_url", "support_url"):
        if not public_https(config.get(key)):
            blockers.append(f"Release configuration: {key} must be a public HTTPS URL")
    if config.get("marketing_url") is not None and not public_https(config.get("marketing_url")):
        blockers.append("Release configuration: optional marketing_url is invalid")
    tracked_config = read_json(root / "appstore/release_config.json", blockers)
    for field in PUBLIC_FIELDS.values():
        if (tracked_config.get(field) or "") != (config.get(field) or ""):
            blockers.append(f"Tracked release configuration: public field {field} differs from the selected audit config")
    source_info = read_plist(root / "ios/LightPlan/Info.plist", "Generated app", blockers)
    check_public_fields(source_info, config, "Generated app", blockers)
    check_archive(root, config, manifest, head, archive_path, blockers)
    for name in ("privacy.html", "support.html"):
        try:
            content = (root / "site" / name).read_text(encoding="utf-8")
            if not content.strip() or PLACEHOLDER.search(content) or re.search(r"Development draft|待发布|草案", content, re.I):
                blockers.append(f"Website {name}: unresolved development placeholders or draft content")
        except OSError:
            blockers.append(f"Website {name}: missing public page source")

    gates = read_json(root / "codex/release_gates.json", blockers).get("gates", [])
    if not isinstance(gates, list):
        gates = []
    ids = [item.get("id") for item in gates if isinstance(item, dict)]
    if len(ids) != len(GATES) or set(ids) != GATES:
        blockers.append("Release ledger must retain each agreed gate G01–G20 exactly once")
    for record in gates:
        if not isinstance(record, dict):
            continue
        label = str(record.get("id", "Unknown gate"))
        if record.get("required") is not True:
            blockers.append(f"{label}: required gate cannot be waived by this tool")
        attestation(root, label, record, blockers)

    checks = manifest.get("account_checks", {})
    if not isinstance(checks, dict):
        checks = {}
    for key in sorted(ACCOUNT_CHECKS):
        attestation(root, key, checks.get(key), blockers)

    metadata_paths = {path.stem: path for path in (root / "appstore/metadata").glob("*.json")}
    if set(metadata_paths) != LOCALES:
        blockers.append("App metadata must contain exactly the nine agreed locales")
    for locale, path in sorted(metadata_paths.items()):
        data = read_json(path, blockers)
        if data.get("locale") != locale:
            blockers.append(f"Metadata {locale}: locale field does not match filename")
        for field, limit in (("name", 30), ("subtitle", 30), ("promotional_text", 170), ("description", 4000)):
            value = data.get(field)
            if not meaningful(value) or len(value) > limit:
                blockers.append(f"Metadata {locale}: {field} is missing, a placeholder, or exceeds {limit} characters")
        keywords = data.get("keywords")
        if not meaningful(keywords) or len(keywords.encode("utf-8")) > 100:
            blockers.append(f"Metadata {locale}: keywords must be nonempty and at most 100 UTF-8 bytes")
        if data.get("status") != "approved_for_submission":
            blockers.append(f"Metadata {locale}: final review is incomplete")
        for field in ("privacy_url", "support_url"):
            if not public_https(data.get(field)) or data.get(field) != config.get(field):
                blockers.append(f"Metadata {locale}: {field} is missing or differs from release configuration")

    shots = manifest.get("screenshots", [])
    if not isinstance(shots, list):
        shots = []
    coverage: dict[tuple[str, str], int] = {}
    for index, shot in enumerate(shots):
        if not isinstance(shot, dict):
            blockers.append(f"Screenshot {index}: malformed record")
            continue
        key = (shot.get("locale"), shot.get("family"))
        if not all(isinstance(item, str) for item in key) or key[0] not in LOCALES or key[1] not in SCREENSHOT_SIZES:
            blockers.append(f"Screenshot {index}: unknown locale/family")
            continue
        coverage[key] = coverage.get(key, 0) + 1
        path = evidence_file(root, shot.get("path"))
        if path is None:
            blockers.append(f"Screenshot {index}: missing native PNG file")
            continue
        size = png_size(path)
        if size is None or tuple(sorted(size)) not in SCREENSHOT_SIZES[key[1]]:
            blockers.append(f"Screenshot {index}: dimensions do not match an accepted {key[1]} primary slot")
        if hashlib.sha256(path.read_bytes()).hexdigest() != shot.get("sha256"):
            blockers.append(f"Screenshot {index}: content hash missing or mismatched")
        if shot.get("source_commit") != head or shot.get("capture_kind") != "native":
            blockers.append(f"Screenshot {index}: native capture provenance does not match current HEAD")
        if not meaningful(shot.get("reviewer")):
            blockers.append(f"Screenshot {index}: visual review missing")
        if shot.get("review_status") != "passed":
            blockers.append(f"Screenshot {index}: visual review status is not passed")
    for locale in sorted(LOCALES):
        for family in SCREENSHOT_SIZES:
            count = coverage.get((locale, family), 0)
            if not 1 <= count <= 10:
                blockers.append(f"Screenshots {locale}/{family}: require 1–10 reviewed native captures; found {count}")

    return {"ready_for_submission": not blockers, "source_commit": head or None,
            "blockers": blockers,
            "boundary": "Local evidence completeness only. Does not create, upload, publish, or submit anything; human attestations and Apple account state require independent verification."}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--config", type=Path, help="Release config; use an ignored local copy for owner details")
    parser.add_argument("--manifest", type=Path, help="Final evidence manifest; use an ignored local copy")
    parser.add_argument("--archive", type=Path, help="Actual signed xcarchive; otherwise use repository-relative archive.path in manifest")
    parser.add_argument("--report-only", action="store_true", help="Print blockers but exit 0 for development; does not mark readiness")
    args = parser.parse_args()
    root = args.root.resolve()
    report = evaluate(root, args.config or root / "appstore/release_config.json", args.manifest or root / "appstore/submission_manifest.json", args.archive)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if args.report_only or report["ready_for_submission"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
