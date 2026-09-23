# Independent astronomy event validation — 2026-09-22

Result: **PASS**. 31/31 destination civil days satisfy all existing timing and event-count requirements.

The reference uses Swiss Ephemeris's independent event solver; app altitude residuals are not used as expected results. [Reference API](https://www.astro.com/swisseph/swephprg.htm).

| Body | Matched events | Maximum absolute time error | Event-kind failures | Count mismatches |
|---|---:|---:|---:|---:|
| sun | 305 | 14.562 s | 0 | 0 |
| moon | 43 | 22.625 s | 0 | 0 |

The fixed pre-existing tolerances are 60 seconds for solar events and 120 seconds for lunar events. No high-latitude exception is applied.

## Failed comparisons

None in this final sample. The baseline failure remains in `astronomy-events-2026-09-22-baseline.json`.

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

Solar/lunar positional agreement alone cannot clear this event gate. Passing this finite sample does not establish a global guarantee, and does not clear unrelated release gates.

## Production fix and cost

The initial low-order solar model missed the two near-tangent Arctic events and differed by 164.265 seconds at the 89°N sunset. Tightening the root solver did not address its solar-coordinate error. The production model now uses VSOP87D, FK5 corrections, aberration, IAU 1980 nutation, and a documented TT−UT prediction.

The coefficients/transforms come from MIT-licensed [astronomia, pinned source](https://github.com/commenthol/astronomia/tree/71e16c942b143a1a5a067b6aab2d8532064704ae); full permission text is in `licenses/astronomia-MIT.txt`. The [NASA TT−UT polynomial](https://eclipse.gsfc.nasa.gov/SEcat5/deltatpoly.html) predicts future Earth rotation and does not establish measured future timing. The Swiss reference remains QA-only.

The unabridged coefficient experiment also passed and is preserved as `astronomy-events-2026-09-22-full-vsop.json`. Production retains 470 VSOP terms and 63 nutation terms. Terms were removed only while the sum of their maximum absolute contributions over `|tau| ≤ 0.102` stayed below `1e-6` radians per angular coordinate and `1e-6` AU for distance. This bounds simplification relative to that full table; it does not bound total astronomical error.

A fresh independent comparison at the original 396 position inputs passed: Sun maximum angular separation 0.000877982°, Moon 0.062524153°, with the existing 0.08°/0.30° limits unchanged. See `astronomy-events-2026-09-22-positions.json`.

The full Swift core suite passed 139 tests, including a new test over all 31 frozen independent event cases. On this arm64 Mac, 50 optimized CLI process launches (startup, full day, output, exit) had P95 14.27 ms and maximum 14.44 ms. See `astronomy-events-2026-09-22-performance.json`; this is not an iPhone performance or energy result.
