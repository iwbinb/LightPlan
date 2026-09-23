# LightPlan App Store 提交资料 — 2026-09-22

最新功能候选及验证边界见[摄影工具增强报告](../tests/reports/photography-tools-2026-09-22.md)；当前归档为本机开发签名，新增功能不自动满足正式提交门槛。

这是可继续执行的提交准备包，不代表已提交或获批。99 美元是产品价值目标，不是售价；用户已明确改为 **下载前付费**：在 App Store 购买应用后使用全部功能，无应用内购买、无订阅。

## 1. 当前事实与下一步

- 本地核心、原生测试及未签名 Release 归档已有证据，见 `STATUS.md` 的当前报告；最终提交必须绑定最终源码与构建。
- 当前收费方式为 `paid_upfront`；旧内购商品不再需要配置。须核验付费 App 的价格、销售地区与协议，以及 TestFlight 的完整功能和离线使用。
- 正式运营主体、支持邮箱、公开支持/隐私网址尚未确认。不要把 `hello@arenovo.com` 候选值当成已核验渠道。
- 2026-09-22 只读查询：GitHub 最新 run [35691258127](https://github.com/iwbinb/LightPlan/actions/runs/35691258127) 对应 `4132f7d068bc340886b3f2434935a912e8f2ac2b`，结果 failure；当时无开放 PR。本地后续修改尚未提交，这条历史结果既不能证明也不能否定后续源码。
- 本文、九语商店文案和验收模板均未写入 Apple 或 Cloudflare 账号。

### 名称核查更新

2026-09-22 已在 Apple 官方商店确认同类 [LightPlan – Photo Planner](https://apps.apple.com/us/app/lightplan-photo-planner/id1668588896)，Seller 为 Rivolu LLC，官网为 lightplan.app。所有者已明确它不是自己的产品，并决定准备独立名称。候选 LumaVantage / LumaBearing 尚待最终选择，正式上架名称和品牌核查保持 pending，不擅用该产品的域名或支持渠道，也不据此作商标法律结论。内部工程名暂保留，最终对外名称需在公开截图/元数据签收前确定。

## 2. 最少需要所有者提供的内容

| 输入/确认 | 用途 | 可以先完成的工作 |
|---|---|---|
| 对外运营主体、真实可接收的支持邮箱、批准使用的域名 | 隐私页、支持页、版权与应用内链接 | 网站内容、数据流清单、链接配置与发布检查 |
| 开发者账号中正确的 LightPlan 应用记录与 Team、候选 bundle/App Group ID 的最终确认 | 签名、Widget、商店分发 | 未签名归档、ID 一致性、原生流程验证 |
| 实际售价与销售地区 | App Store 付费应用配置 | 九语商店草案；不擅自写入 $99 或旧 $2.99 假设 |
| 付费协议、税务/银行、商家身份的真实状态，以及最后提交批准 | 收费及分发 | 提交材料、TestFlight 验收脚本、阻塞清单 |

不要在仓库中保存登录密码、证书、私钥、交易凭据或个人地址。账号核验记录仅保存脱敏结论；本地详细证据放在已忽略的 `tests/reports/local/`。所有者自己完成需要其身份的协议确认；没有确认前不把相应条目标为通过。

## 3. 付费下载与审核资料

收费配置为 **付费 App**，在 App Store Connect 的 Pricing and Availability 设置应用价格与销售地区；不创建或提交内购商品，不需要商品本地化、付费墙或“恢复内购”操作。App Store 处理下载付款，应用安装后直接提供全部功能；没有单独的 LightPlan 账号。99 美元只是价值目标，实际价格必须由所有者确认。Apple 在提交前要求设置应用价格，并要求有效的 Paid Apps Agreement 才能销售付费 App。[应用价格配置](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price)

`appstore/review_notes.md` 的最终说明应给出可复现路径：拒绝定位 → 手动地点 → 地图/构图 → 未来拍摄计划 → 提醒/备份/Widget；说明下载前购买后无需额外支付，以及几何模型不含天气/地形。九语 `metadata/*.json` 已改为完整付费下载表述，仍待实际功能验收与母语审校。不要保留“免费体验”“永久内购解锁”或旧商品 ID 的销售说明。

TestFlight 验收：新装无购买页即可完成全部功能；不依赖 `.storekit` 配置、商品加载或本地 premium 标记；离线可新建/编辑已知坐标与时区的计划、查看日月结果与备份；地图/搜索的联网边界说明准确。再验证升级旧本地数据、重启/前后台、提醒和 Widget。TestFlight 是测试分发，不作为真实扣费证据；生产付费状态由 App Store Connect 的已确认应用价格和销售配置记录证明。

付费协议、税务及银行状态在账号内核验。文档不替所有者接受条款。[协议说明](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements)

## 4. 商店截图与九语文案

当前 6.3 英寸 iPhone 与 11 英寸 iPad 的 QA 截图用于验收；另捕获符合主截图槽位的原生页面。以下尺寸截至 2026-09-22，应在上传前再次核验。[Apple 截图规范](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)

| 平台 | 本项目建议 | Apple 当前可接受主槽位（竖屏像素） |
|---|---|---|
| iPhone | Pro Max 原生捕获 | 6.9 英寸：1260×2736、1290×2796、1320×2868；也可用 6.5 英寸：1284×2778、1242×2688 |
| iPad | 13 英寸 iPad 原生捕获 | 2064×2752 或 2048×2732；应用支持 iPad，因此该槽位需要提供 |
| Duo | 保留硬件证据边界 | 官方仍说明上传槽位稍后开放；不造截图、不用 iPad 冒充 |

每个本地化和平台建议 5 张：今日光线、真实地图双点构图、机会比较、可恢复的拍摄计划、提醒/地点整理。只展示最终版本实际完成的能力；地图保留归属标识，不写“保证拍到”“天气预测”“地形遮挡”。截图价格如有显示必须来自正确地区，不能硬写售价。

截图清单记录实际 PNG 路径、SHA-256、源码 commit、原生来源、视觉审阅者和 `review_status`。提交检查要求九语 × iPhone/iPad 各 1–10 张且逐张通过审阅；九语逐张是本项目标准，不是 Apple 强制每种语言重复截图。可用模拟器原生截图，不能当成真机验收证据或用浏览器效果图替代。

九语 `appstore/metadata/*.json` 仍需语义/实际能力复核，随后填正式网址并把 `status` 改为 `approved_for_submission`。当前字数检查仅证明字段格式，并不证明完成上架材料。

## 5. 隐私、许可与设备验收

最终审核应用和 Widget 的 Privacy Manifest、权限、第三方依赖、素材来源与日志。当前使用本地计划/坐标及 Apple 地图/搜索；下载付款由 App Store 处理，没有自建账号或分析 SDK；不要据此宣称绝无联网。Apple 说明仅在设备处理的数据不算其隐私问卷中的“收集”，但实际外发数据和第三方行为必须另行核对。[隐私填写依据](https://developer.apple.com/app-store/app-privacy-details/)

隐私政策必须公开可访问，并在应用中有容易找到的链接；支持页与应用提供真实联系方式。正式页面需包含主体、数据用途/存储/分享/删除规则、Apple 服务边界和支持联系。[审核要求 1.5 / 5.1.1](https://developer.apple.com/app-store/review/guidelines/)

待按账号实际情况填写：版权、内容权利、年龄评级、出口合规、可访问性声明、销售地区及商家身份。若分发到欧盟，按账号身份确认 Apple 要求的商家公开资料；不让助手臆造个人地址或代做身份认定。[DSA 商家资料](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements)

`docs/PAID_ACCEPTANCE.md` 的真机闭环继续执行：定位拒绝/粗略定位、地图与方向、保存后重启、通知前台/后台/锁屏送达、跨时区、Widget、备份迁移与损坏恢复、升级后数据保留、小屏/大字/VoiceOver/减少动态、离线、冷启动/内存/耗电。科学精度和九语母语审校仍保留，不能以更多单元测试替代。Duo 不可用时只记录已执行自适应测试及缺失的硬件证据，由约定门槛审阅者判断该项的边界。

## 6. 最后提交检查

1. 完成功能和本地验收，得到可复核的最终源码。得到授权后提交/推送，验证该 commit 的 GitHub CI；旧绿灯不替代。
2. 复制 `appstore/submission_manifest.json` 至已忽略的 `tests/reports/local/submission_manifest.json`，填写最终 commit、各账号事项的脱敏证据及审阅者。可用本地审计配置保存不应公开的所有者信息，但生成器始终只读取已跟踪的 `appstore/release_config.json`：批准对外使用的支持邮箱、支持 URL、隐私 URL 必须同步至该文件，然后重新生成工程并重新归档。本地 `--config` 不会自动进入 App，公开联系字段本身不作为秘密。不要将含有自身 commit 的最终 manifest 再提交到该 commit。
3. 正式门槛 `codex/release_gates.json` 每项只有在执行验收后才填写 `passed`、现存非空证据文件和审阅者。修改门槛需按真实结果更新，不得删除或把 required 设为 false 绕过。
4. 使用当前接受的 Xcode/SDK 签名归档，检查最终 app/Widget、Bundle ID、App Group、隐私清单和无 `.storekit` 测试配置，完成 Organizer 验证及 TestFlight 回归。截至检查日，上传至少需 iOS/iPadOS 26 SDK。[SDK 要求](https://developer.apple.com/news/?id=ueeok6yw)
5. 开发阶段运行 `python3 scripts/release_preflight.py --report-only` 得到阻塞清单；该模式 exit 0 也不会把 `ready_for_submission` 改成 true。
6. 最终运行 `python3 scripts/release_preflight.py --config tests/reports/local/release_config.json --manifest tests/reports/local/submission_manifest.json --archive /实际路径/LightPlan.xcarchive`。默认任何缺失即非零退出：待验门槛、空证据/审阅者、占位或无效 URL、草稿资料、未确认账号事项、源码不匹配、缺失/尺寸不符截图。支持/隐私/邮箱逐项核对审计配置、已跟踪配置、生成的 Info.plist 和实际归档，防止资料通过而 App 仍带旧值。
7. 必须提供真实签名归档，并在本地 manifest 增加下面的 `archive` 记录。`path` 仅在未传 `--archive` 时使用，必须相对仓库；命令参数可指向仓库外的实际归档。源码 commit 依据构建记录填写，不从归档日期推断；两个 SHA-256 来自最终签名归档中实际可执行文件。缺归档、错误哈希、错误 Bundle/App Group、缺失或与源码不一致的 astronomia MIT 许可证、混入 `.storekit`、代码签名校验失败均阻止通过。
8. 检查器只做本地完整性、一致性及签名完整性检查，不联网验证邮箱/网站，不证明记录真实性，也不替代 Apple 分发资格、描述文件、Organizer 上传验证或审核。账号状态、TestFlight 全功能和离线验收、网页可达性和最后提交必须有独立证据；具体材料齐全后由所有者批准最后提交。

本地 manifest 的归档字段示例（填写实际值，不能保留示例字符串）：

```json
"archive": {
  "path": "tests/reports/local/LightPlan.xcarchive",
  "source_commit": "构建源码的完整40位commit",
  "app_executable_sha256": "Products/Applications/LightPlan.app/LightPlan的SHA-256",
  "widget_executable_sha256": "Products/Applications/LightPlan.app/PlugIns/LightPlanWidget.appex/LightPlanWidget的SHA-256"
}
```

上述 SHA-256 绑定当前二进制，`distribution_validation` 的人工证据仍应记录该归档的实际 Organizer/TestFlight 验收；仅把其状态写成 passed 不会使缺失或不一致的二进制通过。

检查器的回归测试：`python3 scripts/release_preflight_tests.py`。备份文档契约测试：在开发环境安装 `appstore/release_validation_requirements.txt` 后运行 `python3 scripts/release_schema_tests.py`；这项仅开发验证依赖，不链接或打包到 iOS 应用。

备份契约现已在 `docs/archive.schema.json` 描述读 v1/v2、写 v2、构图快照和可选笔记；同一天/时区/方向有效性仍由原生核心验证。旧 App 不能读取新格式，不对它作反向兼容承诺。
