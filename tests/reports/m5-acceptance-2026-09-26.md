# M5 最终验收与合并交接 — 2026-09-26

## 结论与源码边界

M5「性能与界面细节」的实现、最终源码自动回归和本轮限定范围的原生截图复核已完成，可将 PR #6 转为正式待审的合并候选。此记录不执行合并、不开始 M6，也不表示 App Store-ready。

- 源码：`9fada0d5bb1940f4c160ae181e10e1a2919ce9c6`，树：`f0a4cce900a15b3a5ac7dab9993bf99d4950ddfb`。
- 基线：已合并 M4 的 `133d833d3b2a3469b8345662a3f20c2ec6079403`。
- [push 原生 #68](https://github.com/iwbinb/LightPlan/actions/runs/36218053082)：attempt 1，11/11 组通过，2026-09-26 05:41:00 UTC 完成。
- [PR 原生 #69](https://github.com/iwbinb/LightPlan/actions/runs/36218055216)：attempt 1，11/11 组通过，2026-09-26 05:38:04 UTC 完成；实际检出合并引用 `209e303bbb9cec43eea7cb95e72c666efa236482`。
- [PR 核心 #17](https://github.com/iwbinb/LightPlan/actions/runs/36218055271)：通过。

本次收尾只写文档，不改 App、Core、UI 测试、CI、签名和收费设置，也没有重新执行 App。文档提交触发的最新 PR 检查仍须独立通过，不能把上述历史运行改写成新提交的执行结果。实时合并状态以 PR 页面为准。

## 自动验收结果

环境为 macOS 15.7.9 arm64、Xcode 26.3 / Swift 6.2.4、iOS 26.2 Simulator；设备为 iPhone 17 Pro 和 iPad Pro 11-inch (M4)。

| 分组或检查 | 最终源码结果 |
|---|---:|
| 完整 Foundation 核心 | 280/280，含 M5 新增 13 项 |
| iphone-product | 11/11：10 次 UI + 1 项就绪辅助逻辑 |
| iphone-polish | 3/3 |
| iphone-field | 3/3 |
| iphone-workflow | 4/4 |
| iphone-planning | 6/6 |
| iphone-visual | 5/5 |
| iphone-rich-visual | 3/3：2 次 UI + 1 项既有滚动辅助逻辑 |
| iphone-rich-accessibility | 2/2 |
| iphone-accessibility | 2/2 |
| ipad-rotation | 1/1 |
| CI 辅助 / 发布预检工具 / 截图打包工具 / schema | 36/36、24/24、10/10、15/15 |
| Debug 模拟器构建 / 未签名 Release 归档 | BUILD SUCCEEDED / ARCHIVE SUCCEEDED |
| 工程生成、metadata、本地化完整性 | 通过；389 键、9 语言、3501 条译文，零缺失 |

原生目标合计 **40 次执行 = 38 次真实 UI + 2 项辅助逻辑**，失败、跳过、预期失败均为零。全部 39 个 iPhone 方法各执行一次，iPad 另外执行既有旋转方法。所有原有用例与精度门槛保留，未从不同失败轮次拼接成功结果。

已实际下载并读取 #68 全部十一份 ZIP，逐份核对 SHA-256、`source-commit.txt`、runner 与 `commands.tsv` 退出码、`selected-tests.txt`、XCTest 摘要和原始日志中的通过方法集合。#69 的十一组状态独立查询；其中 checks/product 两份 ZIP 另外下载并核对其合并引用、哈希、退出码及产品全部十一项。未宣称下载了其余九份 #69 ZIP。详见 [机器可读清单](m5-native-verification-2026-09-26.json)。

## 原失败用例的关闭依据

- run 61 的最大字号画幅按钮标识被父容器覆盖，`aa492b7` 将标题与两个按钮的标识分开。最终 polish 三项均通过，包含实际点击和选中状态检查。
- run 62 在真正进入搜索前没有展开构图面板。`497d904` 明确既有 44pt 点击区域和展开状态，增加一次边缘点击用例。旧录屏不足以证明唯一的底层漏点击原因；不将它描述为已确认的天文计算错误。
- run 65 卡在上次新增的点击前稳定性检查：重复实时查询耗尽 10 秒等待。`9fada0d` 改用同一公开界面快照读取几何，保留 0.3 秒稳定期、最终实时可点击校验、一次点击及全部后续产品断言；10 秒超时不变。
- #68 产品组的原失败流程、边缘点击、新增辅助回归全部通过；两份就绪轨迹分别在约 **2.13 秒、2.29 秒**达到稳定且可点击。#69 产品组也独立通过。这是测试辅助逻辑耗时，不是 App 冷启动 P95。

保留 [入口修复证据](m5-composition-entry-repair-2026-09-26.md) 与 [就绪检查修复证据](m5-readiness-polling-repair-2026-09-26.md)。没有删除失败历史、跳过用例、提高超时、重试点击、注入页面状态或放宽计算精度。

## 原生截图复核

本次审阅 #68 五类产物内全部 PNG，共 **56 张**：polish 10、基础视觉 32、扩展大字号 6、产品 6、iPad 旋转 2。截图由对应源码的原生测试导出；内部缩略拼图只用于检查，未作为生成的 App 画面或商店截图。

检查内容包括德语/泰语完整标题、画幅横竖选项与前置外拍入口；1000 条计划查询和恢复；九语言核心页面；构图展开、保存后地图恢复、实际 MapKit 图层，以及 iPad 深色横竖屏。横屏图片按原始方向信息校正后复核。所审阅画面未发现阻断这些 M5 操作的新增标题截断或控件缺失，相关可点击性由原生用例另行验证。

复核不是全量像素差异认证，也不是母语或 VoiceOver 验收。滚动后的正文可出现在系统玻璃工具栏后方；这些截取状态不应直接作为最终商店素材。对比度的设备级量化、实际分屏和全部页面的人工可用性评估仍保留为发布检查。原始参考 HTML 未在本次工作副本中提供，因此不声称完成其逐像素比对。

## 性能证据与适用范围

[同机 Release 对照产物](https://github.com/iwbinb/LightPlan/actions/runs/36207248777/artifacts/10894736288) 的 ZIP SHA-256 为 `7367c851efe49d3410fa315f14c03a91668f6f8e1138c10cfb7541a8e192223b`，本次已重新核对。M4 `133d833` 与 M5 `9e72040` 使用同一 harness、Apple M1 Virtual / Xcode 26.3 / Swift 6.2.4，每项一次预热后测量五次，计时不包含编译。仓库比较确认从该 M5 候选到最终 `9fada0d` 没有 Core 或 benchmark harness 改动。

| 固定场景 | M4 中位数 | M5 中位数 |
|---|---:|---:|
| 90 日太阳搜索，无匹配窗口的固定场景 | 752.76 ms | 555.65 ms |
| 90 日月亮搜索 | 625.58 ms | 564.92 ms |
| 5000 条计划全部分组 | 26.01 ms | 17.39 ms |
| 5000 条计划文字查询 | 24.14 ms | 17.53 ms |

四项结果指纹逐项一致。太阳场景指纹只有已搜 90 天/未截断标记，没有匹配窗口，不能仅凭此证明所有有结果场景的精度或速度；另有原有精度测试及缓存/非缓存回归提供正确性证据。月亮算法没有修改，其耗时差异不能全部归因于优化。实验采用先基线、后候选的单机顺序，样本有波动；#68 自身又保存了一次独立 benchmark，不将跨机器时差当成回归或提速证明。微基准不能换算成真机启动、帧率、内存或能耗保证。

## 复现与交接

```sh
swift test --package-path packages/LightPlanCore
python3 scripts/ci_baseline_tests.py
python3 scripts/localization_audit.py
bash scripts/benchmark_core.sh build/core-performance.json 5
bash scripts/ci_native.sh checks
bash scripts/ci_native.sh iphone-product
bash scripts/ci_native.sh iphone-polish
bash scripts/ci_native.sh all
```

本轮收尾核对上述已执行运行的日志和产物，不把复现命令列表当作又执行了一次。原始 Actions 产物有保留期限，#68/#69 的文件预计于 2026-10-10 到期；仓库内的哈希和摘要不是原始 xcresult 的永久备份。

`STATUS.md` 更新为当前结论；其原全文使用相同 Git blob 原样保存至根目录 `STATUS_HISTORY_2026-09-26.md`，保持历史和相对链接。新增本报告及 JSON 清单，不更改原实施/失败报告。无未解决 review thread 是查询时状态，不代表已有独立审查批准。

实体通知送达、Widget、断网/锁屏/文件提供商、最低系统、真实分屏、VoiceOver、母语审校、真机启动/帧率/内存/能耗、最终商店素材、账号和正式签名均继续作为 M6/发布门槛。备份 schema 2/旧 v1、九语言、买断模式和天文精度保持不变。
