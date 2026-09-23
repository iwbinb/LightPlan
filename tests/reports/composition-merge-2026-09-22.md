# Composition merge candidate — 2026-09-22

Historical report before persisted composition plans. For the later working tree,
see [composition plans](composition-plans-2026-09-22.md); the hashes below must not
be used to certify the newer schema or reminder flow.

Base: `4132f7d` on `dev`. Local validation passed for the merge candidate. No new
commit, push, PR merge or App Store submission has been performed; the exact pushed
commit still needs its GitHub CI result before merging.

## Fixes

- Replaced the daily composition string key with a typed request containing the
  observer, subject, body, full day interval and desired offset. Results are only
  displayed for the matching request; generation guards protect against late tasks.
- Daily and multi-day searches forward cancellation to their detached workers.
  Closing a paid result sheet or losing entitlement prevents late paid results.
- Removed empty auto-extracted catalog entries after preserving the original local
  edit. Brand names and internal test-state text now use explicit verbatim text.
- Removed container accessibility identifiers that overwrote child button IDs.
  Map controls are siblings of MapReader in a bounded accessibility container,
  avoiding zero-sized overlay ancestors after iPad rotation. No assertion was skipped.
- Defined result-row and circular-button hit regions. Result rows accept taps in
  the blank space between their columns, including on iPad.
- Added same-day observer-change, lunar alignment and cancellation tests; added
  purchase-to-search, opportunity selection, suggested observer and refund UI coverage.
  Map controls are checked and operated in both portrait and landscape.

## Verification

| Check | Result | Scope |
| --- | --- | --- |
| Core XCTest | 96 passed, zero failures | Includes four new regression tests |
| Catalog and metadata audits | Passed | 272 keys, nine languages; not native-speaker review |
| Project generator consistency | Passed | No generated-project or plist drift |
| Initial full iPhone suite | Nine passed, zero failures | Includes 30 screenshots; before final hit-region and MapReader layout fixes |
| iPad reproduction | Failed as expected | Same missing map-style control as the original CI failure |
| iPad result-row regression | Passed | Purchase, select opportunity, suggested observer, refund |
| iPad MapReader layout regression | Passed | All map controls found and hittable; actual style/recenter taps preserve time |
| Final iPhone targeted regression | Three passed, zero failures | Final layout, composition flow and both orientations |
| Final iPad targeted regression | Three passed, zero failures | Final layout, composition flow and both orientations |
| Final Release archive | Passed | App and Widget; unsigned; no StoreKit testing configuration in the app |

Native checks use local Xcode 27.0 and iOS 27.0 simulators: iPhone 18 Pro and iPad
Pro 11-inch (M5). The [original failing CI run](https://github.com/iwbinb/LightPlan/actions/runs/35691258127)
used Xcode 26.3; its exported screenshot and accessibility hierarchy were inspected.
That run confirmed buttons existed visually but their identifiers were inherited
from screen-map. Local follow-up also identified empty MapReader overlay ancestor
bounds. The failures and their diagnostics remain available locally.

The earlier full nine-language screenshot run is baseline evidence; final targeted
captures cover the touched map and composition flows. No claim is made that the
entire nine-language matrix was repeated after each layout adjustment.

## Evidence and integration boundary

Raw logs, original catalog edits, failing and passing test bundles, and extracted
native screenshots are local-only under the ignored evidence directories. Public
summaries contain no account identifiers, device IDs or personal filesystem paths.
The final six map/composition screenshots and two xcresult bundles are retained
locally in `tests/reports/v3/native-composition-20260922/`. Codex inspected the
final iPhone and iPad composition/landscape captures: map attribution remains
visible, the original photographic sidebar is preserved, and composition controls
remain in their scrollable panels. These are native simulator captures, not
physical-device or browser evidence.
The [machine-readable summary](composition-merge-2026-09-22.json) records the
tested source hashes and distinguishes the full baseline run from final regressions.
The catalog remains at 272 translated keys; compiler extraction for the affected
Settings and Widget files contains no new brand/state localization entries.

At the branch check, local/remote main was `3fd00c5`, an ancestor of dev `4132f7d`.
The branches have no existing divergence to resolve. These repairs remain local
until explicitly committed/pushed. The exact pushed commit must pass the
[native CI workflow](../../.github/workflows/ci.yml) before merging to main; an old
CI failure or an earlier successful build cannot certify this working tree.

This is engineering merge preparation, not App Store release acceptance. Physical
runtime, real StoreKit sandbox, notification/Widget delivery, accessibility/device
coverage and release-owner configuration retain their existing gates.
