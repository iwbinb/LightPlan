#!/usr/bin/env python3
"""Package native XCTest screenshots without modifying the images or approving them.

Exports XCTest attachments from supplied xcresult bundles, selects the named
nine-language Today/Map/Plan captures, and creates a draft submission manifest.
It never starts a simulator, builds the app, uploads assets, or writes to Apple.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from release_preflight import LOCALES, ROOT, SCREENSHOT_SIZES, git_state, png_size

SCREENS = ("today", "map", "plan")
CAPTURE_TEST = "VisualUITests/testCoreScreensAllLanguages"
NAME = re.compile(r"^v3-(today|map|plan)-(" + "|".join(re.escape(item) for item in sorted(LOCALES, key=len, reverse=True)) + r")-light(?:_[^.]+)?\.png$")


class PackageError(ValueError):
    pass


def metadata_locales(root: Path) -> list[str]:
    files = sorted((root / "appstore/metadata").glob("*.json"))
    if {path.stem for path in files} != LOCALES:
        raise PackageError("Metadata must contain exactly the nine agreed locales")
    for path in files:
        try:
            metadata = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            raise PackageError(f"Cannot read metadata {path.name}: {error}") from error
        if not isinstance(metadata, dict) or metadata.get("locale") != path.stem:
            raise PackageError(f"Metadata locale does not match filename: {path.name}")
    return [path.stem for path in files]


def select_captures(exported: Path, family: str, locales: list[str]) -> list[dict]:
    try:
        manifest = json.loads((exported / "manifest.json").read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise PackageError(f"Cannot read {family} attachment manifest: {error}") from error
    if not isinstance(manifest, list):
        raise PackageError(f"{family} attachment manifest must be an array")
    chosen: dict[tuple[str, str], dict] = {}
    for test in manifest:
        if not isinstance(test, dict):
            raise PackageError(f"{family} attachment manifest contains a malformed test record")
        identifier = test.get("testIdentifier", "")
        if not isinstance(identifier, str) or identifier.removesuffix("()") != CAPTURE_TEST:
            continue
        attachments = test.get("attachments", [])
        if not isinstance(attachments, list):
            raise PackageError(f"{family} capture test has malformed attachments")
        for attachment in attachments:
            if not isinstance(attachment, dict):
                raise PackageError(f"{family} capture test has a malformed attachment")
            name = attachment.get("suggestedHumanReadableName", "")
            match = NAME.fullmatch(name) if isinstance(name, str) else None
            if match is None:
                continue
            screen, locale = match.groups()
            if attachment.get("isAssociatedWithFailure") is not False:
                raise PackageError(f"{family}/{locale}/{screen}: capture failure status is not explicitly false")
            filename = attachment.get("exportedFileName")
            if not isinstance(filename, str) or not filename or Path(filename).name != filename:
                raise PackageError(f"{family}/{locale}/{screen}: unsafe exported filename")
            image = (exported / filename).resolve()
            if image.parent != exported.resolve() or not image.is_file():
                raise PackageError(f"{family}/{locale}/{screen}: missing exported PNG")
            size = png_size(image)
            if size is None or tuple(sorted(size)) not in SCREENSHOT_SIZES[family]:
                raise PackageError(f"{family}/{locale}/{screen}: {size} is not an accepted primary App Store slot; use Pro Max/6.5-inch iPhone or 13-inch iPad native captures")
            key = (locale, screen)
            if key in chosen:
                raise PackageError(f"{family}/{locale}/{screen}: duplicate capture (possibly test retries); select an unambiguous result bundle")
            chosen[key] = {"locale": locale, "screen": screen, "family": family,
                           "image": image, "width": size[0], "height": size[1],
                           "sha256": hashlib.sha256(image.read_bytes()).hexdigest(),
                           "source_attachment_name": name, "source_test": identifier}
    missing = [f"{locale}/{screen}" for locale in locales for screen in SCREENS if (locale, screen) not in chosen]
    if missing:
        raise PackageError(f"{family}: missing {len(missing)} required captures: " + ", ".join(missing))
    return [chosen[(locale, screen)] for locale in locales for screen in SCREENS]


def export_attachments(bundle: Path, destination: Path) -> None:
    if not bundle.is_dir() or bundle.suffix != ".xcresult":
        raise PackageError(f"Not an xcresult bundle: {bundle.name}")
    try:
        result = subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
                                 "--output-path", str(destination)], check=False, text=True, capture_output=True)
    except OSError as error:
        raise PackageError(f"Cannot run xcresulttool: {error}") from error
    if result.returncode:
        raise PackageError(f"xcresulttool failed for {bundle.name} (exit {result.returncode}): {result.stderr.strip()}")


def package(root: Path, bundles: dict[str, Path], output: Path, source_note: str, source_commit: str | None = None) -> dict:
    root, output = root.resolve(), output.resolve()
    try:
        relative_output = output.relative_to(root)
    except ValueError as error:
        raise PackageError("Output must be inside the repository so preflight evidence paths stay portable") from error
    if output.exists():
        raise PackageError("Output already exists; choose a new directory to preserve earlier evidence")
    if not source_note.strip():
        raise PackageError("Provide a source note describing which build/source produced these captures")
    if source_commit is not None and re.fullmatch(r"[0-9a-fA-F]{40}", source_commit) is None:
        raise PackageError("--source-commit must be a full 40-character commit SHA; omit it for uncommitted source")
    if set(bundles) != {"iphone", "ipad"}:
        raise PackageError("Both iPhone and iPad xcresult bundles are required")
    locales = metadata_locales(root)
    try:
        template = json.loads((root / "appstore/submission_manifest.json").read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise PackageError(f"Cannot read submission manifest template: {error}") from error
    if not isinstance(template, dict) or not isinstance(template.get("account_checks"), dict):
        raise PackageError("Submission manifest template is malformed")
    # Never propagate approvals from a previously completed template.
    for key in template["account_checks"]:
        template["account_checks"][key] = {"status": "pending", "evidence": [], "reviewer": None}
    head, dirty = git_state(root)
    template.update({"schema_version": 1, "source_commit": source_commit.lower() if source_commit else None,
                     "status": "draft_visual_review_required", "screenshots": [],
                     "capture_source_note": source_note.strip(),
                     "packaging_context": {"created_at_utc": datetime.now(timezone.utc).isoformat(),
                                           "head_at_packaging": head or None, "worktree_dirty_at_packaging": dirty,
                                           "not_capture_provenance": True},
                     "screenshot_dimensions_reference": "https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications",
                     "boundaries": ["Native screenshots are copied byte for byte; no resizing, compositing or screenshot fabrication.",
                                    "Dimensions and attachment completeness are checked; visual quality, translations, visible MapKit attribution and loaded map tiles remain pending human review.",
                                    "This tool does not infer test success from attachments. Preserve and inspect the original xcresult test outcome separately.",
                                    "A supplied source_commit is a caller assertion. When omitted, it remains null; the packaging worktree is not asserted as the capture source.",
                                    "No device identifiers, account data or raw attachment manifests are included in this package."]})
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="lightplan-captures-") as export_temp, tempfile.TemporaryDirectory(prefix=".store-package-", dir=output.parent) as stage_temp:
        staging = Path(stage_temp) / "package"
        staging.mkdir()
        all_captures = []
        for family in ("iphone", "ipad"):
            exported = Path(export_temp) / family
            export_attachments(bundles[family].resolve(), exported)
            for capture in select_captures(exported, family, locales):
                capture["source_xcresult"] = bundles[family].name
                all_captures.append(capture)
        for capture in all_captures:
            leaf = Path(capture["locale"]) / capture["family"] / f"{SCREENS.index(capture['screen']) + 1:02}-{capture['screen']}-light.png"
            destination = staging / leaf
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(capture["image"], destination)
            template["screenshots"].append({key: value for key, value in capture.items() if key != "image"} | {
                "path": (relative_output / leaf).as_posix(), "source_commit": template["source_commit"],
                "capture_kind": "native", "review_status": "pending", "reviewer": None,
            })
        (staging / "submission-draft.json").write_text(json.dumps(template, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        (staging / "README.md").write_text(
            "# Native App Store screenshot draft\n\n"
            f"{len(all_captures)} original PNG captures: nine locales × iPhone/iPad × Today/Map/Plan.\n\n"
            "Inspect every image for content, text, layout, loaded map imagery and visible attribution. "
            "Dimensions and file hashes are checked, but visual review and account acceptance remain pending. "
            "Original xcresult bundles remain the test evidence. This package does not establish physical-device testing.\n\n"
            "`submission-draft.json` follows release_preflight's manifest shape and intentionally fails final readiness "
            "until actual source provenance, owner/account checks and human reviews are completed. "
            "Do not fill missing approvals merely to make the checker pass.\n", encoding="utf-8")
        staging.rename(output)
    return {"output": str(output), "manifest": str(output / "submission-draft.json"),
            "screenshots": len(template["screenshots"]), "locales": locales,
            "source_commit": template["source_commit"], "review_status": "pending"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iphone-xcresult", required=True, type=Path)
    parser.add_argument("--ipad-xcresult", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path, help="New directory inside repository; prefer tests/reports/local/")
    parser.add_argument("--source-note", required=True, help="Describe the source/build used for these captures; do not infer it from packaging HEAD")
    parser.add_argument("--source-commit", help="Explicit full commit SHA of captured source; omit for uncommitted source")
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        result = package(args.root, {"iphone": args.iphone_xcresult, "ipad": args.ipad_xcresult}, args.output, args.source_note, args.source_commit)
    except (PackageError, OSError) as error:
        parser.exit(1, f"Screenshot packaging failed: {error}\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
