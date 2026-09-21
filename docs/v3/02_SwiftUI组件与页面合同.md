# SwiftUI组件与页面合同

## 实際代码，不是组件名称清单

| 组件 | 源文件 | 行为 |
|---|---|---|
| LPPhotoHero | Theme.swift | 原创摄影图+可伸展内容+独立暗部遮罩 |
| LPGlassSurface / LPCircleButton | Theme.swift | iOS26系统玻璃可用时使用；旧系统Material；减少透明度时实色 |
| LPEventTile | Visual/TodayVisual.swift | 4个事件卡，自适应文字高度，大字体单列 |
| LPMetric / LPPhaseLabel | TodayVisual.swift、Theme.swift | 数值/相位与状态绑定，不把读数嵌进图片 |
| SolarTimeline | Visual/SolarTimeline.swift | Canvas实际日照曲线、阈值色带、拖动、VoiceOver分钟调整、相位轻触觉 |
| VisualDayModel | Visual/SolarTimeline.swift | 天文曲线和静态地理投影后台采样；不在每帧重新计算全天 |
| LightMapView | MapView.swift | MapKit真实影像、天体射线、早晚事件、黄金扇区、浮动控制层、宽屏侧栏 |
| LPMilestoneRow | Visual/PlanVisual.swift | 时间+彩色节点+解释，时间/顺序来自Planner |
| PlansView / PlanDetailView | Visual/PlanVisual.swift | 场景卡片列表、沉浸式详情、编辑、回到地图 |
| PlanEditorView | PlansPlacesSettings.swift | 保留实际表单；支持新建/现有计划编辑并重新排提醒 |

## 布局尺寸是pt，不是硬编码设备像素

紧凑首页：350pt最小Hero（大字体440）；页面边距16；事件外壳28圆角、内边距14、格间距12；信息卡26圆角；主按钮18圆角、至少44pt可点击。文字长则长高，不横向压扁、不把所有文字最小缩到8pt。

宽屏：首页主要阅读内容最大宽度760pt居中；地图保留更多可用面积。主要信息使用headline/body/subheadline/caption语义字型。大字体不承诺“一屏塞完”，允许自然滚动，不能截断时间、地名或购买价格。

地图紧凑：搜索入口+日期胶囊+侧边按钮；底部黑色控制面板保持可操作。MapKit法定署名所在底部不被控制面板盖住。原生面板在地图viewport之外；上方按钮可浮动在地图上。开出图片中不存在的假卫星图是不合格。

计划详情：310pt最小Hero；保存的标题、日期、地点；浅色圆角内容层；彩色节点连接线；提醒配置说明；地图CTA。对于已保存计划，底部显示“在地图中查看计划”，不是永远显示“保存计划”的假按钮。编辑进入真正的PlanEditorView。

## 视觉验收必须一致的内容

照片、构图暗部、模块顺序、图标语义、色彩含义、按钮层级、适当留白与数据绑定必须保留。字体栅格化、系统Tab Bar和MapKit卫星影像不要求与浏览器逐像素相同；不能借此把Hero、曲线和计划卡重写成默认List。

首发地图不包含真实建筑阴影、地形遮蔽、天气评分或AR取景。这些不是靠画一个扇区就实现的能力。产品此前提及的这些可能性不得以虚假文案出现在发布截图。
