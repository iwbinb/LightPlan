# Composition plans — 2026-09-22

The app now connects composition search to a persistent plan, restoration and a
reminder anchored to the confirmed composition instant. This extends the earlier
local composition repairs based on dev `4132f7d`. No commit, push, merge, website
deployment or App Store submission was performed.

## Delivered behavior

- Save observer/place/time zone, subject coordinate, Sun/Moon, desired offset and
  exact instant. A typed sheet route carries the complete draft across purchasing;
  it cannot silently fall back to an ordinary sunset editor.
- Reopen the app, read the saved composition and restore its original map, body,
  offset and time. Reading/export and disabling reminders remain available after refund.
- Editing date/body/offset recalculates the alignment; missing results block saving.
  Details distinguish requested offset from computed error, quality and frame side.
- Arrival and reminder use the saved instant. Details check the actual notification
  queue and scheduled time, and provide retry/disable actions. Queue presence is
  not a claim of physical lock-screen delivery.
- Write archive schema 2; read schema 1 and 2. Original v1 bytes receive a separate
  migration backup that later ordinary writes do not overwrite. New v2 files require
  a compatible app; old clients must reject them rather than discard composition data.
- Added six keys in all nine languages. The owner's no-debugger Run scheme semantics
  were preserved in the project generator, including the existing test launcher.

## Executed validation

| Check | Result | Boundary |
| --- | --- | --- |
| Foundation core | 107 passed, zero failures | Includes 11 new persistence/migration/reminder tests |
| Complete iPhone UI suite | 11 passed, zero failures | Includes nine-language screens; before final read-only quality display |
| Serial iPad regression | Three passed, zero failures | Save/relaunch/refund/map restore, OS notification schedule/disable, rotation |
| Final quality/display regression | Two passed, zero failures on iPhone | Confirms weak alignment is disclosed while persistence and reminders still work |
| Final Release archive | Passed | App and Widget, unsigned; no local StoreKit test configuration in the app |

The native runs used Xcode 27.0 / iOS 27.0 simulators, iPhone 18 Pro and iPad Pro
11-inch (M5). The final two-test run follows the last read-only detail changes;
the entire nine-language matrix was not repeated for that display-only adjustment.
The core migration tests also verify exact reminder timing across midnight and
the repeated DST hour, invalid/misversioned payload rejection, and disabled imported
reminders by default.

The final catalog audit passed with 278 keys across nine languages (2,502 values);
metadata checks and generator idempotency also passed. This establishes resource
completeness, not native-speaker review.

The new tests caught a real draft presentation bug: a boolean sheet with a separate
optional draft could open as a solar plan after purchasing. A route carrying the
immutable draft fixed it. Test gestures were also scoped away from the floating
tab bar. Failed records remain local. A first parallel iPad attempt was stopped
before its cases ran to reduce resource contention; the later serial run passed.

## Evidence

Raw commands/logs, original worktree and scheme copies are local-only under ignored
`tests/reports/local/2026-09-22-composition-plans/`. Current native captures and
xcresult bundles are retained in ignored `tests/reports/v3/native-composition-plans-20260922/`.
These are not broken links to unpublished GitHub files. The screenshots show the
saved Moon/right-offset plan, its restoration after refund, and a future Sun plan
with a matching system reminder. Codex inspected these native captures.

The [machine-readable summary](composition-plans-2026-09-22.json) records final
source hashes, checks and release boundaries. Earlier composition-merge reports
are historical and do not certify the new schema or persisted-plan flow.

## Remaining paid-release prerequisites

The owner confirmed the App Store Connect product is not configured. Real Apple
sandbox purchasing has not been verified. Website legal identity/domain/contact
are awaiting owner confirmation, and existing draft markers/empty metadata URLs
have not been replaced with invented publication evidence. Physical-device
notification delivery, location/map alignment, Widget behavior, accessibility,
performance and independent user acceptance retain their release gates.

See [paid acceptance](../../docs/PAID_ACCEPTANCE.md). This is a tested development
candidate, not a claim that the app is ready to charge customers or already published.
