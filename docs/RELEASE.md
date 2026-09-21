# Release and owner configuration

## Identity

Current candidate IDs: `com.arenovo.lightplan`, widget suffix `.widget`, app group `group.com.arenovo.lightplan`, non-consumable `com.arenovo.lightplan.lifetime`. The candidate contact is `hello@arenovo.com`; these LightPlan-specific registrations/contact approvals have not been supplied by the owner. Centralize changes in `ios/Config/Project.xcconfig`, update the local StoreKit configuration and tests together, and confirm the public support domain before release. Apple seller/legal identity comes from the owner's developer account, not a string invented by this app.

## Charge customers

Create one **Non-Consumable** matching the product ID in App Store Connect; provide all nine product localizations, review screenshot and a review note. Target $2.99 / ¥18 is a pricing hypothesis; App Store Connect determines regional price points. The app displays `Product.displayPrice`, never a hard-coded amount. Complete Apple's paid-app agreements/tax/banking as the owner. Do not attach a `.storekit` configuration to the archive scheme. Sandbox test purchase, cancellation, Ask to Buy/pending, interrupted/restarted app, restore on a second installation, refund/revocation, offline previously verified access and all purchase-gated entry points.

## Native acceptance

The read-only GitHub workflow produces a Debug simulator build, unsigned Release device archive, Foundation tests, StoreKit local XCTest and actual SDK screenshots. Inspect the logs/xcresult for the exact commit; an old passing run cannot certify newer source. The unsigned archive proves compilation, NOT distribution signing or upload validity.

Compare real home/map/plan screenshots against the approved v3 photographic style. Keep the coastal artwork, independent text overlay, card layering, actual curve, real MapKit with visible attribution, floating controls, selected-time state and expanded inspector. Do not substitute a diagram or browser screenshot for a native map. Review each language, dark mode, long text, 12/24h, large accessibility type, VoiceOver, reduced motion/transparency, keyboard and portrait/landscape states. Physical Duo behavior remains explicitly unverified until tested on that hardware.

## Account and App Store steps

Owner approves product name/trademark, bundle/app-group IDs, support address and legal operator; registers the group on both targets; signs with the selected Team. Publish `site/` on the approved Cloudflare domain after replacing identity fields and verifying privacy/support URLs. No app backend or Cloudflare paid service is required. Review App Store privacy details against actual SDK behavior; no own analytics/ads/backend is included. Fill Apple's current age-rating/trader/accessibility questions accurately; do not claim an accessibility badge before its complete test protocol passes. Supply actual native screenshots, not the v3 browser reference or generated promotional collage.

Archive with the owner team, validate in Organizer, upload to TestFlight, verify a real phone and the Apple sandbox, then submit the app together with its first IAP. Do not automatically accept legal agreements, change prices, publish the site, or submit a build without the owner's explicit final authorization.

## Accuracy disclosure

Offline algorithms cover civil years 1900–2100. Event root-search precision is not physical accuracy; topocentric positions use a compact analytical model. Displayed directions are true north. Golden light uses geometric solar-center altitude −4°…+6°, blue −6°…−4°. Rise/set uses modeled solar/lunar semidiameter and 34 arcminutes standard refraction at sea level. Actual atmospheric refraction, terrain, buildings and local weather can materially change visibility. Never promise a guaranteed photographic result or terrain-aware shadow simulation.

## Maintenance

Keep schema migration and immutable plan place snapshots. Import previews must validate before atomic replacement and preserve original damaged bytes. No local premium boolean or secret bypass is allowed. Keep source catalogs synchronized and retain executed failure evidence. Pin CI actions, review changes in PRs, avoid broad force pushes and never commit owner certificates/tokens. Regression suite must run on every source change.

Primary platform references (checked 2026-09-21):
- https://developer.apple.com/news/upcoming-requirements/
- https://developer.apple.com/app-store/submitting/
- https://developer.apple.com/documentation/storekittest
- https://developer.apple.com/documentation/storekit/transaction/currententitlements
