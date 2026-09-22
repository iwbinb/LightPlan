# LightPlan iPhone preview verification — 2026-09-22

This sanitized report describes local verification of the working tree based on
`3bd7035`. It is not a GitHub CI result or App Store release approval.

## Changes

- Short landscape map windows use a scrolling sidebar for controls. The existing
  Map instance and selected time remain shared across layouts.
- Rise/set badges sit above their endpoints; the current celestial marker sits
  below, keeping the event time readable.
- The rotation test starts in portrait and checks that all three map buttons are
  hittable in landscape.
- `scripts/run_iphone.sh` builds, verifies signing, installs and launches on an
  explicitly selected iPhone without attaching a debugger.
- The pre-existing Info.plist edit was ordering-only. Its original bytes were
  preserved locally before restoring the generator's canonical ordering; no
  configuration values changed.

## Executed evidence

| Check | Result | Boundary |
| --- | --- | --- |
| Core XCTest suite | 83 passed, zero failures | Foundation core |
| Localization | 239 keys, 2,151 values, nine languages | Automated completeness, not native-speaker review |
| Metadata length audit | Passed for nine locales | Does not certify final store metadata |
| Initial native UI suite | Six passed; 29 screenshots | Before the map layout repair |
| Final native regression | Five passed, zero failures | Four purchase/place/plan flows and strengthened map rotation test |
| Final-source Debug and Release builds | Passed | Debug signed; Release unsigned |
| Physical iPhone installation | Version 1.0.0 (1) installed | Launch attempts were blocked by the locked phone |

The native UI tests ran on an iPhone 18 Pro simulator with iOS 27.0. The physical
installation used an iPhone 17 Pro. Local StoreKit transactions do not substitute
for App Store Connect sandbox purchases, restore or refunds.

Commit preparation re-ran project generation and its tracked-file consistency
check, the 83 core tests, both audits, and unsigned Debug/Release builds; all
passed. Application and UI-test source hashes still match the final verified
manifest. UI tests were not rerun for report cleanup and equivalent plist ordering.

The first map regression failed while locating the sidebar container by its
accessibility identifier; diagnostic collection then stalled and was interrupted.
The test was changed to assert the user-facing requirement directly: all three
buttons exist and are hittable. The later regression passed. Both the failed and
successful raw records remain preserved locally.

## Native screenshot review

Codex inspected native simulator screenshots, not browser renders. Portrait review
confirmed that sunset time no longer overlaps the Sun icon and attribution stays
visible. Landscape review confirmed visible map controls in the sidebar and the
selected time surviving rotation. This is targeted map review, not full device or
accessibility acceptance. The initial nine-language captures were not regenerated
after this map change; unchanged home and plan views retain baseline evidence only.

Screenshots and xcresult bundles are **local-only** in the ignored directories
`tests/reports/v3/native-20260922/` and
`tests/reports/v3/native-20260922-final/`. They are intentionally not linked as
GitHub-accessible files. A future run of the [native CI workflow](../../../.github/workflows/ci.yml)
can produce a downloadable `native-evidence-<commit>` Actions artifact; no CI run
for the locally verified changes is claimed here.

## Public and private evidence

- [Verification summary](verification.json): result boundaries and commit-readiness checks.
- [Sanitized command templates](commands.json): actual exit codes; device identifiers
  and local build paths replaced with variables.
- [Initial source hashes](source-sha256.json) and [final source hashes](source-sha256-final.json):
  the scoped Swift, catalog and project files covered by those runs.
- [Toolchain](toolchain.txt), [localization](localization.json) and [metadata](metadata.txt):
  small reports safe to include in source control.

Original logs, commands and the earlier report were copied with matching SHA-256
hashes to ignored `tests/reports/local/2026-09-22/`. Failures were preserved. Raw
records may contain developer identity, device IDs and local paths and must remain
local. The dated public report directory uses an explicit Git allowlist so new
raw logs are not accidentally included. Local signing stays in ignored
`ios/Config/Local.xcconfig`; never force-add it or the raw evidence directories.

Still pending separately: physical launch/use, notification delivery, real Widget
refresh, actual App Store sandbox, older-system/small-screen/large-type layout
coverage, native-language review, performance and release acceptance. No purchase
bypass was added. Verification itself did not commit, push, upload or submit the app.
