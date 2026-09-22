# LightPlan / 光迹

Native sunlight and photography planning for iPhone and iPad. Original native app source; no WebView or backend. Development branch: `dev`.

## Open and run

```sh
git clone --branch dev https://github.com/iwbinb/LightPlan.git
cd LightPlan
open LightPlan.xcodeproj
```

Choose the **LightPlan** scheme. In **Signing & Capabilities**, select your Apple Developer team for **LightPlan** and **LightPlanWidget**. Select a connected, trusted iPhone with Developer Mode and Run. Xcode resolves the local `LightPlanCore` package; no CocoaPods, XcodeGen, art copying, Python, or generation step is required on your Mac. Build with Xcode 26+ (CI uses 26.3); iOS 17+ deployment target.

The candidate bundle, group and product IDs are centralized in `ios/Config/Project.xcconfig`. They are not a claim of Apple registration. The owner must register/approve the identifiers and group. Optional local overrides belong in the ignored `ios/Config/Local.xcconfig`. Never commit certificates, private keys or Apple credentials.

For a local iPhone preview without attaching the debugger, set `DEVELOPMENT_TEAM` in
`ios/Config/Local.xcconfig`, connect and unlock your trusted iPhone, then run:

```sh
xcrun devicectl list devices
bash scripts/run_iphone.sh 'Your iPhone name'
```

This builds and signs both the app and widget, installs the app, and opens it.
It preserves existing app data. The normal preview uses real StoreKit configuration;
purchase-gated features need a configured product and verified purchase. Automated
local StoreKit tests are separate and do not charge money.

## Product

- Photographic native dashboard, real solar curve, real MapKit imagery and interactive light tracks, expanded map/inspector workspace.
- Sun and Moon positions/rise/set; golden, blue and twilight events; destination time zones and DST; polar days and missing events.
- Two-point composition planning: tap a photographic subject on the map, compare Sun/Moon alignment, jump to the best same-day time, search the next 14 days, and calculate geometric shooting-position suggestions.
- Search, manual coordinates with explicit IANA time zone, opt-in location, favorites.
- Create/edit/duplicate/delete shooting plans, arrival/reminder offsets, local reminders and notification deep links.
- Validated JSON backup export/import, conflict review, atomic persistence and preservation of damaged originals.
- One-time StoreKit 2 non-consumable; signed entitlement verification, pending/cancel/failure/refund/relaunch handling, restore. No subscription, ads or account.
- Nine languages: English, 简体中文, 繁體中文, 日本語, 한국어, Deutsch, Français, ไทย, Português (Portugal).
- Small/medium widgets, light/dark appearance, dynamic type, reduced motion/transparency, true-north map geometry.

Solar thresholds are documented conventions, not guarantees of visible sunshine or good photographs. Map/search/geocoding/purchasing may require a connection. Celestial calculations and saved plans do not. Artwork is illustrative and does not impersonate the selected destination's live conditions.

## Development and evidence

See `STATUS.md` for executed vs pending acceptance, `docs/RELEASE.md` for owner-side release steps, and `docs/v3` for the approved visual contract. `docs/01_产品规格.md` and related numbered files preserve the original brief; their historical implementation status is superseded by `STATUS.md`.

```sh
swift test --package-path packages/LightPlanCore
python3 scripts/localization_audit.py
# On a Mac with the CI toolchain and simulators:
bash scripts/ci_native.sh
```

The generated `.xcodeproj`, all JPEGs/PNG and resources are checked in. Maintainers may regenerate the deterministic project with `scripts/generate_project.py`; users should not need to. Keep business logic in the Foundation package and framework adapters in `ios/LightPlan`.

`ios/StoreKit/LightPlan.storekit` is a **local testing configuration**. The default Run/Archive scheme does not attach it. XCTest uses it explicitly. It is not a configured App Store Connect product or real payment. Actual product setup and sandbox acceptance are separate release gates.

No release is labeled App Store-ready until native builds, tests, visual/device QA, production identifiers, product configuration, legal/support URLs and owner submission checks have evidence. iPad/rotation coverage is not physical Duo folding evidence.
