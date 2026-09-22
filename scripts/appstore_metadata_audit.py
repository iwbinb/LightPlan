#!/usr/bin/env python3
"""Validate localized App Store metadata before native CI.

This catches deterministic App Store Connect field-limit mistakes without
pretending that draft URLs, legal identity, pricing, or human translation
review have already been completed.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
METADATA = ROOT / "appstore" / "metadata"
EXPECTED = {"en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "th", "pt-PT"}

CHAR_LIMITS = {
    "name": 30,
    "subtitle": 30,
    "promotional_text": 170,
    "description": 4000,
}
REQUIRED_TEXT_FIELDS = tuple(CHAR_LIMITS) + ("keywords",)


def fail(message: str) -> None:
    raise SystemExit("App Store metadata audit failed: " + message)


files = {path.stem: path for path in METADATA.glob("*.json")}
missing = EXPECTED - files.keys()
unexpected = files.keys() - EXPECTED
if missing:
    fail("missing locale files: " + ", ".join(sorted(missing)))
if unexpected:
    fail("unexpected locale files: " + ", ".join(sorted(unexpected)))

for locale in sorted(EXPECTED):
    path = files[locale]
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"{locale}: invalid JSON: {exc}")

    if data.get("locale") != locale:
        fail(f"{locale}: locale field is {data.get('locale')!r}")

    for field in REQUIRED_TEXT_FIELDS:
        value = data.get(field)
        if not isinstance(value, str) or not value.strip():
            fail(f"{locale}: {field} must be non-empty text")

    for field, limit in CHAR_LIMITS.items():
        count = len(data[field])
        if count > limit:
            fail(f"{locale}: {field} is {count} characters; limit is {limit}")

    keyword_bytes = len(data["keywords"].encode("utf-8"))
    if keyword_bytes > 100:
        fail(f"{locale}: keywords are {keyword_bytes} UTF-8 bytes; limit is 100")

    captions = data.get("screenshot_captions")
    if not isinstance(captions, list) or not captions or not all(
        isinstance(value, str) and value.strip() for value in captions
    ):
        fail(f"{locale}: screenshot_captions must contain non-empty strings")

print(f"App Store metadata audit passed for {len(EXPECTED)} locales.")
