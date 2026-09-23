#!/usr/bin/env python3
"""Independent event QA; Swiss Ephemeris remains an optional local reference only.

Build the current Swift CLI first, then supply its path. This script preserves every
comparison, including failures. It does not modify the application's astronomy code.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
import platform
from pathlib import Path
import subprocess
import sys
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
CASES = [
    ("gulangyu-autumn", 24.4478, 118.0679, "Asia/Shanghai", "2026-09-22"),
    ("new-york-dst-short", 40.7128, -74.006, "America/New_York", "2026-03-08"),
    ("new-york-dst-long", 40.7128, -74.006, "America/New_York", "2026-11-01"),
    ("berlin-dst-short", 52.52, 13.405, "Europe/Berlin", "2026-03-29"),
    ("berlin-dst-long", 52.52, 13.405, "Europe/Berlin", "2026-10-25"),
    ("lord-howe-dst-long", -31.55, 159.08, "Australia/Lord_Howe", "2026-04-05"),
    ("lord-howe-dst-short", -31.55, 159.08, "Australia/Lord_Howe", "2026-10-04"),
    ("chatham-dst-short", -43.95, -176.56, "Pacific/Chatham", "2026-09-27"),
    ("kathmandu-quarter-hour", 27.7172, 85.324, "Asia/Kathmandu", "2026-09-22"),
    ("kiritimati-dateline", 1.87, -157.43, "Pacific/Kiritimati", "2026-09-22"),
    ("kiritimati-minimum-year", 1.87, -157.43, "Pacific/Kiritimati", "1900-01-01"),
    ("kiritimati-maximum-year", 1.87, -157.43, "Pacific/Kiritimati", "2100-12-31"),
    ("pago-pago-minimum-year", -14.2756, -170.702, "Pacific/Pago_Pago", "1900-01-01"),
    ("pago-pago-maximum-year", -14.2756, -170.702, "Pacific/Pago_Pago", "2100-12-31"),
    ("tromso-polar-day", 69.6492, 18.9553, "Europe/Oslo", "2026-06-21"),
    ("tromso-polar-night", 69.6492, 18.9553, "Europe/Oslo", "2026-12-21"),
    ("tromso-equinox", 69.6492, 18.9553, "Europe/Oslo", "2026-03-20"),
    ("arctic-before-tangent", 67.396, 13.8875, "UTC", "2026-12-21"),
    ("arctic-near-tangent", 67.398, 13.8875, "UTC", "2026-12-21"),
    ("arctic-after-tangent", 67.4, 13.8875, "UTC", "2026-12-21"),
    ("equator-equinox", 0, 0, "UTC", "2026-03-20"),
    ("north-89-equinox", 89, 0, "UTC", "2026-03-20"),
    ("south-89-equinox", -89, 0, "UTC", "2026-09-23"),
    ("longyearbyen-winter", 78.2232, 15.6469, "Arctic/Longyearbyen", "2026-02-15"),
    ("longyearbyen-spring", 78.2232, 15.6469, "Arctic/Longyearbyen", "2026-04-15"),
    ("longyearbyen-autumn", 78.2232, 15.6469, "Arctic/Longyearbyen", "2026-10-15"),
    ("antarctic-summer", -77.85, 166.67, "Antarctica/McMurdo", "2026-12-21"),
    ("sydney-summer", -33.8688, 151.2093, "Australia/Sydney", "2026-12-21"),
    ("tokyo-leap-day", 35.6762, 139.6503, "Asia/Tokyo", "2024-02-29"),
    ("london-mid-century", 51.5074, -0.1278, "Europe/London", "1950-01-15"),
    ("lisbon-future", 38.7223, -9.1393, "Europe/Lisbon", "2050-04-15"),
]
SOLAR_THRESHOLDS = [
    (-18, "astronomicalDawn", "astronomicalDusk"),
    (-12, "nauticalDawn", "nauticalDusk"),
    (-6, "blueMorningStart", "blueEveningEnd"),
    (-4, "goldenMorningStart", "goldenEveningEnd"),
    (6, "goldenMorningEnd", "goldenEveningStart"),
]

def iso(timestamp: float) -> str:
    return dt.datetime.fromtimestamp(timestamp, dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")

def timestamp(text: str) -> float:
    return dt.datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()

def reference_events(swe, start: float, end: float, body: int, latitude: float,
                     longitude: float, rising: bool, horizon: float, center: bool) -> list[float]:
    flags = (swe.CALC_RISE if rising else swe.CALC_SET) | swe.BIT_NO_REFRACTION
    if center:
        flags |= swe.BIT_DISC_CENTER
    cursor = start / 86400 + 2440587.5 - 0.1 / 86400
    values = []
    for _ in range(4):
        status, times = swe.rise_trans_true_hor(cursor, body, flags, (longitude, latitude, 0),
                                              1013.25, 15, horizon, swe.FLG_MOSEPH)
        if status == -2:
            break
        if status != 0:
            raise RuntimeError(f"Independent oracle returned {status}")
        instant = (times[0] - 2440587.5) * 86400
        if instant >= end:
            break
        if instant >= start:
            values.append(instant)
        cursor = times[0] + 1 / 86400
    else:
        raise RuntimeError("Unexpectedly many events in one civil day")
    return values

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swift-executable", type=Path, required=True)
    parser.add_argument("--report-prefix", default="tests/reports/astronomy-events-2026-09-22")
    parser.add_argument("--fixture", default="packages/LightPlanCore/Tests/LightPlanCoreTests/Fixtures/astronomy-events.json")
    args = parser.parse_args()
    try:
        import swisseph as swe
    except ImportError:
        parser.exit(2, "Independent reference pyswisseph is unavailable; event QA has NOT passed.\n")
    if swe.version != "2.10.03":
        parser.exit(2, f"Expected frozen Swiss Ephemeris 2.10.03; found {swe.version}. Review reference-version changes explicitly.\n")
    executable = args.swift_executable.resolve(strict=True)
    comparisons, fixtures = [], []
    definitions = [(swe.SUN, "sun", True, -34 / 60, False, "sunrise"),
                   (swe.SUN, "sun", False, -34 / 60, False, "sunset"),
                   (swe.MOON, "moon", True, -34 / 60, False, "moonrise"),
                   (swe.MOON, "moon", False, -34 / 60, False, "moonset")]
    for horizon, rising, setting in SOLAR_THRESHOLDS:
        definitions.extend([(swe.SUN, "sun", True, horizon, True, rising),
                            (swe.SUN, "sun", False, horizon, True, setting)])
    for name, latitude, longitude, zone_id, date in CASES:
        day = dt.datetime.fromisoformat(date).replace(tzinfo=ZoneInfo(zone_id))
        start, end = day.timestamp(), (day + dt.timedelta(days=1)).timestamp()
        native = json.loads(subprocess.run([str(executable), str(latitude), str(longitude), zone_id,
                                           day.replace(hour=12).isoformat()], check=True, capture_output=True, text=True).stdout)
        case = {"name": name, "latitude": latitude, "longitude": longitude, "timeZone": zone_id,
                "civilDate": date, "intervalStart": iso(start), "intervalEnd": iso(end), "durationSeconds": end - start}
        fixture = {**case, "expectedEvents": []}
        rows, failures = [], []
        if abs(timestamp(native["start"]) - start) > 0.1 or abs(timestamp(native["end"]) - end) > 0.1:
            failures.append("destinationCivilDayMismatch")
        for code, body, rising, horizon, center, kind in definitions:
            expected = reference_events(swe, start, end, code, latitude, longitude, rising, horizon, center)
            actual = [timestamp(event["date"]) for event in native["events"] if event["kind"] == kind]
            limit = 60 if body == "sun" else 120
            errors = [value - reference for value, reference in zip(actual, expected)]
            passed = len(actual) == len(expected) and all(abs(error) <= limit for error in errors)
            rows.append({"kind": kind, "body": body, "expectedUTC": list(map(iso, expected)),
                         "actualUTC": list(map(iso, actual)), "signedErrorSeconds": errors,
                         "limitSeconds": limit, "passed": passed})
            fixture["expectedEvents"].extend({"kind": kind, "timestamp": value, "maxErrorSeconds": limit} for value in expected)
            if not passed:
                failures.append(kind)
        fixture["expectedEvents"].sort(key=lambda event: event["timestamp"])
        fixtures.append(fixture)
        comparisons.append({**case, "passed": not failures, "failures": failures, "events": rows})
    body_results = {}
    for body in ["sun", "moon"]:
        rows = [row for case in comparisons for row in case["events"] if row["body"] == body]
        errors = [abs(value) for row in rows for value in row["signedErrorSeconds"]]
        body_results[body] = {"matchedEvents": len(errors), "maxAbsoluteErrorSeconds": max(errors),
                              "meanAbsoluteErrorSeconds": sum(errors) / len(errors),
                              "failedEventKinds": sum(not row["passed"] for row in rows),
                              "eventCountMismatches": sum(len(row["expectedUTC"]) != len(row["actualUTC"]) for row in rows)}
    source_files = ["packages/LightPlanCore/Sources/LightPlanCore/Astronomy.swift",
                    "packages/LightPlanCore/Sources/LightPlanCore/DayEngine.swift",
                    "packages/LightPlanCore/Sources/LightPlanCore/SolarEphemeris.swift",
                    "packages/LightPlanCore/Sources/LightPlanCore/SolarCoefficients.swift",
                    "packages/LightPlanCore/Sources/LightPlanCore/Models.swift",
                    "packages/LightPlanCore/Sources/LightPlanCLI/main.swift"]
    model = {
        "oracle": "Swiss Ephemeris 2.10.03 / Moshier via pyswisseph 2.10.3.2",
        "source": "https://www.astro.com/swisseph/swephprg.htm",
        "referenceFunction": "swe_rise_trans_true_hor (independent event solver)",
        "flags": "FLG_MOSEPH; CALC_RISE or CALC_SET; BIT_NO_REFRACTION; BIT_DISC_CENTER only for twilight/golden thresholds",
        "riseSetConvention": "Topocentric upper limb crossing a geometric horizon at -34/60 degree, sea-level observer. Variable apparent radius comes from the reference ephemeris; this matches the app's fixed 34-arcminute convention without using its position or root solver.",
        "thresholdConvention": "Topocentric unrefracted center crosses -18, -12, -6, -4 or +6 degrees.",
        "timeConvention": "UT input from UTC Unix seconds (no subsecond DUT1 correction); destination civil day from Python zoneinfo, compared with Foundation boundaries.",
        "limits": "Existing docs/09 targets: solar events <=60 seconds; lunar events <=120 seconds. Limits are not relaxed for grazing events.",
    }
    result = {
        "generatedAtUTC": dt.datetime.now(dt.timezone.utc).isoformat(), "passed": all(case["passed"] for case in comparisons),
        "caseCount": len(comparisons), "passedCases": sum(case["passed"] for case in comparisons),
        "pythonVersion": platform.python_version(), "reference": model, "bodyResults": body_results,
        "sourceSHA256": {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in source_files},
        "cliSHA256": hashlib.sha256(executable.read_bytes()).hexdigest(),
        "limitations": ["Finite independent samples do not establish a global 1900-2100 accuracy bound.",
                        "Near-tangent geometry amplifies small positional or disk-radius differences and can change event existence.",
                        "No terrain, building obstruction, observer elevation, real atmospheric refraction or physical field observation is validated.",
                        "Swift CLI emits whole-second ISO timestamps, adding under one second of comparison quantization.",
                        "The reference library is installed only in a local temporary environment; no reference source or binary is shipped in the app."],
        "cases": comparisons,
    }
    fixture_path = ROOT / args.fixture
    fixture_path.write_text(json.dumps({"reference": model, "cases": fixtures}, indent=2) + "\n")
    prefix = ROOT / args.report_prefix
    prefix.with_suffix(".json").write_text(json.dumps(result, indent=2) + "\n")
    lines = ["# Independent astronomy event validation — 2026-09-22", "",
             f"Result: **{'PASS' if result['passed'] else 'FAIL'}**. {result['passedCases']}/{len(comparisons)} destination civil days satisfy all existing timing and event-count requirements.", "",
             "The reference uses Swiss Ephemeris's independent event solver; app altitude residuals are not used as expected results. [Reference API](https://www.astro.com/swisseph/swephprg.htm).", "",
             "| Body | Matched events | Maximum absolute time error | Event-kind failures | Count mismatches |",
             "|---|---:|---:|---:|---:|"]
    for body, values in body_results.items():
        lines.append(f"| {body} | {values['matchedEvents']} | {values['maxAbsoluteErrorSeconds']:.3f} s | {values['failedEventKinds']} | {values['eventCountMismatches']} |")
    lines += ["", "The fixed pre-existing tolerances are 60 seconds for solar events and 120 seconds for lunar events. No high-latitude exception is applied.", "", "## Failed comparisons", ""]
    for case in comparisons:
        if case["passed"]:
            continue
        lines.append(f"- **{case['name']}**, {case['civilDate']}, ({case['latitude']}, {case['longitude']}), {case['timeZone']}: {', '.join(case['failures'])}.")
        for row in case["events"]:
            if not row["passed"]:
                lines.append(f"  - {row['kind']}: reference {row['expectedUTC']}; app {row['actualUTC']}; signed errors {[round(value, 3) for value in row['signedErrorSeconds']]} seconds.")
    lines += ["", "## Scope and reproducibility", "",
              "31 fixed cases cover 23/25-hour DST days, Lord Howe's 23.5/24.5-hour days, quarter-hour zones, the international date line, both supported-year endpoints, polar day/night, and near-tangent cases. The fixture contains the independent expected times for all cases, including failures.", "",
              "```sh", "python3 -m venv /tmp/lightplan-astronomy-oracle", "/tmp/lightplan-astronomy-oracle/bin/python -m pip install pyswisseph==2.10.3.2", "swift build --package-path packages/LightPlanCore --scratch-path /tmp/lightplan-astronomy-events-build --product lightplan-cli", "/tmp/lightplan-astronomy-oracle/bin/python scripts/validate_astronomy_events.py --swift-executable /tmp/lightplan-astronomy-events-build/debug/lightplan-cli", "```", "",
              "Exit status 0 means every comparison passed; 1 preserves a measured failure; missing reference/build prerequisites are errors, not passes. JSON records source and CLI hashes, software versions, all event comparisons, definitions and limits.", "", "## Model and limitations", ""]
    lines += ["- " + value for value in result["limitations"]]
    lines += ["", "Solar/lunar positional agreement alone cannot clear this event gate. Passing this finite sample does not establish a global guarantee, and does not clear unrelated release gates."]
    prefix.with_suffix(".md").write_text("\n".join(lines) + "\n")
    print(json.dumps({"passed": result["passed"], "caseCount": result["caseCount"], "passedCases": result["passedCases"], "bodyResults": body_results}, indent=2))
    return 0 if result["passed"] else 1

if __name__ == "__main__":
    raise SystemExit(main())
