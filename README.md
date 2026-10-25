# iMDReader

轻量、原生、只读的 iPad Markdown 阅读器：IDE 式文件树，舒适的长文阅读排版。

**当前为开发原型，部分核心功能已实现，尚未完成 MVP 验收。** 已完成、未完成和待验证内容集中记录在 [开发状态](docs/STATUS.md)。

![iMDReader 原生界面](design/previews/imdreader-name.png)

*原生模拟器截图。截图保留当时状态，最新代码已进一步简化“收起全部”图标。*

## 已实现

- **本地文件夹**：系统目录选择、多来源、原层级懒加载树、安全范围书签及状态恢复；只读原文件。
- **公开 GitHub**：仓库、子目录、单篇 Markdown 链接；分支解析、固定提交读取、相对 Markdown 导航及每来源刷新。
- **阅读**：GFM、表格、任务列表、代码高亮/复制、本地图片、文章目录、阅读位置、隐藏侧栏。
- **外观**：浅色/深色、四套低饱和配色；默认 17pt，字号滑杆以 17pt 为中点（范围 12–26pt）。
- **来源管理**：根标题吸顶、左滑移除、顶层长按排序并保存顺序、收起全部子目录、无障碍上移/下移；移除来源不删除源文件。
- **界面语言**：跟随系统、简体中文、English；保存选择，不翻译文档正文或文件名。
- **刷新保护**：并发请求合并、固定提交响应的受限内存缓存、限流冷却和恢复时间提示。

代码已实现不代表所有实机、异常与无障碍场景已验收。

## 尚未实现

- 私有 GitHub 认证、Keychain 与授权撤销后的内容清理。
- 远程图片、图片放大和持久离线正文缓存。
- 从系统“文件”直接用 iMDReader 打开单个 MD、App 内单文件选择与默认打开方式接入。见[设计方案](docs/FILE_OPENING.md)。
- 完整 iCloud、最低系统、实机长文性能、动态字号和 VoiceOver 验收。

不开发编辑器、Git 提交/推送、AI、协作或自建服务。

## 构建与测试

使用 Xcode 打开 `iMDReader.xcodeproj`，选择共享方案 `iMDReader`。首轮构建需下载 Swift 官方 Markdown/cmark 依赖，版本记录在 `Package.resolved`。暂定 iPadOS 17 下限，尚未完成该版本的运行验收；已使用 Xcode 27.1 构建。

```sh
# 核心解析、路径、GitHub 请求测试
swift test --package-path ReaderCore
# macOS 上直接测试实际 ReaderStore
swift test
# 不签名的模拟器构建
xcodebuild -project iMDReader.xcodeproj -scheme iMDReader \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

实机安装需要在 Xcode 配置自己的开发团队和唯一 Bundle ID；仓库不包含签名证书或个人团队参数。首次选择本地目录需要系统授权。

真实网络测试默认跳过，可在确有需要时显式设置 `READER_GITHUB_LIVE=1`，注意 GitHub 请求额度。

## 技术与安全边界

Swift 6 / SwiftUI `NavigationSplitView` + `WKWebView`。swift-markdown（cmark-gfm）解析为安全白名单 HTML，highlight.js 随应用离线内置。原始 HTML 不直接执行，资源路径检查授权边界，WebKit 禁止文档脚本和网络直连。

GitHub 当前只读取公开内容，不复用开发机登录；请求限定 GitHub API，拒绝重定向。内存缓存上限 32 MB / 128 项，**不等于重启后离线可读**。远程正文暂限 UTF-8 / 10 MB，本地图片文件暂限 20 MB；这些是保护上限，不是性能保证。

第三方声明见 [ThirdPartyNotices](ReaderApp/Resources/ThirdPartyNotices.txt)、[highlight.js 来源与许可](ReaderApp/Resources/Vendor/README.md) 及 [GitHub 来源标识说明](ReaderApp/Resources/GitHubMark-Attribution.md)。GitHub 标识仅用于辨识来源，不是本应用图标。

## 项目入口

- [开发状态与后续计划](docs/STATUS.md)
- [单文件打开与默认应用设计](docs/FILE_OPENING.md)
- [原生运行截图](design/previews/README.md)
- [App 图标说明](design/app-icon/README.md)
- `ReaderApp/`：原生界面、阅读桥接、来源与状态。
- `ReaderCore/`：安全解析、文件边界、GitHub 只读请求及核心测试。
- `Tests/`：实际应用状态的 macOS 测试。
- `design/`：早期视觉原型、配色比较与历史截图；不作为当前实现状态的依据。
