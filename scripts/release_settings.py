"""Validated public build settings shared by project generation and release checks."""
from __future__ import annotations
import re

BUILD_FIELDS = ("candidate_name", "candidate_bundle_id", "candidate_app_group_id",
                "marketing_version", "build_number", "minimum_runtime_ios")


def validate(config: dict) -> list[str]:
    errors = []
    patterns = {
        "candidate_bundle_id": r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+",
        "candidate_app_group_id": r"group\.[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+",
        "marketing_version": r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)",
        "build_number": r"[1-9][0-9]{0,3}",
        "minimum_runtime_ios": r"[1-9][0-9]*\.[0-9]+(?:\.[0-9]+)?",
    }
    for key, pattern in patterns.items():
        value = config.get(key)
        if not isinstance(value, str) or not re.fullmatch(pattern, value):
            errors.append(f"Release configuration: invalid {key}")
    name = config.get("candidate_name")
    if not isinstance(name, str) or not name.strip() or len(name) > 30 or any(ord(c) < 32 for c in name):
        errors.append("Release configuration: invalid candidate_name")
    return errors
