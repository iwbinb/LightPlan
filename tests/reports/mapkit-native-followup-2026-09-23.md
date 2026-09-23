# 原生 MapKit 底图与设备蓝点后续修复 — 2026-09-23

用户在实体 iPhone 二次复核后明确反馈：前一版的图标虽然变化，底图仍未变化；GPS 能定位，但没有代表设备位置的小蓝点。因此前一版的模拟器成功不能作为这两项真机问题已修复的证据。

## 本轮变化

- 保留SwiftUI地图承载的相机、天体射线、方向标记和MapKit署名；在样式改变时，通过公开的`MKMapView.preferredConfiguration`显式应用`MKImageryMapConfiguration`或`MKStandardMapConfiguration`。这是对前一版仅改变SwiftUI `.mapStyle`和视图身份后真机瓦片仍旧的补救。[Apple的原生地图配置文档](https://developer.apple.com/documentation/mapkit/mkmapview/preferredconfiguration)。
- 用户主动点击GPS且获得位置后，显示MapKit系统[UserAnnotation](https://developer.apple.com/documentation/mapkit/userannotation)蓝点。已选拍摄机位改为上方的相机标记，两者在同一地点也能区分。离开地图后移除设备位置标记，避免后台持续追踪。
- 纯图标样式按钮、横排避开日出时间、长按返回拍摄地点及九语辅助功能值保留。

## 已执行证据

| 项目 | 实际结果 | 边界 |
|---|---|---|
| 原生GPS流程 | 专用iPhone模拟器通过 | 系统授权后更新地点；原生截图可见系统蓝点和独立相机机位标记 |
| MapKit底图 | 专用iPhone模拟器通过 | 卫星/普通底图截图确实不同，样式重启保留；Debug测试记录桥接器找到2个底层`MKMapView`实例 |
| 最终App/Widget归档 | 开发签名、App Group、隐私/MIT、无StoreKit与无生产fixture检查通过 | 不代表App Store分发验收 |
| 实体iPhone更新 | 已安装并重新启动新归档 | 用户再次查看后才能确认这次真机底图和蓝点表现；当前仍为待确认 |

最终归档：`/private/tmp/LightPlan-mapkit-native-ready.xcarchive`。原生结果包：`/private/tmp/LightPlan-mapkit-bridge.xcresult`。本地原图、编译与签名记录在Git忽略的`tests/reports/local/2026-09-23-location-map-style/`；前一候选和用户提供的失败截图原件都保留。

**后续真机反馈：** 用户再次确认样式图标变了、实际底图仍没变。该桥接候选也没有解决真机底图问题，不能将模拟器成功写成真机通过。应用已转为[直接持有MKMapView的后续候选](owned-mapkit-2026-09-23.md)；本页保留失败尝试与来源边界。

源码仍在`dev`，本轮未commit、push、merge、部署网站或提交App Store。正式名称、所有者账号/价格、真机完整交互、TestFlight和语言人工审校仍分别验收。
