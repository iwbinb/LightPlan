# M5 run 65: cold-launch readiness polling repair — 2026-09-26

## Evidence and diagnosis

- User-reported run: [native #65](https://github.com/iwbinb/LightPlan/actions/runs/36212617007), source `497d904e3fe4336a03add86807dde5d517dceccd`, product job `108322171199`.
- Downloaded the complete product evidence ZIP, artifact `10896727695`, and verified SHA-256 `3292f5b54ab824aa76e405de18c7512f2de11cddb1122e3f534a0970d5420c12`. Read `native-tests.log`, `test-summary.json`, the exported hierarchy and screenshot; preserved the original bundle.
- Product results: 9 passed, 1 failed, 0 skipped; exit 65, neither stage timeout nor interruption. The failed method was `testCompositionFiltersAndUsesSelectedOpportunity`, at the newly added readiness assertion on line 148. No composition tap or astronomical search was attempted by that method.
- On the cold launch, the readiness predicate began at test elapsed 20.99s; its first cycle used approximately 6.95s making repeated live element/property/tab-bar queries. A second cycle began at 27.94s but the same 10s waiter expired while queries were still resolving. The final screenshot and hierarchy show the entry onscreen: x=272.5, y=624.7, width=44, height=44.3 in a 402x874 window, above the tab bar at y=791.
- The corner-hit test later passed on the same runner. Separately queried PR run #66 reports all eleven jobs successful for the same implementation. That result does not erase run #65: the new readiness helper itself is sensitive to cold-runner query cost. The trace does not prove the exact lower-level cause of the earlier run-62 missed tap.

## Targeted repair

Only `ProductUITests.swift` changes executable source. Production App/Core/Widget, numerical models, precision, data schema, signing and pricing are unchanged.

- Read entry identity, enabled state, window and tab-bar geometry from one public `XCUIElementSnapshot` per poll. Do not repeatedly resolve index-bound tab-bar elements or mix geometry from different live snapshots.
- Still require foreground state, exactly one entry/window, valid onscreen bounds, a resolved tab bar, unchanged geometry for at least 0.3 seconds, and a live `isHittable` check. The original 10-second readiness timeout is unchanged. Recheck enabled/hittable before returning the entry.
- The original method still taps once and must expose both selected state and the actual composition panel, then pass every original low-sky/All, result-time, editor-time and suggested-observer assertion. The separate edge-hit regression remains unchanged. No retries of the tap, injected UI state, skips, test-side queue clearing or enlarged timeouts.
- Retain a bounded per-poll timing/reason trace on success and failure, in addition to the existing failure screenshot/hierarchy.
- Add one pure helper regression for settling, changed geometry, missing/ambiguous samples, disabled controls, clipping, tab-bar overlap, invalid bounds and non-monotonic time. This is a test-logic regression, not another UI scenario. Product inventory is now eleven methods: ten actual UI scenarios plus this helper check.

Public API references: [snapshot()](https://developer.apple.com/documentation/xcuiautomation/xcuielementsnapshotproviding/snapshot()), [XCUIElementSnapshot](https://developer.apple.com/documentation/xcuiautomation/xcuielementsnapshot), [isHittable](https://developer.apple.com/documentation/xcuiautomation/xcuielement/ishittable). A captured snapshot is not a substitute for the live hit test.

## Local checks

Isolated Linux x86_64 / Swift 6.2.1; the original ProductUITests blob was checked against `c83e22dff7da5cf05827ac62e4294ab4960ad6ea` before editing. Reviewed replacement blob: `378f0f1f10d502d4ccfecc87422a7e9e229d2546`.

- `swift test --package-path packages/LightPlanCore`: 280 passed, 0 failures, exit 0; completed 2026-09-26 04:24:17 UTC. No core source changes. An earlier local invocation was interrupted by a one-second command window and is not counted as test evidence.
- Extracted the exact pure helper and its regression into a standalone XCTest executable: 1 passed, 0 failures, exit 0. This does not typecheck XCUIAutomation.
- `python3 scripts/ci_baseline_tests.py`: 36 passed, exit 0.
- `python3 scripts/ci_baseline.py select . iphone-product`: eleven assigned methods, including all ten existing methods; exit 0.
- `swiftc -frontend -parse ios/LightPlanVisualUITests/ProductUITests.swift` and `git diff --check`: exit 0. Parsing is not Apple-platform typechecking.

## Native acceptance remains required

The repair must be checked on its own committed source. Existing CI will build and run the product shard and full native regression; PR merge-reference checks remain separate. Neither the previous PR pass nor local checks mark this new helper or all M5 acceptance complete. Retain run #65 failure evidence. Do not merge main or start M6 in this repair.

Reproduce on a Mac with the repository's Xcode toolchain:

```sh
bash scripts/ci_native.sh iphone-product
bash scripts/ci_native.sh all
```

True device startup/frame/energy metrics, VoiceOver, minimum OS, file providers, signing and App Store acceptance remain separate gates.
