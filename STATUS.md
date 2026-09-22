# Current local preview status — 2026-09-22

**Signed iPhone preview built and installed: LightPlan 1.0.0 (1).**

- Xcode 27.0: signed Debug app + widget build passed; unsigned Release build passed.
- Connected iPhone 17 Pro: installation confirmed by an independent
  device app listing. Initial automatic launch was blocked by the phone being locked.
- Core tests: 83 passed, zero failures. Nine-language catalog and metadata audits passed.
- Initial full native suite: six tests passed with 29 screenshots. After the map
  repair, the final five-test regression passed: four purchase/place/plan flows plus
  portrait/landscape time continuity and all three map buttons remaining hittable.
  Current map screenshots and xcresult are local-only in the ignored directory
  `tests/reports/v3/native-20260922-final/`; they are not published artifacts.
- Local signing uses ignored `ios/Config/Local.xcconfig`, derived from the existing
  LightPlan development profile. App and widget share the expected App Group.
- Added `scripts/run_iphone.sh` for repeatable signing, installation and launch
  without attaching a debugger. The original ordering-only Info.plist edit was
  backed up locally, then normalized to match the project generator.
- Initial source compiled without compiler repairs. Native screenshot review then
  found clipped landscape map controls and overlapping event/celestial labels.
  The map now uses a scrolling side panel in short landscape windows and separates
  event badges from the current celestial marker. Visual assets remain unchanged.

Current evidence and limitations: [iPhone preview report](tests/reports/2026-09-22/README.md).
Raw logs and device/signing identifiers are retained only in ignored local evidence;
the public report contains sanitized summaries and command templates.
Commit preparation re-ran the generator consistency check, 83 core tests, both
audits and unsigned Debug/Release builds successfully. App and UI-test sources
still match the final verified hashes, so the five-test UI result above remains
applicable; UI tests were not rerun for report cleanup. No commit or push was made
during verification.
This does not complete App Store release acceptance. Historical CI results below
remain tied to their original source/toolchain and are not new device evidence.

# Historical release status — 2026-09-21

**Native CI candidate; not yet authorized for App Store submission.** This file records executed evidence, not a promise of App Review approval.

## Executed and passed

- Foundation core: 83 XCTest cases pass, 0 failures.
- String Catalog: 239 keys × 9 languages = 2,151 localized values; automated audit reports no missing referenced keys.
- Native Debug simulator build: **BUILD SUCCEEDED** with Xcode 26.3 / iOS 26.2 SDK.
- Unsigned Release archive: **ARCHIVE SUCCEEDED**.
- iPhone 17 Pro native UI suite: 6 tests pass, 0 failures.
  - Manual coordinate location flow works without granting device location permission.
  - Paywall dismissal does not unlock premium.
  - StoreKit test purchase resumes the plan editor and saves.
  - Signed local StoreKit non-consumable survives relaunch and refund revokes the entitlement.
  - All core screens render in all nine languages.
  - Dark-mode map state survives portrait/landscape rotation.
- Native screenshot evidence: 27 light-mode iPhone screenshots (Today / Map / Plan × 9 languages) plus 2 dark-mode map screenshots.
- iPad Pro 11-inch (M4) native rotation suite: passed with portrait and landscape screenshot evidence.
- GitHub Actions native verification run **35624640157** passed on commit `8d98c8cbdcb6f721d923d2c2c67726453ddebe49`.
- Representative native screenshots were visually reviewed after the run; no obvious clipping/overflow was found in the nine-language core-screen contact review.

## Implemented

Photographic v3 SwiftUI views/assets; real MapKit imagery and solar/lunar tracks; interactive timelines; date/location workflows; favorites; create/edit/duplicate/delete plans; reminders and notification deep links; validated backup import/export and conflict handling; StoreKit 2 one-time unlock/restore/refund handling; widgets/App Group; nine languages; light/dark appearance; dynamic/adaptive layouts.

## Remaining release gates

- Physical iPhone/iPad verification: real location/heading behavior, map alignment, notification delivery, app-group widget refresh, cold launch and background/foreground behavior.
- App Store Connect sandbox purchase/restore/refund checks with the real product identifier. Local StoreKit tests do not substitute for Apple sandbox.
- Apple Developer identifiers/App Group, signing team and provisioning must be registered/authorized by the owner.
- App Store Connect product, price, Paid Apps agreement/tax/banking state, privacy answers, age rating, support/privacy URLs and final metadata require owner-account configuration.
- Final performance/battery/accessibility spot checks on physical devices.
- Actual Duo fold/unfold verification remains pending real device/SDK availability; responsive iPad coverage does not substitute for fold hardware.

The product scope remains the complete approved first release. Do not remove a release gate or invent evidence merely to call the app “100%.”
