# M6-A repository release preparation — 2026-09-27

**M6-A release-tooling implementation and local regression are complete; current-commit Apple/native and Store-capture CI must still be checked. This is repository preparation, not M6-B or App Store readiness.**

- Based on owner-merged M5 PR #6, main `e4c84fa4b181e1cc62f89935d288809b40867898`; dev was fast-forwarded without force.
- Shared validated build configuration, complete PNG integrity checks, App/Widget archive/entitlement consistency and a source-bound local gate ledger now support release preparation.
- New atomic `prepare_release.py` preserves old evidence and resets final-source attestations to pending. New native Store capture tooling uses dedicated simulators and never approves images or publishes to Apple.
- Local core 280/280; release preflight 30/30; image/settings 10/10; preparation 10/10; generator 4/4; screenshot packaging 10/10; CI helper 36/36; schema 15/15. All are executed local checks, not Apple signing/device acceptance.
- Current generated App project and plists remain identical to M5; no App/Core/Widget business code, pricing, precision, schema or signing changes.
- Final identity/contact/price, actual screenshots/translation approval and all device/account/distribution gates remain open. No main merge or upload.

See [M6-A report](tests/reports/m6a-release-preparation-2026-09-27.md), [release tools](docs/M6_RELEASE_READINESS.md), and [Mac/Codex handoff](docs/M6B_LOCAL_HANDOFF.md). Earlier status below is preserved as historical evidence.

---

# M5 automated acceptance and review handoff — 2026-09-26

**M5 implementation, final-source native regression and the scoped screenshot review are complete. PR #6 is a merge candidate, not App Store release approval. No merge, auto-merge, M6 implementation, signing change or release is authorized by this handoff.**

## Verified source

- Source: `9fada0d5bb1940f4c160ae181e10e1a2919ce9c6`; tree: `f0a4cce900a15b3a5ac7dab9993bf99d4950ddfb`.
- Base: merged M4 `133d833d3b2a3469b8345662a3f20c2ec6079403`.
- [Native push #68](https://github.com/iwbinb/LightPlan/actions/runs/36218053082): **11/11 groups passed**, attempt 1, completed 2026-09-26 05:41:00 UTC.
- [PR merge-ref native #69](https://github.com/iwbinb/LightPlan/actions/runs/36218055216): **11/11 groups passed**, attempt 1, completed 2026-09-26 05:38:04 UTC. Tested merge ref: `209e303bbb9cec43eea7cb95e72c666efa236482`.
- [PR core #17](https://github.com/iwbinb/LightPlan/actions/runs/36218055271): passed.

## Evidence checked

All eleven run-68 ZIP digests, source commits, runner/command exits, selected tests and actual passed-test names were checked. **280 core tests**, **40 native-target executions** (38 real UI executions + two helper regressions), **36 CI helper tests**, Debug simulator build and unsigned Release archive passed. Native failures, skips and expected failures are zero. All 39 distinct iPhone methods were selected once; the existing rotation method additionally ran on iPad. PR-69 checks/product ZIPs were independently downloaded and validated; the other PR-69 groups were checked through Actions metadata.

A scoped review inspected **56 exported native PNGs**: all screenshots in run-68 polish, basic visual, rich accessibility, product and iPad rotation artifacts. This covers the new German/Thai largest-text headings and orientation controls, the large-library workflow, nine-language core screens, composition entry, and dark iPad rotation. It is not a claim that every exported screenshot, VoiceOver interaction, translation or physical-device condition was independently reviewed.

The earlier composition-entry and readiness failures are retained in their reports. The repaired readiness traces reached the final live hit check in about 2.13 and 2.29 seconds; these are test-helper timings, not application cold-launch measurements. No test or precision gate was removed to obtain a pass.

## Handoff and remaining gates

- [M5 final acceptance, performance scope and reproduction](tests/reports/m5-acceptance-2026-09-26.md).
- [Source, artifact hashes and execution manifest](tests/reports/m5-native-verification-2026-09-26.json).
- [Original M5 implementation record](tests/reports/m5-performance-polish-2026-09-25.md), [entry repair](tests/reports/m5-composition-entry-repair-2026-09-26.md), and [readiness repair](tests/reports/m5-readiness-polling-repair-2026-09-26.md) remain historical evidence.
- This closeout changes documentation only. Any new PR checks triggered by its commit must finish successfully before merging; the completed runs above are not relabeled as executions of the documentation commit.
- Device launch/frame/memory/energy metrics, minimum OS, real split-screen, VoiceOver, native-speaker review, physical notification/Widget/offline/file-provider behaviour and Store/account/distribution signing remain release gates. Native simulator captures are not final App Store screenshots.
- Paid download, nine languages, archive schema 2/legacy v1 compatibility, astronomical coefficients and precision are unchanged.

## Preserved status history

The complete previous `STATUS.md` is preserved byte-for-byte in [STATUS_HISTORY_2026-09-26.md](STATUS_HISTORY_2026-09-26.md), using its original Git blob `191ed0f82022fc49147ee3dc5781ebdf60857912`. It stays at the repository root so its relative links keep working. Its pending statements describe historical source versions, not this completed M5 source review.
