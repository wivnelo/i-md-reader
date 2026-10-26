# App Store 分发准备（草稿，未上传）

用户确认iPhone/iPad使用App Store。当前仅准备，任何上传、协议接受、密钥或权限扩展、审核提交和上架需要单独明确步骤。

本次GitHub正式发行仅为Mac 0.2.0（46）；移动源码版本已同步，设备仍为0.2.0（44），不等于App Store已发布。

## 隐私元数据补充（最新）

已添加ReaderApp/Resources/PrivacyInfo.xcprivacy并纳入iOS/Mac资源阶段；仅元数据，不改变运行逻辑、权限或网络。build34归档已验证包含清单；build33“缺清单”仅为历史记录。Mac当前包与移动开发设备安装版本以STATUS为准。

| 类别 | 原因 | 源码依据和实际用途 |
| --- | --- | --- |
| NSPrivacyAccessedAPICategoryUserDefaults | CA92.1 | ReaderStore.swift:167、204–210及ReaderScreen.swift:40–49；只保存本App书签索引、阅读位置和外观偏好，无跨App/App Group读取 |
| NSPrivacyAccessedAPICategoryFileTimestamp | C617.1 | OfflineCache.swift:74、103–109；App缓存容器内的修改日期，用于缓存淘汰，无上传时间戳 |

已按2026-10-26 Apple官方结构化文档核对代码与范围：[许可理由](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)。LocalDocuments.swift:87读取文件大小，不是该表列出的时间戳API；未因其用途机械添加3B52.1。固定swift-markdown Sources与swift-cmark src中未检出所查stat/boot-time/UserDefaults调用；这不是全部系统实现或供应链审计。

NSPrivacyTracking为false、TrackingDomains为空：源码无广告标识、跨App关联或广告/数据经纪跟踪用途。尚未设置NSPrivacyCollectedDataTypes，避免把未完成的商店收集评估写成空数组承诺。该文件目前仅完成已证实API及跟踪部分；运营主体、支持反馈处理和GitHub服务的数据保留仍需最终核实，商店隐私标签未提交。

验证：build34 unsigned iOS Release Archive成功；App包内清单与源码解析结果完全一致，plist及工程语法检查通过。未上传Apple验证；后续Mac build37/38/39已构建并包含同一资源阶段，不能将此归档检查等同于Apple审核通过。

## 本地核对

- iOS target为iMDReader，支持iPhone/iPad，最低iOS17，公开工程默认bundle ID为`com.example.ipadmarkdownreader`；此前两台真机安装使用本机构建覆盖的开发标识，与此默认值不同。当前设备build44沿用原开发标识，具体本机签名参数不入库。拟用商店标识及既有记录仍须对照核实，不擅自改名或清空设备资料。
- 工程使用Automatic signing；公开工程不保存团队或个人设备信息。已有本机Apple Development身份，尚未确认App Store distribution provisioning可用，不自动创建证书或profile。
- Info.plist声明Markdown Viewer、原地打开文档、单scene；没有新增相册/定位等权限。当前源码已包含PrivacyInfo.xcprivacy；已核对的required-reason API见上表，数据收集评估仍未完成，不据此声明“完全不收集”。
- iOS 0.2.0（34）unsigned Release Archive已成功并包含隐私清单；build39 iOS Simulator构建通过。build44已用原开发签名覆盖安装iPhone/iPad并读回版本，详见STATUS；开发签名与unsigned Archive均不等于App Store分发签名或真机功能验收。
- 无已验证App Store ID/公开URL，移动启动更新入口暂不启用。后续读取App Store Connect现有记录，核对bundle ID后接入真实商店地址。

## 可审阅商店文案

名称：iMDReader
副标题草稿：只读 Markdown 阅读器
说明草稿：在iPhone与iPad阅读本地Markdown文件、文件夹及GitHub文档。保留目录层级，支持代码高亮、目录导航、主题、字号与中英文界面。应用不修改源文档。GitHub私有仓库可使用用户授权的只读访问。

待准备：实际版本截图、支持与隐私政策URL、隐私表逐项核实、年龄分级与内容声明、加密出口合规核对、审核演示步骤、分发签名与设备Archive验证。不得把示例占位URL提交到商店。


## 后台只读补核（2026-10-26）

App Store Connect后台浏览器访问apps实际返回登录页与authResult=FAILED；没有可用连接器。不代表账户没有App记录，只代表本会话未认证。最小下一步：用户在本机登录App Store Connect，进入“我的App”并打开iMDReader现有记录；然后核对App信息中的bundle ID和Apple ID。如没有记录，先报告，不自动创建或猜URL。密码/验证码不发聊天。

历史build33 unsigned归档缺隐私清单的发现已由build34修复；本轮复核build34包内清单与源码完全一致，但没有embedded.mobileprovision，仍不是可上传的分发归档。数据收集评估、商店隐私标签及最终签名归档报告仍待完成。

隐私政策可审阅草稿：

> iMDReader在设备上保存阅读偏好、来源引用、阅读位置及离线缓存，不修改原Markdown文件。访问GitHub来源时，应用向GitHub请求仓库目录、文章与相对资源；私有仓库的访问令牌保存在本机钥匙串，并随授权请求发送给GitHub。令牌不用于开发者自有分析服务。清除离线缓存会移除本机缓存；移除来源不删除原文件。点击外部链接会交由系统打开，对方网站适用其自身隐私政策。

以上为源码支持的草稿，发布前需补实际运营主体、联系渠道、政策生效日期及托管URL。未发现广告/统计SDK，不等于已经完成所有依赖和服务端数据保留审计，不直接提交“完全不收集”标签。现有依赖为固定版本swift-markdown/swift-cmark，仍需归档隐私报告核对。WebView使用nonPersistent存储（ReaderWebView.swift:41），外链需用户点击（:172），Markdown外部图片被过滤（MarkdownRenderer.swift:107）。

Apple依据：[App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)、[required-reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)。商店标签与隐私清单是两项不同交付，不能相互替代。
