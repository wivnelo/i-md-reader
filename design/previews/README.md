# 原生运行截图

## 当前截图 · 0.2.1（51）

`51-zh-ipad-reading.jpg`、`51-en-ipad-reading.jpg`为iPad模拟器实际阅读截图；`51-zh-iphone-reading.png`、`51-en-iphone-reading.png`为用户提供的iPhone真机阅读截图。均来自已选商店素材，画面未修图或拉伸；英文iPad图系统状态栏仍为中文。 首页所用SVG仅通过裁切路径显示圆角，内嵌原图，源截图与商店素材未改。

## 历史截图 · 2026-10-24

`imdreader-name.png`：统一iMDReader显示名后的模拟器原始截图。插入线触摸跨行效果仍待实机复查，不以这张静态图声称已验收。

`language-en.png`、`language-zh.png`：外观面板的English／简体中文切换；`language-github-en.png`：英文添加GitHub表单。simctl原始截图，文章/文件名保持原中文；重启恢复英文已检查，不据此声称所有系统弹窗或WebKit控件均已人工验收。

新增 `source-order-dark.png`：通过无障碍下移改变顶层来源顺序后的原始模拟器截图，左滑移除仍可见；不作为连续触摸拖放或边缘滚动的验收证据。

截图来自 iPad Air 11-inch (M4) / iPadOS 27.0 模拟器，通过 Xcode Device Hub 的截图功能保存，未合成或修改画面。

- `native-landscape-light-v2.png`：修正加载提示和外观弹窗锚点后的横屏浅色正文。
- `native-portrait-light.png`：竖屏正文优先，目录隐藏，表格独立排版。
- `native-landscape-dark.png`：深色 Swift 代码高亮及任务列表。
- `native-landscape-light.png`：本轮较早的首次运行截图，保留用于对比。

手动检查已覆盖目录展开、文档切换、相对图片、文章目录跳转、主题、代码复制和重启阅读位置恢复；不代表实机性能或外部文件授权验收。

## 密度与深色修订 · 2026-10-25

- `density-architecture-light.png`：知识库《技术架构》原文，收紧段落/标题留白后的浅色横屏。
- `density-architecture-dark.png`：同一文档、同一位置、同一字号的柔和深色横屏。

仍由 iPad Air 11-inch (M4) / iPadOS 27.0 模拟器的 Device Hub 原生截图功能保存，均为 2360×1640 PNG，未修改画面。样例原文来自 `KnowledgeBase/20_Projects/iMDReader/技术架构.md`，仅复制为应用内本地测试素材，不代表 GitHub 接入已完成。

## 17pt 比较版 · 2026-10-25

- `compact-17pt-architecture-light.png`、`compact-17pt-architecture-dark.png`：同一篇《技术架构》、同一初始位置、17pt 正文 / 1.65 行高，缩小标题比例与侧栏字体。
- 已通过原生外观面板核对 17pt 实际生效；保留原配色，截图未编辑。默认目录字体约 15pt，点击行至少 44pt。
- 与前一版截图的差异是实际 App 排版修改，不是缩放或后期压缩图片；用户提供的参考图存在裁切/缩放，无法用于精确反推 ChatGPT 字号。

## 本地目录恢复 · 2026-10-25

- `local-folder-restored.png`：系统文件选择器添加「我的 iPad」合成测试目录后，重启恢复授权、展开状态、相对文档和图片。与内置样例分开，不代表 iCloud 或实机验收。

## GitHub 原生流程 · 2026-10-25

- `github-refresh-light.png` / `github-refresh-dark.png`：从 App 添加公开 swiftlang/swift-markdown 的 README 单文件来源，手动刷新后，同一位置浅深色阅读。正文 17pt，原配色不变。
- `github-tree-dark.png`：添加完整公开仓库，展开 Sources 子目录，从树中打开 README；重复添加被明确拒绝，已有来源保留。
- 三张均由 Device Hub 原生截图按钮保存，2360×1640，未编辑。公开仓库未人为修改，不把刷新操作记作真实远端提交变化验收；新版本变化仍以自动状态测试为依据。
- 本地刷新另外实际验证外部正文/改名更新，8 个合成文件哈希与外部修改后的基准一致；本轮未另存本地截图。

## 来源层级修订 · 2026-10-25

- `source-sections-dark.png`：来源根名称加粗、文件夹/GitHub 官方图标、独立细分隔线；下级目录缩进保持。右侧为内置《技术架构》快照。
- 由同一 iPad Air M4 / iPadOS 27.0 模拟器的 Device Hub 截图按钮保存，2360×1640，未编辑。远程来源因实际限流处于收起状态，没有伪造远端加载结果。
- 箭头保持同一图形旋转，目录内容禁用继承动画；静态截图不证明帧率或实机拖影已改善。

## 来源吸顶实现后 · 2026-10-25

- `source-headers-dark.png`：新构建在同一模拟器启动后的原始 simctl 截图，颜色不变，展示来源根行与目录基础布局。未通过此图声称左滑、滚动吸顶、收起或真实授权撤销已完成人工验收。
- 配色候选另存 `../reader-palettes.html`，属于同排版的浅深色示意预览，不是原生运行截图。

## 四套配色 · 2026-10-25

`palette-mist-light.png`、`palette-mist-dark.png`：正式雾蓝浅深色与四项配色选择器。`palette-mountain-dark.png`、`palette-moss-dark.png`、`palette-sand-dark.png`：实际从外观面板切换远山、青苔、暖砂后的深色画面。均为 simctl 保存的原始 PNG。字号保持 17pt，阅读文档不变；另验证暖砂浅色重启恢复。

## 独立文件 · 2026-10-25

`single-file-dark.png`：专用iPad Air M4模拟器通过系统选择器授权目录外的合成MD，显示最近文件和权限范围提示；同级链接实际被阻止，重启恢复通过。Device Hub原生截图，未改图；不代表iCloud或默认类型实机验收。
