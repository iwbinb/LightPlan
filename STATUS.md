# Release status — 2026-09-21

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
