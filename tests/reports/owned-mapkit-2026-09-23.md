# 直接管理MapKit地图的真机修复与复核 — 2026-09-23

用户两次真机复核均发现：SwiftUI地图切换图标状态后，实际瓦片仍是卫星影像。后一次复核还指出GPS能定位，却没有独立的当前位置蓝点。此前两版的模拟器截图不能作为真机成功证据；失败原图与报告继续保留。

## 具体变化

- 地图由应用直接持有公开的`MKMapView`，显式设置MapKit的原生底图类型。保留原有相机区域、地图旋转/缩放、天体轨迹、黄金时段扇区、升落方向、主体与建议机位标记；点图选主体改用MapKit的坐标转换。该做法避免依赖真机上未生效的SwiftUI地图样式更新。[Apple的地图配置接口](https://developer.apple.com/documentation/mapkit/mkmapview/preferredconfiguration)。
- 拍摄机位用相机图标标识；用户点击定位后，用CoreLocation给出的**同一份坐标**绘制独立蓝点。只有地图可见且用户主动定位后才持续更新；离开地图即停止。中国大陆测试地点上，MapKit内建用户位置坐标曾与已知模拟GPS坐标相差数百米，因此不把它直接作为当前拍摄机位，也不手写网上的地图偏移公式。
- 三个地图控件维持纯图标横排；点定位箭头取设备位置，长按回到已选拍摄地点。地图在状态栏下方完整显示，地图署名保留。
- CI的专用模拟器现在使用确定的GPS坐标并授权使用期间定位；定位错误不能再让正向GPS用例“通过”。

## 执行证据

| 项目 | 结果 | 边界 |
|---|---|---|
| 主要地图原生回归 | 六项通过 | 运行于直接持有地图的较早修订；最终补充蓝点与状态栏修订后又单独重跑严格GPS测试。覆盖构图机会保存、点图选主体、底图切换及重启保留、横竖屏控件、长按回中、GPS路线 |
| 严格GPS/蓝点回归 | 通过 | 授权的专用模拟器取得已知坐标，XCUITest找到单独的蓝点；地图截图中蓝点与相机机位对齐且颜色清晰 |
| 卫星与普通底图 | 两组模拟器原图可见实际瓦片变化；用户在更新后的实体iPhone点击确认也能切换 | 真机确认仅覆盖这项交互，不代表全地图精度验收 |
| App/Widget最终归档 | 开发签名及App Group、隐私、MIT许可、无StoreKit/生产fixture检查通过 | 不是App Store分发验收 |
| 实体iPhone更新与操作 | 已安装并重新启动；用户实际点击后确认底图可切换、单独蓝点可见 | 仅证明这两项反馈；不能代替其他真机与商店验收 |

最终蓝点回归结果包：`/private/tmp/LightPlan-owned-map-live-dot.xcresult`；其余地图工作流结果包：`/private/tmp/LightPlan-owned-map.xcresult`。最终归档：`/private/tmp/LightPlan-owned-map-ready.xcarchive`。原始截图、签名输出、已知失败版本与工作前备份位于Git忽略的`tests/reports/local/2026-09-23-location-map-style/`。

源码仍在`dev`且未提交。独立上架名称、账号/价格/联系方式、正式签名、真机完整操作和母语审校未完成；这次开发签名安装不等于可提交App Store。

最终定位检查曾发现一轮测试在系统弹窗后落入“定位不可用”却被宽松断言计为通过；已收紧断言，并在授予使用期间定位、设置已知坐标的专用模拟器重跑。最终源码的GPS结果包为`/private/tmp/LightPlan-owned-map-live-dot.xcresult`：真实位置改变且独立蓝点元素存在，原图展示蓝点与上方机位相机标记对齐。该失败与前两版真机反馈同样保留，未回填成早先候选已通过。

提交前复核（同日）：`swift test --package-path packages/LightPlanCore`退出码0，187项通过；`python3 scripts/localization_audit.py`退出码0，370个键覆盖九语；`python3 scripts/appstore_metadata_audit.py`退出码0；`python3 scripts/release_preflight_tests.py`退出码0，24项通过；`git diff --check`退出码0。Swift测试在受限沙箱内首先因编译器缓存权限失败，改在正常本机权限下重跑成功；这不是源码测试失败。
