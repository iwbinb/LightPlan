# Independent astronomy event validation — 2026-09-22

Result: **FAIL**. 29/31 destination civil days satisfy all existing timing and event-count requirements.

The reference uses Swiss Ephemeris's independent event solver; app altitude residuals are not used as expected results. [Reference API](https://www.astro.com/swisseph/swephprg.htm).

| Body | Matched events | Maximum absolute time error | Event-kind failures | Count mismatches |
|---|---:|---:|---:|---:|
| sun | 303 | 164.265 s | 3 | 2 |
| moon | 43 | 22.625 s | 0 | 0 |

The fixed pre-existing tolerances are 60 seconds for solar events and 120 seconds for lunar events. No high-latitude exception is applied.

## Failed comparisons

- **arctic-near-tangent**, 2026-12-21, (67.398, 13.8875), UTC: sunrise, sunset.
  - sunrise: reference ['2026-12-21T11:01:04.128613Z']; app []; signed errors [] seconds.
  - sunset: reference ['2026-12-21T11:03:54.561727Z']; app []; signed errors [] seconds.
- **north-89-equinox**, 2026-03-20, (89, 0), UTC: sunset.
  - sunset: reference ['2026-03-20T23:11:47.735020Z']; app ['2026-03-20T23:14:32.000000Z']; signed errors [164.265] seconds.

## Scope and reproducibility

31 fixed cases cover 23/25-hour DST days, Lord Howe's 23.5/24.5-hour days, quarter-hour zones, the international date line, both supported-year endpoints, polar day/night, and near-tangent cases. The fixture contains the independent expected times for all cases, including failures.

```sh
python3 -m venv /tmp/lightplan-astronomy-oracle
/tmp/lightplan-astronomy-oracle/bin/python -m pip install pyswisseph==2.10.3.2
swift build --package-path packages/LightPlanCore --scratch-path /tmp/lightplan-astronomy-events-build --product lightplan-cli
/tmp/lightplan-astronomy-oracle/bin/python scripts/validate_astronomy_events.py --swift-executable /tmp/lightplan-astronomy-events-build/debug/lightplan-cli
```

Exit status 0 means every comparison passed; 1 preserves a measured failure; missing reference/build prerequisites are errors, not passes. JSON records source and CLI hashes, software versions, all event comparisons, definitions and limits.

## Model and limitations

- Finite independent samples do not establish a global 1900-2100 accuracy bound.
- Near-tangent geometry amplifies small positional or disk-radius differences and can change event existence.
- No terrain, building obstruction, observer elevation, real atmospheric refraction or physical field observation is validated.
- Swift CLI emits whole-second ISO timestamps, adding under one second of comparison quantization.
- The reference library is installed only in a local temporary environment; no reference source or binary is shipped in the app.

Solar/monthly positional agreement alone cannot clear this event gate. A release claim must also account for the failed grazing-event timing/count comparisons above.
