#!/usr/bin/env python3
"""Prepare a source-bound M6-B workspace; never approve, sign, upload or publish.

Only reviewed public inputs are copied. A new ignored directory is required;
previous owner evidence, signing files and simulator data are never overwritten.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

from release_preflight import ACCOUNT_CHECKS, GATES, LOCALES, ROOT, evaluate, git_state
from release_settings import validate


class PreparationError(ValueError):
    pass


def load(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(value, dict):
            raise ValueError("expected JSON object")
        return value
    except (OSError, ValueError) as error:
        raise PreparationError(f"Cannot read {path.name}: {error}") from error


def write(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def prepare(root: Path, output: Path) -> dict:
    root, output = root.resolve(), output.absolute()
    safe_root = root / "tests/reports/local"
    if safe_root.resolve() != safe_root:
        raise PreparationError("Local evidence root must not be a symbolic link")
    if output.resolve() != output or not output.is_relative_to(safe_root) or output == safe_root:
        raise PreparationError("Output must be a new, non-symlink directory beneath tests/reports/local/")
    if output.exists():
        raise PreparationError("Output already exists; choose a new directory to preserve previous evidence")
    head, dirty = git_state(root)
    if not head or dirty:
        raise PreparationError("Commit or preserve outstanding changes first; source must be a clean Git checkout")
    ignored = subprocess.run(["git", "check-ignore", "--quiet", str(output)], cwd=root, check=False)
    if ignored.returncode != 0:
        raise PreparationError("Output is not Git-ignored; refuse to expose local acceptance records")
    config = load(root / "appstore/release_config.json")
    errors = validate(config)
    if errors:
        raise PreparationError("; ".join(errors))
    gates = load(root / "codex/release_gates.json")
    records = gates.get("gates")
    if (not isinstance(records, list) or len(records) != len(GATES)
            or any(not isinstance(x, dict) or x.get("required") is not True or not isinstance(x.get("id"), str) for x in records)
            or {x.get("id") for x in records} != GATES):
        raise PreparationError("All agreed G01–G20 gates must remain required exactly once")
    metadata = sorted((root / "appstore/metadata").glob("*.json"))
    if {p.stem for p in metadata} != LOCALES:
        raise PreparationError("Metadata must retain all nine languages")
    for path in metadata:
        if load(path).get("locale") != path.stem:
            raise PreparationError(f"Metadata locale mismatch: {path.name}")
    for target in ("LightPlan", "LightPlanWidget"):
        path = root / "ios" / target / "PrivacyInfo.xcprivacy"
        try:
            privacy = plistlib.loads(path.read_bytes())
        except (OSError, ValueError) as error:
            raise PreparationError(f"Invalid source privacy manifest: {target}") from error
        if not isinstance(privacy, dict) or privacy.get("NSPrivacyTracking") is not False:
            raise PreparationError(f"Source privacy contract changed: {target}; review before preparation")
    tree = subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=root, text=True).strip()
    # A fresh final-source ledger never inherits historical passed attestations.
    gates["source_commit"] = head
    for record in records:
        record.update(status="pending", reviewer=None, evidence=[], source_commit=head)
    manifest = {"schema_version": 1, "source_commit": head, "distribution_model": "paid_upfront",
                "account_checks": {k: {"status": "pending", "reviewer": None, "evidence": []}
                                   for k in sorted(ACCOUNT_CHECKS)}, "screenshots": [],
                "archive": {"path": None, "source_commit": head,
                            "app_executable_sha256": None, "widget_executable_sha256": None}}
    if config.get("distribution_model") != "paid_upfront":
        raise PreparationError("Distribution must remain paid_upfront")
    # Copy only this allowlist. Local overrides, passwords and signing material are excluded.
    public_paths = [Path("appstore/review_notes.md"), Path("docs/M6B_LOCAL_HANDOFF.md"),
                    Path("docs/APP_STORE_HANDOFF.md"), Path("docs/M6_RELEASE_READINESS.md"),
                    *[p.relative_to(root) for p in metadata]]
    for relative in public_paths:
        path = root / relative
        if not path.is_file() or path.resolve() != path or not path.stat().st_size:
            raise PreparationError(f"Missing or unsafe public handoff input: {relative}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".m6a-", dir=output.parent) as temp:
        staging = Path(temp) / "package"; staging.mkdir()
        write(staging / "release_config.json", config)
        write(staging / "release_gates.json", gates)
        write(staging / "submission_manifest.json", manifest)
        for relative in public_paths:
            dest = staging / "reference" / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(root / relative, dest)
        report = evaluate(root, staging / "release_config.json", staging / "submission_manifest.json",
                          gates_path=staging / "release_gates.json")
        if report["ready_for_submission"]:
            raise PreparationError("Fresh unreviewed evidence must never pass submission readiness")
        write(staging / "preflight-blockers.json", report)
        hashes = {str(p.relative_to(staging)): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in sorted(staging.rglob("*")) if p.is_file()}
        write(staging / "preparation.json", {"prepared": True, "ready_for_submission": False,
              "created_at_utc": datetime.now(timezone.utc).isoformat(), "source_commit": head,
              "source_tree": tree, "files_sha256": hashes,
              "boundary": "Prepared local workspace only; all final-source attestations are pending. No account, device, signing or publication operations."})
        # Detect concurrent edits before publishing; leave no partially prepared package.
        if git_state(root) != (head, False):
            raise PreparationError("Source changed during preparation; preserve it and prepare again")
        if output.exists():
            raise PreparationError("Output appeared during preparation; refusing overwrite")
        staging.rename(output)
    return {"prepared": True, "ready_for_submission": False, "source_commit": head,
            "output": str(output), "submission_blockers": len(report["blockers"])}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", required=True, type=Path,
                        help="New ignored directory under tests/reports/local/")
    args = parser.parse_args()
    output = args.output if args.output.is_absolute() else args.root / args.output
    try:
        result = prepare(args.root, output)
    except (PreparationError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Release preparation failed: {error}\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
