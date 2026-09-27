# M6-A：仓库发布准备与边界

M6-A 提供可复现的发布配置、预检、原生截图入口和本地交接工具。它不签收 M6-B 的设备/账号事项，不表示已具备 App Store 提交资格。

## 统一配置

`appstore/release_config.json` 是公开版本、构建号、候选名称、Bundle/App Group 和最低运行版本的生成输入。当前仍为 1.0.0 (1)、iOS 17.0，未改变既有产品行为。实际售价、销售地区、名称和运营信息尚未批准；原候选不能当作最终上架身份。

修改批准的配置后运行 `python3 scripts/generate_project.py`，检查并提交生成文件。不要只修改 Xcode 工程，下一次生成会覆盖手改。`ios/Config/Local.xcconfig` 仅存本机 Team 等覆盖；不上传证书、描述文件、私钥、Apple ID 或账号页面原件。最终归档的真实标识和签名权限必须与批准配置相符。

## 新增检查

发布预检保留 G01–G20、九种语言和现有账号检查。新增 PNG 完整结构/CRC/解压长度校验、解压资源上限，拒绝只有尺寸头的假文件；这不是视觉质量或原生来源认证。归档逐项核对 App/Widget 版本、最低运行版本、候选显示名、设备 SDK、源隐私清单与实际签名 entitlements。开发签名或 `get-task-allow=true` 不作为分发通过。

`--gates` 允许读取当前源码绑定的本地 gate ledger，避免不断提交最终验收证据导致 HEAD 再次变化。历史 gate 记录原样保留；本地新 ledger 将所有验收重置为 pending。不能通过删除必需项或复制历史通过状态来获得绿灯。

## 可运行交接入口

在干净、已提交的工作区执行：

```sh
python3 scripts/prepare_release.py --output tests/reports/local/release-candidate-01
```

输出独立的 `release_config.json`、`release_gates.json`、`submission_manifest.json`、阻塞清单、源码/tree/hash 清单与参考文档/九语言元数据。不会覆盖同名目录，不复制本地签名信息，不更改已跟踪的门槛。不干净的工作区或越界/符号链接输出会被拒绝。`prepared=true` 仅表示交接目录生成成功；`ready_for_submission` 必须仍为 false。

## 商店截图

已有 M5 截图是功能 QA，不擅自改尺寸或改来源来填商店槽位。新增原生捕获入口使用独立、可删除的测试模拟器，不清除用户已有设备；仍调用真实 XCTest、SwiftUI/MapKit：

```sh
bash scripts/capture_store_screenshots.sh iphone build/store-iphone
bash scripts/capture_store_screenshots.sh ipad build/store-ipad
python3 scripts/package_store_screenshots.py \
  --iphone-xcresult build/store-iphone/native.xcresult \
  --ipad-xcresult build/store-ipad/native.xcresult \
  --output tests/reports/local/store-draft-01 \
  --source-commit "$(git rev-parse HEAD)" \
  --source-note 'Captured from this committed source on the recorded Xcode toolchain'
```

默认选择已安装的 iPhone 17 Pro Max 和 iPad Pro 13-inch (M4) 类型。缺少任一类型或 runtime 就明确失败，不用其他尺寸缩放冒充。允许 `LIGHTPLAN_CAPTURE_DEVICE` 指定本机实际可用的同类主槽位型号，打包器仍校验像素尺寸。本轮在该 workflow 文件变更时自动试跑；后续也可在 Actions 手动运行 `Native Store screenshot drafts`；它仅产生原始截图草稿和 xcresult，不上传到 Apple，不将待审图片自动批准。

54 张草稿的基础集合为九语 × iPhone/iPad × Today/Map/Plan。原始图片保持字节不变；最终可扩充至每组 1–10 张，需逐张复核真实页面、地图署名、名称、文案和像素。批准品牌/网址后必须在最终源码重新捕获。所有者未选择最终名称之前，截图不能算正式提交素材。

## 资料检查矩阵

| 材料 | 仓库内结果 | 最终签收责任 |
|---|---|---|
| 九语元数据 | 保留完整九语与长度检查；仍为草稿 | 正式名称/链接、母语审校与实际能力核对 |
| 审核说明 | 包含无登录/无内购、手动地点、构图、计划与离线边界 | 按最终构建重走路径 |
| 隐私与许可 | App/Widget 隐私文件、MIT 文件及署名纳入一致性检查 | Apple 问卷、真实外发行为、公开页面与运营主体 |
| 截图 | 新增主槽位真实原生捕获/草稿打包入口 | 真实执行、逐张视觉和语言签收 |
| 发布配置 | 统一输入、生成、归档比对 | Team、标识注册、定价、地区、协议 |
| 设备报告 | 见 M6-B 可执行检查表 | 真实 iPhone/iPad、最低系统、通知和性能 |

## 官方规则核查（2026-09-27）

- [Apple SDK 要求](https://developer.apple.com/news/upcoming-requirements/)：2026-04-28 起上传需 Xcode 26 或更高及 iOS/iPadOS 26 SDK。最低运行版本与构建 SDK 是不同条件；上传当天再次确认。
- [Apple 截图尺寸](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)：iPhone 主槽位可采用 6.9/6.5 英寸官方尺寸，iPad 使用 13 英寸槽位；当前允许值保留在 `release_preflight.SCREENSHOT_SIZES`。九语逐张签收是本项目标准，不声称 Apple 强制所有语言单独上传。
- [App Review Guidelines 2.3](https://developer.apple.com/app-store/review/guidelines/)：商店资料应真实反映功能，截图展示使用中的 App；不要在名称、副标题和截图硬写未批准售价。

这些链接不替代开发者账号验证、法律判断或 App Review。没有部署 Cloudflare 网站、接受协议、设置价格、上传 TestFlight、发布标签或提交 App Store。
