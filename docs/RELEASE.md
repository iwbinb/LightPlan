# Release and owner configuration

最新功能候选及验证边界见[摄影工具增强报告](../tests/reports/photography-tools-2026-09-22.md)；当前归档为本机开发签名，新增功能不自动满足正式提交门槛。

## Identity

Current candidate IDs: `com.arenovo.lightplan`, widget suffix `.widget`, app group `group.com.arenovo.lightplan`. The owner must confirm these registrations and the public support contact/domain. Public build versions, identifiers and contact fields originate in `appstore/release_config.json`; regenerate `ios/Config/Project.xcconfig` and the project with `scripts/generate_project.py`. Local Team overrides stay in ignored `Local.xcconfig`. There is no in-app product ID in the paid-upfront model selected on 2026-09-22. Apple seller/legal identity comes from the owner's developer account, not a string invented by this app.

## Charge customers

The owner selected **paid upfront** on 2026-09-22: configure the app's price and territories in App Store Connect, then users purchase before downloading and all installed-app features are available. No in-app purchase, subscription, paywall or restore-purchase action remains. The $99 target expresses intended customer value, not a selling price; the actual price is still an owner decision. Complete Apple's paid-app agreements/tax/banking as the owner.

Verify fresh installation, upgrade with existing local data, relaunch, complete planning/Widget access and offline use with known coordinates/timezones. TestFlight validates the binary's full functionality; it does not prove a real paid sale. Preserve old purchase-test evidence as history, but do not use it to certify this new distribution model. See `docs/07_收费与恢复购买.md` and `docs/APP_STORE_HANDOFF.md`.

## Native acceptance

The read-only GitHub workflow produces a Debug simulator build, unsigned Release device archive, Foundation tests, full-function native XCTest and actual SDK screenshots. Inspect the logs/xcresult for the exact commit; an old passing run cannot certify newer source. The unsigned archive proves compilation, NOT distribution signing or upload validity.

Compare real home/map/plan screenshots against the approved v3 photographic style. Keep the coastal artwork, independent text overlay, card layering, actual curve, real MapKit with visible attribution, floating controls, selected-time state and expanded inspector. Do not substitute a diagram or browser screenshot for a native map. Review each language, dark mode, long text, 12/24h, large accessibility type, VoiceOver, reduced motion/transparency, keyboard and portrait/landscape states. Physical Duo behavior remains explicitly unverified until tested on that hardware.

## Account and App Store steps

Owner approves product name/trademark, bundle/app-group IDs, support address and legal operator; registers the group on both targets; signs with the selected Team. Publish `site/` on the approved Cloudflare domain after replacing identity fields and verifying privacy/support URLs. No app backend or Cloudflare paid service is required. Review App Store privacy details against actual SDK behavior; no own analytics/ads/backend is included. Fill Apple's current age-rating/trader/accessibility questions accurately; do not claim an accessibility badge before its complete test protocol passes. Supply actual native screenshots, not the v3 browser reference or generated promotional collage.

Archive with the owner team, validate in Organizer, upload to TestFlight, verify full functionality and offline workflows on a real phone, then prepare the paid app submission. No IAP submission is needed. Do not automatically accept legal agreements, change prices, publish the site, or submit a build without the owner's explicit final authorization.

## Accuracy disclosure

Offline algorithms cover civil years 1900–2100. Event root-search precision is not physical accuracy; topocentric positions use a compact analytical model. Displayed directions are true north. Golden light uses geometric solar-center altitude −4°…+6°, blue −6°…−4°. Rise/set uses modeled solar/lunar semidiameter and 34 arcminutes standard refraction at sea level. Actual atmospheric refraction, terrain, buildings and local weather can materially change visibility. Never promise a guaranteed photographic result or terrain-aware shadow simulation.

## Maintenance

Keep schema migration and immutable plan place snapshots. Import previews must validate before atomic replacement and preserve original damaged bytes. Do not reintroduce a local premium boolean or paywall into the paid-download app. Keep source catalogs synchronized and retain executed failure evidence. Pin CI actions, review changes in PRs, avoid broad force pushes and never commit owner certificates/tokens. Regression suite must run on every source change.

Primary platform references (paid-app configuration checked 2026-09-22; recheck SDK requirements before upload):
- https://developer.apple.com/news/upcoming-requirements/
- https://developer.apple.com/app-store/submitting/
- https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price
- https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements

## M6-A / M6-B

Use [M6_RELEASE_READINESS.md](M6_RELEASE_READINESS.md) for the current repository tools and [M6B_LOCAL_HANDOFF.md](M6B_LOCAL_HANDOFF.md) for final source-bound local acceptance. New preparations do not inherit historical approvals.
