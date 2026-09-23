#!/usr/bin/env python3
"""Validate the published backup contract using the independent JSON Schema engine.

Install appstore/release_validation_requirements.txt in a development environment.
The native core remains the authority for timezone, calendar and geometry rules.
"""
from datetime import datetime
import json
from pathlib import Path
import unittest

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
FORMATS = FormatChecker()


@FORMATS.checks("date-time", raises=ValueError)
def aware_iso_instant(value):
    # jsonschema otherwise silently skips date-time without an optional extra.
    # The app's archive uses ISO-8601 absolute instants, including a timezone.
    if not isinstance(value, str):
        return True  # The schema's type constraint owns non-string failures.
    return "T" in value and datetime.fromisoformat(value.replace("Z", "+00:00")).tzinfo is not None


class ArchiveSchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        schema = json.loads((ROOT / "docs/archive.schema.json").read_text())
        Draft202012Validator.check_schema(schema)
        cls.validator = Draft202012Validator(schema, format_checker=FORMATS)

    def setUp(self):
        place = {"id": "284d0ac7-9290-4c30-bf69-5d8c514674ba", "name": "Fixture",
                 "coordinate": {"latitude": 24.4478, "longitude": 118.0679}, "timeZoneID": "Asia/Shanghai"}
        self.plan = {"id": "07053d74-cdb3-41cb-9a9d-c012e185d334", "title": "Sunset",
                     "place": place, "date": "2026-09-22T04:00:00Z", "target": "sunset",
                     "arrivalLeadMinutes": 30, "reminderLeadMinutes": 30,
                     "createdAt": "2026-09-22T00:00:00Z", "updatedAt": "2026-09-22T00:00:00Z"}
        self.archive = {"schemaVersion": 1, "places": [place], "plans": [self.plan]}
        self.composition = {"body": "moon", "subject": {"latitude": 24.449, "longitude": 118.069},
                            "desiredOffsetDegrees": 10, "instant": "2026-09-22T12:00:00Z"}

    def valid(self):
        return not list(self.validator.iter_errors(self.archive))

    def test_legacy_v1_with_missing_optional_fields(self):
        self.assertTrue(self.valid())

    def test_v2_accepts_solar_plan_with_notes(self):
        self.archive["schemaVersion"] = 2
        self.plan["notes"] = "Bring tripod; confirm access."
        self.assertTrue(self.valid())

    def test_v2_accepts_composition_and_null_notes(self):
        self.archive["schemaVersion"] = 2
        self.plan.update(target="composition", composition=self.composition, notes=None)
        self.assertTrue(self.valid())

    def test_v1_rejects_composition(self):
        self.plan.update(target="composition", composition=self.composition)
        self.assertFalse(self.valid())

    def test_composition_target_requires_snapshot(self):
        self.archive["schemaVersion"] = 2
        self.plan["target"] = "composition"
        self.assertFalse(self.valid())
        self.plan["composition"] = None
        self.assertFalse(self.valid())

    def test_solar_target_rejects_composition_snapshot(self):
        self.archive["schemaVersion"] = 2
        self.plan["composition"] = self.composition
        self.assertFalse(self.valid())

    def test_invalid_version_and_malformed_snapshot(self):
        for version in (0, 3, 1.5):
            with self.subTest(version=version):
                self.archive["schemaVersion"] = version
                self.assertFalse(self.valid())
        self.archive["schemaVersion"] = 2
        self.plan.update(target="composition", composition=self.composition)
        for field, bad in (("body", "planet"), ("desiredOffsetDegrees", 91), ("instant", "not-a-date")):
            with self.subTest(field=field):
                original = self.composition[field]
                self.composition[field] = bad
                self.assertFalse(self.valid())
                self.composition[field] = original

    def test_notes_limit(self):
        self.archive["schemaVersion"] = 2
        self.plan["notes"] = "a" * 2000
        self.assertTrue(self.valid())
        self.plan["notes"] += "a"
        self.assertFalse(self.valid())

    def test_v2_optional_search_constraints_round_trip_shape(self):
        self.archive["schemaVersion"] = 2
        self.plan.update(target="composition", composition=self.composition)
        self.composition["constraints"] = {
            "maximumErrorDegrees": 3,
            "altitudeRange": {"lowerBound": 0, "upperBound": 15},
            "solarAltitudeRange": {"lowerBound": -6, "upperBound": 6},
        }
        self.assertTrue(self.valid())
        self.composition["constraints"]["solarAltitudeRange"] = None
        self.assertTrue(self.valid())
        del self.composition["constraints"]["solarAltitudeRange"]
        self.assertTrue(self.valid())
        self.composition["constraints"] = None
        self.assertTrue(self.valid())
        del self.composition["constraints"]
        self.assertTrue(self.valid())

    def test_search_constraints_require_explicit_bounded_fields(self):
        self.archive["schemaVersion"] = 2
        self.plan.update(target="composition", composition=self.composition)
        for invalid in (
            {},
            {"maximumErrorDegrees": 181, "altitudeRange": {"lowerBound": 0, "upperBound": 15}},
            {"maximumErrorDegrees": 3, "altitudeRange": {"lowerBound": -91, "upperBound": 15}},
            {"maximumErrorDegrees": 3, "altitudeRange": {"lowerBound": 0}},
            {"maximumErrorDegrees": 3, "altitudeRange": [0, 15]},
            {"maximumErrorDegrees": 3, "altitudeRange": {"lowerBound": 0, "upperBound": 15},
             "solarAltitudeRange": {"lowerBound": -6, "upperBound": 91}},
        ):
            with self.subTest(constraints=invalid):
                self.composition["constraints"] = invalid
                self.assertFalse(self.valid())

    def test_optional_camera_snapshot_and_legacy_absence(self):
        self.archive["schemaVersion"] = 2
        self.plan.update(target="composition", composition=self.composition)
        self.assertTrue(self.valid())
        self.composition["cameraFraming"] = None
        self.assertTrue(self.valid())
        for focal_length, orientation, altitude in ((14, "landscape", -30), (1200, "portrait", 60)):
            with self.subTest(focal_length=focal_length, orientation=orientation):
                self.composition["cameraFraming"] = {
                    "focalLength35mm": focal_length,
                    "orientation": orientation,
                    "referenceAltitudeDegrees": altitude,
                }
                self.assertTrue(self.valid())

    def test_camera_snapshot_requires_finite_bounded_fields_and_known_orientation(self):
        self.archive["schemaVersion"] = 2
        self.plan.update(target="composition", composition=self.composition)
        camera = {"focalLength35mm": 50, "orientation": "landscape", "referenceAltitudeDegrees": 0}
        self.composition["cameraFraming"] = camera
        for field, invalid in (
            ("focalLength35mm", 13.99), ("focalLength35mm", 1200.01),
            ("focalLength35mm", "NaN"), ("focalLength35mm", None),
            ("orientation", "square"), ("orientation", 90),
            ("referenceAltitudeDegrees", -30.01), ("referenceAltitudeDegrees", 60.01),
            ("referenceAltitudeDegrees", "Infinity"),
        ):
            with self.subTest(field=field, invalid=invalid):
                original = camera[field]
                camera[field] = invalid
                self.assertFalse(self.valid())
                camera[field] = original
        for field in list(camera):
            with self.subTest(missing=field):
                original = camera.pop(field)
                self.assertFalse(self.valid())
                camera[field] = original
        self.composition["cameraFraming"] = []
        self.assertFalse(self.valid())

    def test_optional_moon_illumination_bounds_and_legacy_absence(self):
        self.archive["schemaVersion"] = 2
        self.plan.update(target="composition", composition=self.composition)
        constraints = {"maximumErrorDegrees": 3, "altitudeRange": {"lowerBound": 0, "upperBound": 15}}
        self.composition["constraints"] = constraints
        self.assertTrue(self.valid())
        for bounds in (None, {"lowerBound": 0, "upperBound": 1}, {"lowerBound": 0.9, "upperBound": 1}):
            with self.subTest(bounds=bounds):
                constraints["moonIlluminationRange"] = bounds
                self.assertTrue(self.valid())
        for invalid in (
            {}, [0, 1], {"lowerBound": 0},
            {"lowerBound": -0.01, "upperBound": 1},
            {"lowerBound": 0, "upperBound": 1.01},
            {"lowerBound": "0", "upperBound": 1},
        ):
            with self.subTest(invalid=invalid):
                constraints["moonIlluminationRange"] = invalid
                self.assertFalse(self.valid())

    def test_collection_and_completion_optional_in_v1_and_v2(self):
        for version in (1, 2):
            with self.subTest(version=version):
                self.archive["schemaVersion"] = version
                self.plan.pop("collectionName", None)
                self.plan.pop("completedAt", None)
                self.assertTrue(self.valid())
                self.plan.update(collectionName=None, completedAt=None)
                self.assertTrue(self.valid())
                self.plan.update(collectionName="City light trip", completedAt="2026-09-22T14:30:00+08:00")
                self.assertTrue(self.valid())
                self.plan["collectionName"] = "a" * 60
                self.assertTrue(self.valid())

    def test_invalid_collection_and_completion_fields(self):
        self.archive["schemaVersion"] = 2
        for collection in ("a" * 61, 1, ["trip"]):
            with self.subTest(collection=collection):
                self.plan["collectionName"] = collection
                self.assertFalse(self.valid())
        self.plan["collectionName"] = "Valid trip"
        for instant in ("2026-09-22", "2026-09-22T15:00:00", "not-a-date", 1789650000):
            with self.subTest(instant=instant):
                self.plan["completedAt"] = instant
                self.assertFalse(self.valid())


if __name__ == "__main__":
    unittest.main()
