# M2 calculation/search reliability — 2026-09-23

**M2 core implementation is complete and the complete Foundation regression passed: 212 tests, zero failures. Debug and unsigned Release checks also passed. Full native UI and release acceptance remain open.**

- Implementation commit: `99326e35cac863e490d417a3d92ecb47f4c7b292` on `dev`. Core run `35843822247`, job `107125023850`, Xcode 26.3 / Apple Swift 6.2.4, passed with preserved logs. This includes all 25 new regressions and the unchanged 187 existing cases.
- Shared extrema sampling retains short windows near either civil-day boundary; invalid steps/nonfinite results fail explicitly; cancellation is checked inside event/root searches. Civil-time and Sun/Moon request-isolation regressions pass. No ephemeris coefficients, precision thresholds, UI, archive schema, pricing or signing changed.
- Native run `35843822133`, checks job `107125573481`, also passed on this implementation: CI/tooling/schema/localization checks, core regression, Debug simulator build, unsigned Release archive and archive fixture check. Evidence artifact `10741769940` was uploaded. UI groups are separate and still pending; unsigned archiving is not distribution signing.
- M1 run `35841204831`: checks and basic iPhone visual passed; product/planning UI failed with exit 65 before the M2 change. Remaining three groups were superseded by the new native run through the existing concurrency policy; their evidence was uploaded. These are not successful tests and the UI issues remain open.
- The owner requested M2 work while M1 UI acceptance was unresolved. No M3 implementation or main merge is included. The next task must triage the outstanding native failures rather than declare the whole app green.

Details and reproducible commands: [M2 evidence](tests/reports/m2-calculation-search-2026-09-23.md), [core execution record](tests/reports/m2-core-verification-2026-09-23.json), and [M1 baseline report](tests/reports/m1-ci-baseline-2026-09-23.md). All earlier evidence below retains its original source and verification scope.

# Current owned MapKit phone fix — 2026-09-23

**The owner confirmed on the physical iPhone that the map now switches between imagery and road tiles and that GPS shows a separate blue location dot.** This fixes the two reported phone behaviors; the complete App Store release remains pending.

- Two earlier SwiftUI/MapKit style fixes passed in the Simulator but failed the owner's phone check. The app now owns its public `MKMapView` and directly sets the real tile provider, while retaining the saved map region, astronomical rays, subject tapping and MapKit attribution.
- After an explicit GPS request, the visible Map uses live CoreLocation coordinates for a blue dot and a separate camera icon for the selected shooting place. Updates stop when leaving the Map.
- Six focused native map/planning regressions passed; a later strict GPS rerun required actual known coordinates and the separate dot. Native screenshots show both tile styles and the aligned blue dot. The signed development Release App/Widget archive passed integrity checks, was installed and restarted on the iPhone, and the owner then verified both outcomes.
- Source is on `dev`; local commit status is verified through Git. Distribution signing, remote CI, broader physical-device checks and owner Store details remain open.

See [the owned MapKit and phone evidence](tests/reports/owned-mapkit-2026-09-23.md). Earlier candidates and failed phone reports below remain historical evidence.

# Historical physical-map feedback candidate — 2026-09-23

**The map-style icon and GPS arrow were corrected from the owner's iPhone screenshot, and the new development build is installed and launched on the paired iPhone. Actual on-phone tap results still need owner confirmation.**

- The icon-only map-style control now recreates the MapKit view when switching tile providers, while preserving the external camera and planning state. The satellite/standard screenshots show actual different tiles and legible event times.
- The map arrow now requests the device's location and updates the shooting place; long press retains the former recenter action. Three map controls are arranged horizontally so they do not cover the sunrise label in the observed phone layout.
- Four focused native simulator flows passed: GPS selection, map-style change and relaunch persistence, portrait/landscape reachability, and long-press recenter. The final Release App/Widget archive passed local signature, App Group, privacy and license checks.
- The final archive at `/private/tmp/LightPlan-map-gps-final.xcarchive` was installed on the physical iPhone 17 Pro; the old LightPlan process was terminated and the app relaunched. Local App Store preflight remains not ready. No commit, push, merge or submission occurred.

See [the physical-map feedback report](tests/reports/map-physical-feedback-2026-09-23.md). Earlier candidate summaries below retain their original source and verification scope.

# Historical location and map-style candidate — 2026-09-23

**The Places location action and a clearly labeled map-style switch are fixed, compiled, tested locally, and installed on the paired iPhone. App Store readiness remains pending.**

- The Places tab now requests system location only after the user taps **Use my location**. A resolved coordinate/time zone becomes the selected map place; manual coordinates remain available after location or geocoding failure.
- The Map tab now shows **Satellite imagery** or **Standard map** on its style button. The actual MapKit imagery/road tiles change, and the selected style survives app relaunch.
- Debug App/Widget build and two focused native simulator flows passed. Screenshots show both real MapKit tile styles with legal attribution and the new Places control. Catalog completeness: 370 keys × nine languages, zero missing values.
- A new development-signed Release App/Widget archive passed signature, privacy, App Group, license and shipping-bundle checks. It was installed and launched on the physical iPhone 17 Pro; actual GPS/map interaction on that phone still needs the owner's visual check.
- Work remains uncommitted on `dev`; no push, merge, website deployment, upload or App Store submission occurred.

See [the location/map-style evidence](tests/reports/location-map-style-2026-09-23.md). The earlier candidate summaries below retain their original evidence scope.

# Current photography-tool candidate — 2026-09-23

**New planning functions are implemented; the signed development Release archive and 187 core tests passed. App Store submission and commercial validation remain pending.**

- Added a 35mm-equivalent lens/framing preview, 1–90-day continuous opportunity windows with Moon-illumination filters, Sun/Moon task templates, project search/groups, completion/reopening and a field countdown.
- Camera settings, project names and completion states persist with compatible backups. Completing a plan cancels its reminder; reopening never silently enables it.
- Large libraries publish readable rows first and calculate missing event times in bounded batches, retaining a bounded day cache. Core Release benchmarks are reported separately from native first-frame/device performance.
- Fixed vertical scrolling that accidentally scrubbed the timeline, stale asynchronous framing results, saved All filtering and refresh cancellation leaving a blank day.
- Core: 187 passed. Catalog: 368 keys / 3312 values across nine languages. Schema: 15 passed. Project generator is idempotent. Six product flows have native evidence, plus three iPad flows, nine-language screen captures and German/Thai largest-text checks. Exact success/failure/source scope is recorded in the linked report; full device/VoiceOver/native-speaker acceptance remains open.
- New app + Widget archive: `/private/tmp/LightPlan-rich-final.xcarchive`; development signing, matching App Groups, privacy manifests, MIT notices and no StoreKit/debug fixture checked. This is not App Store distribution approval.
- On 2026-09-23, the development-signed candidate was installed and launched on the paired physical "Hello iPhone" (iPhone 17 Pro); a separate device app listing confirmed LightPlan 1.0.0 (1). In-app field verification on that phone remains pending. No commit, push, merge, website deployment, upload or submission.

See [this round's evidence and remaining checks](tests/reports/photography-tools-2026-09-22.md) and [product value acceptance](docs/PRODUCT_VALUE_ACCEPTANCE.md). Earlier candidate summaries below are historical; their archives do not include these new features.

# Current paid-download product candidate — 2026-09-22

**Local product work and a signed development Release archive passed. Not ready for App Store submission.**

- Changed to paid download at the owner's explicit request. All functionality is available after installation; no IAP, paywall, restore-purchase flow or local entitlement switch remains.
- Added constrained opportunities, saved search conditions, field notes and shareable briefs, morning/evening windows and accessible coordinate entry; repaired reminder concurrency and high-latitude calculations.
- Core: 139 tests. Independent event oracle: 31/31 civil days. Position oracle: 396 samples. Final iPhone layout/capture suite: four passed; final iPad suite: four passed. Six product flows passed before the final visual-only corrections.
- Generated 54 native simulator screenshot drafts at App Store primary sizes, with nine-language layout review. Catalog: 283 keys / 2547 values; mother-tongue and real VoiceOver acceptance remain separate.
- Signed Release archive for app and Widget passed; signing integrity, App Group consistency, privacy manifests, MIT notices and absence of StoreKit/debug fixtures checked. This is development signing, not App Store distribution approval.
- Owner confirmed the existing same-name Rivolu app is unrelated and requested an independent name; LumaVantage / LumaBearing are prepared, awaiting a choice. Public identity/contact/URLs, actual pricing and account/TestFlight/device acceptance remain open.
- No commit, push, merge, new physical iPhone install, website deployment, upload or submission performed.

See [this round's report](tests/reports/paid-product-2026-09-22.md), [submission handoff](docs/APP_STORE_HANDOFF.md), and [value acceptance](docs/PRODUCT_VALUE_ACCEPTANCE.md). Earlier IAP evidence below is historical and does not describe the current business model.

# Current composition-plan development candidate — 2026-09-22

The composition-to-plan workflow now saves and restores the observer, subject,
Sun/Moon, desired offset and exact time, and schedules reminders for that instant.
Schema 2 reads old v1 backups and preserves migration originals. The draft survives
the paywall; refunded users can still read/export and restore the saved map.

- Core: 107 tests passed. Complete iPhone suite: 11 passed. Serial iPad checks:
  three passed. The final read-only quality display passed two focused iPhone checks.
- Reminder tests query the simulator OS queue and verify the actual scheduled
  time and cancellation; they do not prove physical-device lock-screen delivery.
- Existing no-debugger Run settings are now generated consistently. Original local
  edits and failed test records were preserved outside the public commit candidate.
- Final unsigned Release archive passed for app and Widget, with no StoreKit test
  configuration in the application. Catalog: 278 keys across nine languages; audits passed.
- Owner confirmed the real IAP product is not configured. Domain/contact/legal
  website details remain unconfirmed; support/privacy pages are unpublished drafts.

See the [current report](tests/reports/composition-plans-2026-09-22.md) and
[paid acceptance](docs/PAID_ACCEPTANCE.md). No commit, push, merge, physical iPhone
installation, website deployment or store submission was performed in this round.

# Earlier composition merge candidate — 2026-09-22

**Local fixes and verification passed; the exact pushed commit still requires
GitHub CI before merging to main. No new commit, push or merge was performed.**

- Fixed empty catalog extraction at the source, observer-dependent composition
  refresh, worker cancellation and stale-result isolation.
- Fixed iPad map-control identifier inheritance and zero-bounds MapReader overlay
  ancestors; preserved assertions and verified actual button taps in both orientations.
- Defined full result-row hit regions and added purchase/search/stand/refund coverage.
- Core: 96 tests passed. Localization: 272 keys across nine languages; metadata audit passed.
- Initial full iPhone suite: nine tests passed with 30 screenshots, before the last
  hit-region/MapReader layout fixes. Final-source targeted regressions: three passed
  on iPhone and three on iPad, each with zero failures.
- Final unsigned Release archive passed for app and widget and contains no local
  StoreKit test configuration. Project generation produces no tracked-file drift.
- Current native captures were visually inspected and are retained locally with
  xcresult bundles; raw device/signing diagnostics remain Git-ignored.

See the [composition merge report](tests/reports/composition-merge-2026-09-22.md)
for source fingerprints, toolchain, failed-run history and the remote-CI boundary.
This round did not update the physical iPhone installation described below.

# Earlier local iPhone preview — 2026-09-22

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
