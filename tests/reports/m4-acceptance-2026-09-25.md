# M4 外拍与数据可靠性：最终自动化验收 — 2026-09-25

## 结论与源码范围

**M4 开发及自动化验收完成；此前外拍专项失败已关闭。当前是 dev → main 合并候选，不是 App Store 发布批准。**

- 已合并的 M3 基线：`3357d351df3a89b3cdfc1a1410e96f66c6fdce0c`。
- 最终验证源码：`ae12c56b13e9a450949817497ef576a9f7ba30bd`，树 `c47fd29f2cd3651c8972dcf9eac84913cf6fac32`。
- [Native app verification #58](https://github.com/iwbinb/LightPlan/actions/runs/36110477855)，attempt 1；2026-09-25 08:54:12 UTC 完成，**10/10 组成功**。
- 本次交接只补充验收文档和 STATUS，不修改已测的 App、Core、UI 测试或 CI，不重新执行 App。PR 创建后的合并引用检查独立执行，不能用上述 dev 结果代签。

原始设计、事务/导入/提醒行为及早期本地结果保留在 [M4 实现记录](m4-reliability-2026-09-24.md)。其中 266 项和原生 pending 是当时的历史状态；最后增加取消队列时的版本校验回归后，完整核心为 267 项。

## 最终实际执行

| 检查组 | 结果 | Artifact ID |
|---|---|---|
| checks | 核心 267、CI 自测 36、Debug、未签名 Release 及工具回归通过 | 10852792807 |
| iPhone 外拍专项 | 3/3 | 10853017584 |
| iPhone M3 工作流 | 4/4 | 10853866378 |
| iPhone 产品流程 | 9/9 | 10853731967 |
| iPhone 规划流程 | 6/6 | 10853269727 |
| iPhone 基础视觉 | 5/5 | 10854016943 |
| iPhone 扩展视觉 | 3/3，含既有滚动预算辅助逻辑回归 | 10854740898 |
| iPhone 扩展最大字号 | 2/2 | 10854862039 |
| iPhone 基础最大字号 | 2/2 | 10855036771 |
| iPad 旋转 | 1/1 | 10854786860 |

原生目标共 **35 次执行：34 次实际 UI 执行 + 1 项辅助逻辑回归**。全部 34 个 iPhone 方法各选择一次，iPad 另执行原有旋转用例。所有原生结果包均为零失败、零跳过、零预期失败；没有删除用例、重试到通过或使用 continue-on-error。

完整核心 267/267 包括既有 224 项和 M4 新增 43 项：DataReliabilityTests 18、PlanMutationTests 10、ReminderReliabilityTests 15。其他检查：发布预检工具 24/24、截图打包工具 10/10、schema 15/15；本地化 389 键 × 9 语言 = 3501 条译文，零完整性错误；工程生成无漂移。Debug 日志为 BUILD SUCCEEDED，Release 日志为 ARCHIVE SUCCEEDED；归档没有 StoreKit fixture。工具单测不等于正式发布预检 ready。

实际环境：macOS 15.7.9 arm64、Xcode 26.3 (17C529)、Apple Swift 6.2.4、iOS 26.2 Simulator。通知队列属于模拟器操作系统，不是实体设备通知送达证明。

## 验收项与证据对应

| 验收项 | 证据和范围 |
|---|---|
| 保存后重启恢复 | `testManualTimeAndNotesPersistThroughSaveRelaunchAndFieldMode`：实际保存手动时刻、备注，重启后读取，进入现场模式，再恢复地图时刻；不是只检查编辑器 |
| 提醒取消及重启 | `testDisablingSavedReminderClearsSystemQueueAndSurvivesRelaunch`：开启并保存、检查系统队列，再编辑关闭、保存并重启，核对持久化关闭状态及待发数量 0 |
| 编辑/复制不产生重复提醒 | `testEditedReminderStaysSingleAndDuplicateDoesNotCopyIt`：原系统请求保持单一，复制保留数据但不复制提醒意图 |
| 写入失败不谎报成功 | DataReliabilityTests：回读、回滚、首次保存、备份失败及回滚失败；保留损坏和迁移原件；不等同真实断电或磁盘满测试 |
| 旧编辑与导入冲突 | PlanMutationTests 和 DataReliabilityTests：全记录版本校验、删除不复活、旧预览拒绝、保留两份、超限导入及 legacy v1；真实文件提供商仍单独验证 |
| 提醒并发/失败保护 | ReminderReliabilityTests：过期请求、权限、容量、未知记录、失败替换、保存意图跨 await 校验及延迟取消不删除新版本 |
| 离线读取边界 | 核心与本地文件恢复不需要网络；本轮没有进行实体设备断网、首次解锁或锁屏验证，不把模拟器联网运行描述为断网验收 |

## 已关闭的失败与修复依据

1. **Run 56，源码 `899893a`：提醒开关没有被真正关闭。** 保留的失败用例等待 `settings-reminder-count == 0` 超时。后续修复提交 `11de7a5` 记录了原截图/录屏的根因：点击 Toggle 行中央仍保持开启。测试改为在已确认的英文/LTR 可见框内操作尾部原生开关，保存前必须断言真实 value 为关闭；保留最终零队列断言，新增从已开启计划编辑关闭并重启的回归。没有测试侧清空通知队列或伪造通知结果。
2. **Run 57，源码 `11de7a5`：导航瞬间读取了已消失的 ScrollView。** 原有两项外拍流程通过，新增关闭/重启流程已验证队列 1 → 0，但重新打开详情时在检查 exists 之前读取了消失容器的 frame。`ae12c56` 等待明确目标页面，并先检查容器存在性，再查询几何及子控件；未增加超时或弱化开关、持久化和系统队列断言。
3. **Run 58，源码 `ae12c56`：全部三项外拍及其余九组通过。** 使用同一完整源码运行，不从不同失败轮次拼接一份通过报告。原始失败及修复提交保留在历史中，临时诊断工作流不在最终变更树内。

## 原始产物核验与截图

2026-09-25 逐一下载并读取十份 run-58 ZIP，核对 API 公布的 SHA-256、`source-commit.txt`、`runner.json`、`commands.tsv`、`selected-tests.txt`、`test-summary.json` 和完整 iPhone 清单；全部命令退出码和 runner 退出码为 0，无超时或中断。哈希、任务编号和逐项选择器见 [机器可读清单](m4-native-verification-2026-09-25.json)。保留期可能使远程产物以后过期，报告保留引用与摘要，不声称远程 ZIP 永久可下载。

抽查了当前外拍截图：关闭开关、已保存关闭状态、系统待发数量 0、保存的时间/备注、现场倒计时、地图恢复与复制。系统状态栏处可见内容叠加、浮动 Tab 背后的内容和重复提醒说明等视觉问题仍属后续视觉收尾；这些截图不是最终商店素材，也不构成全应用无裁切证明。

## 复现

```sh
swift test --package-path packages/LightPlanCore
python3 scripts/ci_baseline_tests.py
python3 scripts/localization_audit.py
bash scripts/ci_native.sh checks
bash scripts/ci_native.sh iphone-field
bash scripts/ci_native.sh all
```

在与上述匹配的 Apple 工具链和模拟器上复现原生命令。Linux 的语法解析或核心测试不替代 Apple 编译和 UI 执行。

## 保留的独立发布门槛

本阶段不修改 schema 2/legacy v1 兼容性、星历系数、精度阈值、九语言、买断模式、签名或账号。事务仍是 AppState 单写者设计，不承诺跨进程数据库语义和电源故障下硬件持久性。实体设备通知送达、离线/锁屏/首次解锁、真实文件提供商、Widget、最低系统、VoiceOver、母语审校、性能与 M5 视觉收尾、正式签名和商店配置仍须各自验证。未开始 M5，未合并 main，未启用自动合并，未发布。
