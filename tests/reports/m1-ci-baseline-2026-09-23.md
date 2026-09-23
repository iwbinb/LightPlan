# M1 — 稳定测试基线（2026-09-23）

**实现与脚本自测已完成；原生验收仍受 GitHub runner 启动失败阻塞。不得将本报告理解为 M1 全绿、App Store-ready 或真机验收通过。**

## 范围与源码

从 `dev` 的 `d65d8d942e41e9c8c8f7d24f84691b565f0e66fd` 开始。首个实现提交为 `f3a899d0650d20844767c4b61f1c7517eb787c42`。本报告所在的后续提交仅补充本地 all 入口的错误传播、两项自测及证据文档。所有写入只针对 dev，使用非强制快进；没有修改 main、生产 Swift 文件、UI 素材、功能、定价、签名或账号设置。

## 已实现

| 项目 | 处理 |
|---|---|
| 任务拆分 | checks、iPhone 产品/规划/基础视觉/扩展视觉/辅助功能、iPad 旋转，共七组；最多三个并行，一个失败不取消其他组 |
| 完整覆盖 | 从实际 XCTest 源码生成明确选择器；五个 iPhone 测试类各执行一次，保留原有 iPad 旋转；新增/遗漏测试类、重复方法、空选择器均拒绝 |
| 防止假通过 | xcodebuild 必须成功；xcresult 通过数必须等于选择数，失败和跳过均为零；未知结果格式也失败 |
| 有界运行 | CI 每组内部 1800 秒截止，超时退出 124；记录退出码、时长、提交及原始日志，并清理进程组；任务总限时仍为 40 分钟，给上传留出余量 |
| 失败证据 | 上传条件改为 always，设置独立上传时限和分组/提交/attempt 产物名；保留 xcresult、截图、命令退出码和设备信息；没有用重试或 continue-on-error 掩盖失败 |
| 环境一致性 | 保留 macos-15、Xcode 26.3、iOS 26、固定已知 GPS 坐标和关闭 XCTest 并行；按数值而不是字典序选择 runtime |
| 原生诊断 | 工具支持时停用可选的重型 test diagnostics；不关闭 XCTest 断言、结果包或显式截图；实际参数写入证据 |
| 本地入口 | 原来的 bash scripts/ci_native.sh 仍能运行完整检查；阶段发现失败/空清单会返回非零；也可单独运行分组 |

`always()` 不能保证在 runner 根本未分配或被强制销毁时获得产物；本次远端失败即发生在任何步骤之前。

## 本轮实际执行

执行环境为 Linux，没有 Xcode。本轮没有在本环境执行 iOS 编译、Swift 核心套件、模拟器 UI 或实体设备测试。

| 命令/检查 | 实际结果 |
|---|---|
| `python3 scripts/ci_baseline_tests.py` | 最终 33 项通过，0 失败；CI 编排的标准库自测，不是 App 测试 |
| `bash -n scripts/ci_native.sh` | 退出 0；仅 Shell 语法 |
| Python 编译检查 | 退出 0；仅 Python 语法 |
| 工作流 YAML 解析与矩阵检查 | 通过；七组与 CLI 清单一致 |
| 首个实现的 GitHub push | 成功，dev 非强制更新到 f3a899d |
| GitHub 原生工作流 | 已触发，但 runner 未启动，没有执行编译或测试 |

保留首次自测失败的说明：最初一个 0.3 秒测试包含解释器站点初始化，子进程尚未输出就触发截止。测试子进程改用 `python -S -u`，并给予 1 秒启动预算，仍严格断言退出 124、保留输出和终止进程。生产 CI 的 1800 秒截止没有放宽。此后 31 项自测连续通过；追加 all 入口两项检查后，最终 33 项通过。

## 远端阻塞证据

运行 `35839123805`，提交 `f3a899d0650d20844767c4b61f1c7517eb787c42`，GitHub 结论为 failure。

七个任务的 `runner_id` 均为 0，`runner_name` 为空，`steps` 均为空。示例：checks 任务 `107109690618`。获取该任务日志返回 `BlobNotFound`，并非一个可供诊断的编译/断言失败日志。现有连接接口未返回具体的 runner 拒绝原因；**不据此断言是额度耗尽、账单或代码错误**。

在 runner 恢复前不重复触发相同检查，不改付费设置，不将私有库改为公开，不把失败状态伪造为成功。最终候选仍需要自己的有效原生结果。本次后续提交使用 `[skip ci]`，仅为避免在 runner 未分配的状态下重复排队；它不代表验证通过。恢复后须针对最终 dev 重新执行工作流。

## 复现与验收

有 Xcode 26.3 / 对应 iOS 26 模拟器的 Mac 或恢复后的 Actions 可运行同一脚本。针对一个分组，使用有界入口：

```sh
python3 scripts/ci_baseline.py stages
python3 scripts/ci_baseline.py run --seconds 1800 \
  --log build/evidence/iphone-product/runner.log \
  -- bash scripts/ci_native.sh iphone-product
```

日志包装器拒绝覆盖已有 runner.log。重新运行前将既有 `build/evidence` 移至其他目录保存，不删除失败证据。完整本地入口 `bash scripts/ci_native.sh` 是串行的；Actions 按矩阵独立运行。单组脚本本身不设置全程截止，上述包装器才提供它。

原生验收要求：checks 中核心测试、Debug、未签名 Release 归档和现有发布工具回归全部通过；五组 iPhone 的实际测试数与源码选择器一致，iPad 旋转通过；七份对应提交的证据可读取。原生全绿之前，不开始 M2，也不标记 M1 完整验收通过。

真机通知送达、GPS 精度、Widget、VoiceOver、母语审校、正式签名与商店提交继续是独立门槛。
