# M6-A release preparation — 2026-09-27

## Scope and source

Based on merged M5 `e4c84fa4b181e1cc62f89935d288809b40867898`, source tree `2bf48f37ed7b732956e815c0b32876ef3fc75385`. The owner requested repository release preparation, not upload or publication. `dev` was fast-forwarded without force. The working copy came from the fixed, read-only Actions source archive; its ZIP SHA-256 was `cbc283e333ab2ef9b51819264fff09d411bc121b5d76eb10685049d8fcd713e6`, and the extracted tree matched the baseline exactly.

No application/Core/Widget source, astronomical precision, archive schema, language, payment model or signing credentials were changed. The generator's current output remains byte-for-byte identical to the checked-in M5 project/plists/identifier configuration. New configuration fields preserve version 1.0.0 (1) and minimum iOS 17.0; they are configuration inputs, not App Store account approval.

## Changes

1. Shared validated public release settings feed project generation. Name, IDs, version/build and minimum OS no longer need separate hard-coded edits. Invalid input fails before overwriting generated files; local signing overrides are retained.
2. PNG inspection now verifies complete chunk structure/CRC, compressed payload length, scanline filter bytes and resource limits, including Adam7 input. The previous implementation accepted a 24-byte header as screenshot dimensions; that concrete false-positive was reproduced before repair.
3. Final preflight additionally compares archived App/Widget versions, display name, minimum OS, device SDK, privacy manifests and actual signed entitlements. It keeps all existing gates, screenshots, metadata and account requirements. It cannot certify Apple distribution eligibility or attestations' truth.
4. `--gates` supports a source-bound ignored local acceptance ledger. `prepare_release.py` creates a new atomic local workspace with all final-source gates/account checks pending, preserving all tracked history and prior owner evidence. It copies only named public documents/configuration, not signing credentials or arbitrary local files. Prepared does not mean ready to submit.
5. `capture_store_screenshots.sh` and `Native Store screenshot drafts` supply a runnable native primary-slot capture path. Only dedicated newly created simulators are removed; screenshots are not rescaled or auto-approved. Actual Mac execution is separately recorded by CI. No final brand or screenshot approval is fabricated.
6. M6-B local handoff and current M6 release instructions clarify final source, configuration, nine-language materials, device checks, native captures and signed-archive preflight. Historical submission documents are retained and linked rather than silently rewritten as current evidence.

## Executed local checks

Environment: isolated Linux x86_64 / Swift 6.2.1 / Python 3.11. This is not the user's Mac or Apple SDK.

| Command | Result |
|---|---|
| `swift test --package-path packages/LightPlanCore` | 280 tests, 0 failures; complete rerun exit 0 |
| `python3 scripts/release_preflight_tests.py` | 30 tests passed (24 retained + 6 new) |
| `python3 scripts/package_store_screenshots_tests.py` | 10 retained tests passed |
| `python3 scripts/release_integrity_tests.py` | 10 new tests passed |
| `python3 scripts/prepare_release_tests.py` | 10 new tests passed |
| `python3 scripts/release_generator_tests.py` | 4 new tests passed |
| `python3 scripts/ci_baseline_tests.py` | 36 retained tests passed |
| `python3 scripts/release_schema_tests.py` | 15 retained tests passed |
| Localization / metadata | 389 keys, nine languages, 3501 values, 0 completeness errors / nine metadata files passed |
| Generator comparison | Identical current project output; overridden settings and repeated generation verified in isolated fixtures |
| Python/Shell/YAML syntax and diff checks | Passed |

Total new release-tool regressions: 30. All fixtures are synthetic and are not submission evidence. One first local preparation test failed because its symlink fixture was caught by the dirty-worktree guard before the intended path guard; path validation now happens before source validation and the complete suite passes. One first core command exceeded the runner's 45-second command budget while compiling/testing; a subsequent complete invocation passed 280/280 in 22.578 seconds of test execution, exit 0. The interrupted command is not counted as success.

The baseline `release_preflight --report-only` produced 123 submission blockers with `ready_for_submission=false`; this expected result is not a build/test failure. Added integrity checks may increase the list until owner and device evidence are supplied. No gate or approval flag was changed to make it green.

## Remaining evidence and release gates

This report records local implementation checks. Newly triggered macOS native/checks and Store-capture workflow results must be read for their exact candidate commit, and cannot be inferred from M5's success. A capture workflow is a draft production tool, not a completed screenshot approval; brand/URL-dependent final capture remains open.

Final product name/localized display names, legal operator, verified support email/domain, price/territories, Apple account/Team/registered IDs, live privacy/support pages and final screenshots remain unconfirmed. Real devices, minimum OS, notifications/Widget/offline/import providers, VoiceOver/native-speaker checks, performance/energy, distribution signing, TestFlight and owner submission approval belong to M6-B. No Cloudflare deployment, Apple-account change, merge to main, tag, release, signing or upload was performed.

Use [M6 repository preparation](../../docs/M6_RELEASE_READINESS.md) and [local handoff](../../docs/M6B_LOCAL_HANDOFF.md). Official Apple SDK/screenshot/metadata sources and their recheck date are included there.
