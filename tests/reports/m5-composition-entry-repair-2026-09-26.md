# M5 composition-entry repair candidate — 2026-09-26

## Observed failure, not an inferred search defect

Source `aa492b75f57abf2f6b230ddcab0479ddec17bc13`, native run 62 (`36208519163`), job `108310403770`: ProductUITests executed 9 cases, 8 passed and 1 failed, no skips. The failed case was `testCompositionFiltersAndUsesSelectedOpportunity`. The command returned 65 without timeout or interruption.

The complete failure ZIP `10895401583` was downloaded and its SHA-256 verified as `cfb72dd12bcb5dd4db1ab0cae5519a60b5f7cd1ea80965fa2f6db0ca20a336b2`. `native-tests.log` locates the failure at ProductUITests.swift:104, waiting for `composition-search` inside `revealComposition`, before any search or filter selection. The initial native `map-composition` tap did not expose the composition panel. The preserved hierarchy shows the ordinary map and no composition-card; the recorded touch is at the visible button's center. This does not establish a numerical defect, nor does one recording prove the precise lower-level reason that this tap was missed.

## Narrow hardening and regression coverage

- Make the compact composition button's entire existing 44pt frame the explicit interaction shape, with a plain button style. Preserve its icon, circular background and normal layout.
- Expose composition mode as the selected accessibility trait on both compact and wide entry buttons. No test-only production state injection is added.
- In the original failing test, select portrait and wait for the real control to be foreground, enabled, hittable, fully within the visible screen above the tab bar, and geometrically stable before one tap. Verify both selected state and the actual composition panel before continuing.
- Add `testMapCompositionEntryAcceptsFullHitTarget`: tap once near the corner inside the 44pt target but outside the glyph/circle, require the real panel and selected state, and verify that entering composition does not change the map time.
- Retain every original low-sky/All filtering, selected-result, editor-time, unique accessibility text and suggested-position assertion. Product stage now selects 10 cases. No timeout increase, repeat-tap fallback, skipped test, notification clearing, result fixture substitution or precision change.
- Add a screenshot and accessibility-hierarchy attachment when the entry is not ready or does not open. These diagnose the exact entry failure rather than reporting it only as a later missing search button.

## Verification of this candidate

The isolated Linux source was reconstructed to the exact live Git tree `4b48841eb12d901eceaffc58c45500ca178cbd03` before editing. The archived source TAR SHA-256 was verified (`9a5e52220cfdd6b5a0ff34d8f08f0881c101abbdc474daf1f08a37e8593e74bd`). It is not the owner's Mac worktree.

- `swift test --package-path packages/LightPlanCore`: 280 passed, 0 failures; exit 0 (Swift 6.2.1, Linux x86_64).
- `python3 scripts/ci_baseline_tests.py`: 36 passed, exit 0.
- `swiftc -frontend -parse ios/LightPlan/MapView.swift ios/LightPlanVisualUITests/ProductUITests.swift`: exit 0. Parsing is not Apple SDK type checking.
- `git diff --check`: exit 0. CI selection retains the original nine Product methods and adds one.

Apple build and native regression on this repair are **pending**, not passed by these local checks. Run 62 remains a failed historical run. PR #6 must remain Draft until final-source native results and remaining M5 evidence are checked. No main merge, M6 work, schema, astronomical model, pricing, signing or release change is included. The temporary object-transport workflow is removed from the repair tree.
