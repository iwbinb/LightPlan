# M6-A PR #7 check repair — 2026-09-27

## Scope and evidence

Original source: `b7d832f69a5c37ae0d6258e2651aafd14f693905`; PR merge ref: `04b10ff0df5acbc26b44fc277443e1c40ec32eec`.
[PR native run #73](https://github.com/iwbinb/LightPlan/actions/runs/36260355359) completed with nine successful groups and two failed groups. This report preserves both failures; old successful groups are not acceptance evidence for this repair commit.

| Failed group | Actual failure | Original evidence |
|---|---|---|
| `checks`, job `108454866507` | `prepare_release_tests.py`: 7 failures, 2 errors out of 10 tests; exit 1 before core/build stages | [ZIP 10912845764](https://github.com/iwbinb/LightPlan/actions/runs/36260355359/artifacts/10912845764), SHA-256 `96c302feaa832efd8481db8da97820cc1015bca3f596121fe8a4f1de076a6593` |
| `iphone-visual`, job `108454866992` | `VisualUITests/testMapBaseStyleSwitchesAndSurvivesRelaunch`: 4/5 passed, one timed-out value expectation, zero skips; xcodebuild exit 65 | [ZIP 10913208450](https://github.com/iwbinb/LightPlan/actions/runs/36260355359/artifacts/10913208450), SHA-256 `a935dd21e8ba0139c4333692cb9131e705531db34f4319f61daacef32831f653` |

Both ZIPs were downloaded and their digests checked. The original command records, raw logs, exported screenshot and map-style recording were examined. This was not an Actions quota failure or compilation failure.

## 1. Canonical checkout ancestry, without weakening evidence-path protection

`prepare_release.py` canonicalized `root` with `resolve()` but left `output` at `absolute()`. A checkout reached through an ancestor alias (including the macOS temporary-directory `/var` spelling) therefore failed the containment/equality checks against its canonical `/private/var` root.

A portable ancestor-alias fixture reproduced the same rejection against the original implementation on Linux: 16 tests, two alias-case errors. The fixture deliberately does not canonicalize the input before invoking production code.

The fix maps only the path leading to the outermost matching checkout root to its canonical spelling. It does **not** resolve away the output suffix. Existing checks still reject evidence-root/descendant symlinks, outside destinations, existing evidence, dirty Git state and unignored outputs. Parent traversal is explicitly rejected. A descendant link pointing back to the checkout root is still rejected rather than treated as an authorized ancestor alias.

Seven new regression cases cover both root/output alias directions, canonical output, inside-root redirection, links back to the checkout, parent traversal and an outside sibling. All original ten preparation tests remain intact; the final preparation suite contains 17 tests. The standalone release-tool workflow now runs on both Ubuntu and macOS, with fail-fast disabled, so Linux success cannot conceal the platform-specific failure again.

## 2. Map-style feedback polling

The original raw log shows one actual tap, followed by a live `value == 普通地图` expectation. Its first lookup began at test time 15.59 seconds; the next diagnostic appears at 24.80 seconds and the 10-second waiter failed. The recording shows the icon changing to the globe and the imagery changing to a standard-map loading grid. It does **not** prove network tiles finished loading or that the expected accessibility value was already available at every polling instant. The artifact does not establish a unique lower-level XCTest/MapKit cause.

The repair removes repeated live element resolution from each poll: one public immutable application snapshot supplies both the unique style button value and the native map's actual configuration value. A pass requires both to match. The original 10-second timeout, single real taps, changed-value checks and relaunch persistence checks remain; checks now also verify the restored native map and the final reversal, not just the button. No test-side style injection, repeated-tap fallback, test deletion or deadline increase is used.

A pure observation regression rejects missing/duplicate identifiers, missing values, disagreement between map and button, and empty expectations. Each real UI wait attaches bounded poll timing/value diagnostics; a failure also saves a screenshot and accessibility hierarchy. This is a testing-path repair candidate, not a claimed production map-rendering fix.

## Local commands and results

Isolated Linux checkout, Swift 6.2.1; the source archive tree was verified against Git tree `e06fec9d1d7f24c1959e682da3f0f48774e41f5a`. No user Mac worktree was edited.

| Command / check | Exit / result |
|---|---|
| `python3 scripts/prepare_release_tests.py` with original implementation and alias tests | 1; controlled failing baseline, two errors / 16 tests |
| `python3 scripts/prepare_release_tests.py` with final fix and all new security cases | 0; 17/17 |
| `python3 scripts/release_integrity_tests.py` | 0; 10/10 |
| `python3 scripts/release_preflight_tests.py` | 0; 30/30 |
| `python3 scripts/package_store_screenshots_tests.py` | 0; 10/10 |
| `python3 scripts/release_generator_tests.py` | 0; 4/4 |
| `python3 scripts/ci_baseline_tests.py` | 0; 36/36 |
| `python3 scripts/release_schema_tests.py` | 0; 15/15 |
| `swift test --package-path packages/LightPlanCore` | 0; 280 XCTest tests, zero failures |
| Extracted exact `MapStyleObservation` and its pure XCTest method | 0; 1/1, no Apple UI API emulation |
| `swiftc -frontend -parse ios/LightPlanVisualUITests/VisualUITests.swift` | 0; syntax only, not Apple SDK typechecking |
| `python3 scripts/generate_project.py`, localization/metadata audit, inventory, Python syntax, YAML and `git diff --check` | Passed; generated App/Widget/project files unchanged |

The release-tool total is now **71** (formerly 64, plus seven preparation regressions). The native inventory adds one helper test: expected 41 target executions, comprising the same 38 real UI executions and three helpers; these are expected counts until Apple CI actually executes them. A combined shell test batch hit the local tool time budget after its first three successful commands; remaining commands were rerun individually and only their completed results are counted.

## Verification boundary and handoff

Current-source macOS tool regression, native `checks`, the repaired `iphone-visual` group and complete PR CI must pass before this repair is closed. The Linux helper test and parsing do not prove native UI success. Keep PR #7 as Draft while these are pending. The original Store-capture workflow's iPhone/iPad jobs now report success, but those artifacts were produced from the original source and were not reclassified as reviewed final submission screenshots here.

This patch changes release preparation, its tests, workflow platform coverage, one native test file and documentation only. App/Widget/Core business code, generated build files, pricing, astronomical precision, backup schema, signing, owner approvals and release gates are unchanged. `main` is not merged; no account, deployment, signing or upload operation is performed. Temporary read-only source transport is removed from the final tree. Historical failures remain available in Actions subject to artifact retention.
