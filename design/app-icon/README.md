# iMDReader 图标 v1

2026-10-25。用户确认纸页 + M 方向，随后要求深色版减少蓝色、参考苹果深色图标配色。

资源位于 `ReaderApp/Resources/SourceIcons.xcassets/AppIcon.appiconset/`：

- Any：暖白纸张、低饱和蓝灰 M。
- Dark：石墨灰背景、银灰纸页、炭灰 M，无明显蓝色。
- Tinted：黑底灰阶图案，供系统着色。

三张均为 1024 × 1024、不含 alpha 的 PNG；外部圆角由系统裁切。工程已指定 AppIcon，桌面名称为 iMDReader，未修改 Bundle ID。

制作使用内置 image_gen，之后仅用 sips 归一化尺寸。生成源图保留在 Codex generated_images。本轮采用 asset catalog 静态资源，尚非 Icon Composer 分层文件；不声称已完成 Liquid Glass 分层及透明外观专项验收。最低 iPadOS 17 使用默认图标，支持相应外观的系统按主屏幕设置选择资源。

## 最终提示词

Light（edit）：REMOVE the large outer raised rounded square tile behind the document, including its boundary, bevel and cast shadow. Replace that outer tile and the surrounding canvas with one continuous FLAT uniform warm ivory #FCFBF8 background extending edge-to-edge to every pixel and corner. Preserve only the CENTRAL folded paper document with the M and two reading lines, at its existing size and position. Reduce blue saturation on M slightly to slate blue-gray. Only ONE raised object, the central folded paper; NO second outer tile or frame. Keep document geometry. Output square production artwork, opaque, no surrounding mockup.

Dark（edit）：REMOVE the large outer raised rounded square tile behind the silver document, including its boundary, bevel and cast shadow. Replace outer tile and surrounding canvas with ONE continuous FLAT UNIFORM neutral graphite #202123 background, edge to edge to all pixels and four square corners. Keep the central silver folded-paper document with M and two lines unchanged at existing size and position. Only ONE raised object remains: central folded paper. NO second outer tile, border, frame, or mockup. Absolutely neutral gray, no blue. Square production image.

Tinted：Create a monochrome TINTED appearance iOS app icon resource matching the approved paper M icon. ONE square full bleed grayscale opaque image. Background pure black reaching all four square corners, paper sheet light gray with folded upper-right corner, bold M and exactly two short horizontal reading lines dark gray. Centered, generous padding. System-tintable grayscale artwork, no colors, no blue cast, NO rounded outer icon boundary, NO canvas or mockup, no external shadow. Crisp silhouette, restrained grayscale shading, no words.

## 验证

通用 iOS Simulator Debug 构建通过，asset catalog 编译成功；三张 PNG 均为 1024 × 1024 且无 alpha。尚未进行本轮实机主屏幕明暗／着色切换验收。

## App 内品牌区

侧栏导航栏采用 32pt 圆角图标 + iMDReader，移除原“资料库”大标题，保留添加来源按钮。ReaderBrand 图片集复用已确认的浅深色图标，跟随 App 当前外观。构建通过；模拟器已检查深色横屏。

## Mac固定深色图标 · 0.2.0正式资源

用户已取消Dock跟随系统明暗，固定使用已确认的深色图标。此决定取代此前运行时方案A；不再保留切换监听、App delegate或DockIconLight/Dark两套冗余imageset。

MacAppIcon.appiconset/AppIcon.png由原AppIcon-Dark.png复用生成：1024×1024画布，将原图绘制至x/y=100、824×824区域，185圆角，保留透明外边距。这与此前已确认运行时深色图的几何参数一致，中间纸页M不重绘。图标通过静态asset catalog打包，Dock/Finder无需等待应用运行时赋值；旧系统图标缓存可能延迟更新，不自动重启Dock或清缓存。

build41源图检查通过，最终build46 Universal正式包已签名公证并安装，已查看源PNG；实际Dock/Finder最终显示待用户确认，不将资源正确等同于缓存已刷新。系统明暗切换不再是需求或验收项目。App内ReaderBrand、iPhone/iPad Light/Dark/Tinted资源未改。

历史：build37–39曾使用运行时方案A，实际Dock切换未完成验收，工具读取超时；此方案已被用户撤回。Icon Composer方案B从未选择或实施。

安装版本与剩余验证见[STATUS](../../docs/STATUS.md)。
