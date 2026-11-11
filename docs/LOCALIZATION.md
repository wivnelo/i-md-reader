# 界面本地化

当前开发分支在现有简体中文（zh-Hans）、英语（en）基础上新增繁体中文（zh-Hant）、日语（ja）、韩语（ko）。这是未在 Apple 平台验证的开发适配，不代表正式版已提供五语言。

## 机制

- String Catalog：ReaderApp/Resources/Localizable.xcstrings，源语言 zh-Hans，key 使用中文原文。SwiftUI 的 Text、Label、Button 等使用 LocalizedStringKey；动态 key 应显式转换，用户正文与文件名保持普通 String。
- ReaderLanguage：应用内选择跟随系统或五种语言，通过 environment locale 注入 SwiftUI。跟随系统按首选语言顺序选首个支持的语言，繁体/台湾/香港/澳门先于通用中文，均不支持时回退英语。
- message()：原生菜单、分段标签、alert、错误等普通 String 从 bundle.resourceURL 下的语言 lproj/Localizable.strings 取值。主 bundle 使用不可变静态语言表缓存；简体中文、未知 locale/key 保留原文。换行错误逐行翻译，系统错误详情保留；额度与 HTTP 动态错误通过 %@ 模板替换。
- reader.js：按 data-ui-language 选择五语言文案；MutationObserver 支持即时切换。未知语言沿用简体中文。
- Widget：独立 text() 五语言表，只看系统首选语言，不编译 ReaderLanguage，也不跟随 App 内语言覆盖。
- App Shortcuts：title、description、typeDisplayRepresentation、shortTitle 等使用目录中的中文 key；phrases 显式列出各语言，保留 applicationName 和 document 参数，每个 shortcut 不超过 10 条。
- DocumentDates：保留原中英文输出；新增三语言标签与本地化日期模板 yMMMdHHmmzzz，使用公历及传入时区。

## 新增语言或字符串

1. 在目录补齐对应语言译文，保留 key 和占位符类型；不要翻译用户内容或语言自称。
2. 新语言同步 knownRegions、ReaderLanguage 解析/语言表缓存、语言 Picker、reader.js、Widget text()、日期标签及 App Shortcuts phrases。
3. 新 SwiftUI 文案直接使用中文 LocalizedStringKey；普通 String 显示入口使用 message()，并保证目录存在同名 key。新的动态消息优先使用完整模板，避免假定译文参数位置。
4. 补语言解析、临时 bundle 消息、日期与 WebView 测试；检查普通/iOS 与 Mac Contents/Resources 两种资源布局。
5. 执行 `python3 scripts/check-localizations.py`（校验目录 JSON、五语言完整性、占位符一致、严格 UTF-8、knownRegions、reader.js/ReaderLanguage 覆盖；可选安装 opencc-python-reimplemented 以提示繁体里残留的简体字），再在 Mac 执行根目录 swift test 和 ReaderCore 下的 swift test；使用 scripts/check-reader-webview.sh 及 scripts/check-mac-appearance.sh /path/to/iMDReader.app。
6. 在实际打包 App 中切换所有语言与 system，检查窄屏、长文案、设置菜单、无障碍及中英文既有交互。

## 已知限制与验证边界

示例文档与正文不翻译；ByteCountFormatter 与 GitHub 限流时间使用系统 locale；正文 HTML lang 保持 zh-CN，避免改变汉字字形。日语、韩语、繁体译文由 AI 起草，未经母语审校；日期用系统本地化模板（yMMMdHHmmzzz），中英文保持旧格式。语言设置控件由分段改为菜单（六个选项在 Mac 弹层与 iPhone 窄屏放不下分段）。

本轮仅在 Linux 做静态检查：目录校验脚本、JavaScript 行为检查，以及用 Swift 6.1 对 ReaderLanguage/DocumentDates 做的独立编译与运行检查、其余 Swift 文件的语法解析；没有 Xcode，未在 Xcode、模拟器或真机编译 App 与 Widget、验证布局、语言或交互。固定回归门槛中的语言标签、外观排版、Mac 查找和移动设置仍需 Apple 平台回归。
