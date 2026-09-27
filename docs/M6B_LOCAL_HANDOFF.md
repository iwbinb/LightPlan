# M6-B · Mac / Codex 本地接管

目标：把 M6-A 准备好的工程变成有设备与账号证据的发布候选。不是新的功能开发阶段。未经授权，不提交 App Store、发布网站、接受协议或修改价格。

## 1. 保留现场并确定源码

先读 `AGENTS.md`、`STATUS.md`、`docs/M6_RELEASE_READINESS.md`，查看 `git status --short`、当前分支和最近提交。不要 reset、清除数据或覆盖用户本机更改。使用用户选择的候选 commit，核对相应 GitHub CI；保存 `git rev-parse HEAD`、`git rev-parse HEAD^{tree}`、`xcodebuild -version` 与实际设备/SDK。

确认已安装所需 Xcode、模拟器和真实设备。记录当前账号 Team，但不要在公开仓库写入证书、描述文件、Apple ID 或个人地址。所有原始资料存 `tests/reports/local/`。

## 2. 获取缺失决定，不沿用候选假设

正式名称及各语言显示名；合法运营主体；真实支持邮箱、支持/隐私域名；Bundle/App Group 注册；实际售价和销售地区。`hello@arenovo.com` 和相邻 Lumen 产品网址不能仅因历史项目使用过就视为本 App 的批准值。名称/商标审查和后台售价仍是所有者决定，不由工具生成。

把批准的公开构建/联系字段更新到 `appstore/release_config.json`，同步九语元数据、InfoPlist 本地化名称及网站内容，运行生成器后检查 diff。配置更改属于新源码，提交后重跑 CI、重建归档和截图，不给旧截图改 commit 标签。

## 3. 建立最终源码本地验收目录

```sh
python3 scripts/prepare_release.py --output tests/reports/local/release-candidate-01
```

仅在干净 Git 工作区执行。换了 commit 就建立新目录，旧证据不删除。新目录里所有 gate/账号审批均为 pending；按实际完成情况填写 evidence 文件、reviewer、status，原始日志脱敏后再引用。证据路径相对仓库且不能为空；签收当前 commit，不给过去结果改名。

## 4. 真实设备验收清单

| 任务 | 操作与通过条件 | 证据 |
|---|---|---|
| 首次启动/定位 | 新安装不抢先索权；拒绝和粗略定位可手动设置地点 | 设备/系统记录、录屏 |
| 日期/构图 | 改日期、日月、时区、机位后时间一致；横竖屏草稿保留 | 流程录屏、选定时间 |
| 通知 | 建未来计划，前台/后台/锁屏分别真实收到；编辑/关闭/删除后无旧通知 | 实际送达时间和系统队列，不只模拟器截图 |
| 断网/Widget | 关闭网络，已知坐标计算、保存/重启/备份可用；地图联网边界准确；组件数据和过期状态正确 | 断网操作和桌面组件录屏 |
| 数据 | 先导出备份再验证旧版本升级、导入冲突、损坏恢复；不得破坏用户唯一数据 | 备份校验值、恢复前后条目 |
| 可访问性 | 真机 VoiceOver、最大字号、深色、减少动态；各关键入口可操作 | 检查路径和失败/修复记录 |
| 宽屏/系统 | iPad 旋转、分屏及最低支持系统；没有对应设备就保留 pending | 设备型号、系统和交互录像 |
| 性能 | 指定设备、样本数、冷/热启动条件；测冷启动 P95、拖动、内存/能耗 | Instruments 原始记录；不以核心微基准代替 |

原规格目标：最低支持设备冷启动 P95 ≤2.5s、缓存地点首页结果 P95 ≤500ms。记录样本和实验条件，不能将目标当实测。Duo 没有设备就保持未验证，iPad 不能代签。

## 5. 商店资料、归档与最后预检

按 `M6_RELEASE_READINESS.md` 捕获 iPhone/iPad 主槽位原生图片，逐图确认名称、功能、署名、九语言和内容；将真正签收的条目复制到本地 submission manifest。不得把 QA 拼图或生成效果图当商店实机图。不要跳过缺少的地区与语言。

在正确 Team 下构建并验证分发归档，App/Widget 使用一致版本和批准的共享组。未签名的 CI archive 与开发签名 archive 不等于分发归档。按 Apple 当前工具流程做 Organizer 验证与 TestFlight，保存脱敏回执；预检检查实际签名权限，`get-task-allow` 必须为 false。仅代码签名完整性不替代描述文件、分发资格或 TestFlight 实测。

填写实际归档路径、源 commit、两个可执行文件的 SHA-256。所有者自己完成付费协议/税务/银行/商家身份等事项。实际签收前，不把 `release_ready` 或账号字段设成 true。

```sh
python3 scripts/release_preflight.py \
  --config tests/reports/local/release-candidate-01/release_config.json \
  --manifest tests/reports/local/release-candidate-01/submission_manifest.json \
  --gates tests/reports/local/release-candidate-01/release_gates.json \
  --archive /实际路径/LightPlan.xcarchive
```

默认非零退出表示仍有阻塞；`--report-only` 的 exit 0 仅为生成报告，不能作提交批准。清单/截图/归档必须绑定同一最终 commit。即使报告全绿，最后上传或提交仍需所有者明确批准。
