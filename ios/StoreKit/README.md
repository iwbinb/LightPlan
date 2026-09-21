# StoreKit local test setup — not yet verified

The native purchase service uses non-consumable product ID `org.nodestake.lightplan.lifetime`. This candidate must match the final authorized App Store Connect configuration.

In the installed supported Xcode, create a **StoreKit Configuration File** for the project, add a non-consumable product with the same ID, set example display name “LightPlan Complete” and test price 2.99, then attach it to the Debug scheme. Confirm the current schema through Xcode rather than hand-writing an unverified `.storekit` file. Record the generated configuration and Xcode version in the repository once tested.

Run first-purchase, cancellation, pending approval, failure, restored entitlement and revoked transaction cases. Local configuration testing is not a sandbox transaction or production pricing configuration. Before release, confirm no local StoreKit file is active in production distribution and complete sandbox tests on an authorized test account.

No payment has been made, no product has been registered and no transaction has been verified in this handoff session.
