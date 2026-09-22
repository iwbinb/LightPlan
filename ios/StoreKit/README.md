# StoreKit local test setup

LightPlan uses the non-consumable product ID `com.arenovo.lightplan.lifetime`.
The checked-in `LightPlan.storekit` file is **test-only** and is included in the
`LightPlanUITests` target so `SKTestSession` can exercise signed local StoreKit
transactions in CI.

It is deliberately **not** a resource of the LightPlan application target and is
not attached to the normal Run or Archive scheme. CI fails if any `.storekit`
file appears inside the Release `LightPlan.app` archive.

The local configuration currently covers the one-time unlock at a sample US
price of 2.99 for automated testing. It does not create an App Store Connect
product, set production pricing, or prove sandbox/production payment acceptance.

Before App Store submission, the owner must create/confirm the matching
non-consumable in App Store Connect, complete agreements/tax/banking as needed,
and verify first purchase, cancellation, pending approval, restore, refund or
revocation, relaunch persistence, and purchase availability using Apple's
sandbox/TestFlight path on an authorized account/device.
