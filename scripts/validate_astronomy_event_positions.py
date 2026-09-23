#!/usr/bin/env python3
"""Re-run the existing 396 position coordinates against the independent oracle."""
from pathlib import Path
import argparse, datetime as dt, json, math, subprocess
import swisseph as swe
ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swift-executable', type=Path, required=True)
    args = parser.parse_args()
    if swe.version != '2.10.03':
        parser.error('Expected Swiss Ephemeris 2.10.03; review a reference-version change explicitly.')
    original = json.loads((ROOT / 'packages/LightPlanCore/Tests/LightPlanCoreTests/Fixtures/positions.json').read_text())
    inputs = [{key: row[key] for key in ['body', 'timestamp', 'latitude', 'longitude']} for row in original]
    actual = json.loads(subprocess.run([str(args.swift_executable.resolve()), 'positions'], input=json.dumps(inputs), capture_output=True, text=True, check=True).stdout)
    errors = {'sun': [], 'moon': []}
    for row, value in zip(inputs, actual, strict=True):
        jd = row['timestamp'] / 86400 + 2440587.5
        swe.set_topo(row['longitude'], row['latitude'], 0)
        eq, _ = swe.calc_ut(jd, swe.SUN if row['body'] == 'sun' else swe.MOON, swe.FLG_MOSEPH | swe.FLG_EQUATORIAL | swe.FLG_TOPOCTR)
        az, alt, _ = swe.azalt(jd, swe.EQU2HOR, (row['longitude'], row['latitude'], 0), 1013.25, 15, eq[:3])
        r = math.pi / 180
        cosine = math.sin(value['altitude'] * r) * math.sin(alt * r) + math.cos(value['altitude'] * r) * math.cos(alt * r) * math.cos((value['azimuth'] - (az + 180) % 360) * r)
        separation = math.acos(min(1, max(-1, cosine))) / r
        errors[row['body']].append({**row, 'angularSeparationDegrees': separation})
    result = {'generatedAtUTC': dt.datetime.now(dt.timezone.utc).isoformat(), 'reference': 'Swiss Ephemeris 2.10.03 Moshier, topocentric, unrefracted sea-level positions',
              'source': 'https://www.astro.com/swisseph/swephprg.htm', 'count': len(inputs), 'bodyResults': {}, 'samples': errors}
    for body, rows in errors.items():
        limit = 0.08 if body == 'sun' else 0.30
        values = [row['angularSeparationDegrees'] for row in rows]
        result['bodyResults'][body] = {'count': len(rows), 'maxAngularErrorDegrees': max(values), 'meanAngularErrorDegrees': sum(values) / len(values), 'limitDegrees': limit, 'passed': all(value <= limit for value in values)}
    result['passed'] = all(row['passed'] for row in result['bodyResults'].values())
    (ROOT / 'tests/reports/astronomy-events-2026-09-22-positions.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key != 'samples'}, indent=2))
    return 0 if result['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
