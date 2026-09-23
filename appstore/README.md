# 商店材料

2026-09-22用户确认采用下载前付费（paid_upfront）：应用安装后全部功能可用，不创建内购商品，不提供付费墙/订阅/恢复内购。实际应用售价与销售地区由所有者确认；99美元是价值目标，不是售价。

`metadata/`包含九语名称/副标题/推广文案/描述/关键词草案；没有自动提交。所有文案要在功能实际完成后复核，禁止宣传未完成计划编辑、Widget或离线功能。名称、字符限制、词组与地区表达需要在App Store Connect和母语审校中再确认。

`scripts/appstore_metadata_audit.py` 会在 CI 中检查九语元数据的必填文本、名称/副标题/推广文案/描述长度，以及关键词 100-byte 限制；超限会直接阻止 CI。候选品牌、母语审校和最终 App Store Connect 字段仍需发布前人工确认。

截图由完成后的真实iOS运行界面生成：今日、地图拖时、拍摄计划、宽屏工作台、九语支持。原型或ImageGen图不得冒充原生截图。最终尺寸与设备要求按当时官方商店规范获取；不要假定Duo截图槽位或未确认尺寸。

正式隐私/支持URL和运营主体仍为null；见release_config.json。原生代码中的开发状态提示必须在完成真实配置后替换。

提交准备见 `docs/APP_STORE_HANDOFF.md`。`scripts/package_store_screenshots.py` 从两类设备的原生 xcresult 整理九语截图并生成待审阅清单；`scripts/release_preflight.py` 默认严格阻断未完成的账号、资料与验收事项，`--report-only` 只显示清单，不表示可发布。App Store应用价格/协议和TestFlight完整功能/离线验证分别记录；历史内购测试不替代现行验收。
