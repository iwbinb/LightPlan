# M6-A PR #7: signed-entitlement fixture follow-up — 2026-09-27

The new cross-platform release-tools matrix in `8137c00cd5b85bb0564aae3daa5a111325bf3ad6` exposed an additional macOS-only **test fixture** problem before its preparation tests could run. It is not evidence of a real App/Widget signature failure.

[PR release-tools run #5](https://github.com/iwbinb/LightPlan/actions/runs/36280725333), macOS job `108511900300`, tested merge ref `fc245343d2dd05b8f5aa545e4732ea31c5aadff0`. Integrity tests passed 10/10; preflight tests failed 2/30 with `Archived widget: signed application identifier mismatch`. The Ubuntu job passed. Raw job logs were read; the macOS preparation/smoke steps did not execute in this failed job.

The mocked `signed_entitlements` callback compared the canonical archive path provided by production code against the fixture's noncanonical temporary path. It therefore returned the main App's synthetic identifier for the Widget on macOS. The production archive verifier correctly rejected that mismatch.

The fixture now maps the canonical identities of the two known bundles to their distinct synthetic identifiers. An unknown fixture bundle raises an assertion rather than silently receiving App entitlements. **Production `release_preflight.py`, real signed-entitlement inspection and all original positive/negative acceptance assertions are unchanged.**

Two new regressions explicitly check App and Widget through a portable checkout alias and reject unknown bundle identities. Against the old callback, the expanded suite failed two tests on Linux as expected (exit 1, 32 tests). With the fixture correction, the exact suite passed **32/32**, exit 0. The new aggregate release-tools inventory is **73** (32 preflight + 17 preparation + 10 integrity + 10 screenshot packaging + 4 generator); other suites retain the separately recorded successful results from the preceding repair and must execute again in current-source CI.

Reproduction: `python3 scripts/release_preflight_tests.py`; `python3 -m py_compile scripts/release_preflight_tests.py`; `git diff --check`. Local validation used Linux/Python and synthetic files only, with no signing command or Apple account access. Both failing and successful local invocations completed. The prior path repair, native map-style polling candidate, failure ZIP references and core/UI verification boundaries remain in [the preceding repair report](m6a-pr7-check-repair-2026-09-27.md).

This follow-up changes only the synthetic test fixture, its two new regression cases and this report. Native map tests still require the current commit's Apple run. PR #7 stays Draft pending current-source platform/native checks; no main merge, generated project change, pricing/precision/schema change, signing or publication is performed.
