# Release status — 2026-09-21

**Development candidate; not yet authorized for App Store submission.** This file records evidence, not a percentage or a promise of approval.

## Executed locally

- Foundation core: 83 XCTest cases pass on Swift 6.2.1 / Linux; baseline v3's 60 also re-run.
- String Catalog: 239 keys × 9 languages = 2,151 values; no missing referenced keys in automated audit.
- Native Swift source syntax parsed; Xcode project structurally parsed. These are NOT native SDK compilation.
- GitHub macOS toolchain probe succeeded, run 35595137061. Xcode 26.3 and iOS 26.2 simulators are installed. This probe is NOT an app build.

## Implemented, awaiting native execution

Photographic v3 views and assets; MapKit tracks/controls; timelines; date/location workflows; plans and reminders; purchase intent resumption, verification/restore; validated backup merging and corrupt-file retention; widgets; nine languages and accessibility layout.

## Blocking acceptance

- Native Debug build, unsigned Release archive and native tests/screenshots: pending execution.
- StoreKit local integration: tests written, pending execution. Apple sandbox/real-device payment cases remain separate.
- Real-device location, compass/map alignment, notification delivery and app-group widget behavior: pending owner-device verification.
- Full native visual and nine-language review, accessibility and performance measurements: pending.
- Registered identifiers/team, support/legal website, App Store Connect IAP, pricing, agreements, privacy/age-rating metadata and signing: owner confirmation/configuration required.
- Actual Duo fold/unfold test: pending device/SDK availability; responsive iPad tests do not substitute.

The product scope remains the complete approved first release. Do not delete a gate, invent evidence or merge a release merely to call it “100%.”
