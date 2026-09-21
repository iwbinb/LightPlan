# v3追加约束（优先阅读）

必须先读docs/v3，打开VISUAL_REVIEW.html了解实际参考。正式原生入口已接入Visual目录，不要继续使用旧prototype里的简化视觉。
保持摄影Hero、四卡、曲线、MapKit影像、自定义控制层、宽屏侧栏。禁止以WebView、静态效果图或假地图代替。不要把本次浏览器截图标为原生截图。完成视觉需运行capture_native.sh并保存当前源码对应的xcresult及逐屏对比。
本包引用的1024宽屏不是Duo硬件参数。缺少实际Duo模拟器/设备时只标记pending，不能用iPad代签。
如已经有用户改动，逐项合并新视觉组件，不要覆盖业务修复。所有原发布门槛依然生效。

---

# Instructions for Codex

## Authority and scope

The user's approved requirements, `docs/01_产品规格.md`, and `docs/10_风险与决策.md` are authoritative. ImageGen reference is visual direction only, never authoritative for time, geometry, dates, product completeness, device APIs or licensing. Do not redesign the product into a web wrapper, omit agreed languages, or remove features to mark tasks done.

## Before editing

Inspect repository status, toolchain, existing targets, recent user changes and signing configuration. Never overwrite an existing app. Make a non-destructive branch or working copy. Read `STATUS.md`, all numbered specs, task DAG and acceptance gates. Record actual commands/exit codes in `tests/reports/`.

## Implementation rules

- SwiftUI native app, Foundation-only testable core, one domain model. No hard-coded demonstration sun times in native production UI.
- All displayed astronomical instants must come from the selected `Place` and destination civil day. Never use 86400 seconds to advance a local calendar day.
- Validate decoded data, finite numbers, IANA timezones, archive versions and bounds. No force-unwrapping untrusted values. Do not overwrite corrupt storage with an empty archive.
- No claim of terrain/building shadows, weather, live clouds or guaranteed photographic quality. Reference directional diagram is not a geospatial map.
- Keep nine languages at parity through source catalogs; translate new keys in all languages. Mark native review pending until a human or suitable independent reviewer actually verifies it.
- StoreKit transaction verification is the entitlement authority. Do not ship a developer premium switch. Restore/read/export remain usable without premium. No own card form, wallet or secret billing service.
- iPhone/Duo/iPad layouts respond to actual container width, accessibility size and safe area, not device name or invented fold APIs. Keep selected place/date/instant/form drafts stable across width changes.
- Real map tiles must come through authorized platform APIs with attribution visible. Do not redistribute map screenshots as a faux live map or guess coordinate conversions.
- No login, analytics SDK, hosted AI or backend required for V1. No background continuous location tracking. Do not ask the user to manually create art; use provided original assets and native/procedural visuals.
- Use provided purchase ID and bundle IDs as configurable candidates only; owner must authorize actual identifiers. Never put tokens, certificates or personal data in the repository.
- Do not publish, create paid resources, submit agreements or deploy to a real account without explicit authorization.

## Definition of done

A task is done only if its acceptance checks have evidence. Syntax parsing is not typechecking; simulated purchasing is not StoreKit sandbox; browser render is not native UI QA. Update task status and `STATUS.md` with factual results. Preserve failed tests and unresolved blockers instead of deleting them.

When tool or account prerequisites block a stage, finish other unblocked local work and report the exact prerequisite. Do not ask product questions already answered here. Do not claim deferred work will run in the background.
