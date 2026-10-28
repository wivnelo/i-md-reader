# App Store 分发准备（未上传、未提交）

更新：2026-10-28。Mac正式版仍为0.2.0（46）；移动首发准备版本为0.2.1。源码、恢复及验证边界见[STATUS](STATUS.md)。

## 已完成准备

- 10月27日已核对开发团队与生产移动标识，并按授权建立Explicit App ID和App Store Connect记录；真实Apple ID已确认。记录存在不等于公开商店页面已上线。
- 已按用户决定保存0.2.1、免费、手动发布及175个地区的目标范围；首发仅iPhone/iPad，关闭Apple芯片Mac和Vision Pro兼容分发。地区选择不等于满足各地区资质要求。
- 中英文商店描述、关键词及支持/营销/隐私链接已准备并保存过读回；审核联系资料仅保存在Apple后台，不放入公开仓库。
- [产品网站](https://wivnelo.github.io/i-md-reader/)、[隐私政策](https://wivnelo.github.io/i-md-reader/privacy.html)、[支持](https://wivnelo.github.io/i-md-reader/support.html)已发布。移动App隐私入口源码已恢复，但未安装给用户验收。
- 用户创建Apple Distribution身份后，已核对匹配团队的App Store描述文件；历史0.2.1（49）签名归档、严格验签和本地IPA导出成功。原临时产物现已缺失，恢复后无签名归档成功，但分发签名等待系统交互已主动停止，尚无新IPA。

本轮未重新登录后台；以上后台状态来自10月27日操作与读回记录。未上传二进制、提交审核或发布。

## 本轮构建结果

核心37项、状态33项集合通过，各1项真实网络跳过。新49无签名移动Archive成功，包内版本、iPhone/iPad设备族、最低系统及隐私清单通过核对。现有分发身份与描述文件可识别，但签名等待系统SecurityAgent交互，已主动终止且不重试；当前没有新IPA。Mac新49签名Universal构建已通过，未公证。产物仅保存本地，未安装或上传。

## 构建与验证清单

- iOS目标支持iPhone/iPad，最低iOS17；历史49使用iOS27.1 SDK。SDK能编译不等于所有新形态或最低系统布局已验收。
- 公开工程保留通用标识及空团队参数；生产标识、签名参数和设备信息不入公开文档。重新构建须核对实际签名团队、Bundle ID、版本、设备族、隐私清单及描述文件权限。
- Info.plist声明Markdown Viewer、原地打开文档、单scene，无新增相册/定位权限。不得把unsigned Archive或开发签名包当商店分发包。
- 新包另存持久目录并计算新摘要，不覆盖旧正式资产或设备资料。分发私钥不导出、不写入Git；不再次自动操作Keychain Access权限弹窗。

## 尚缺资料与决策

- 最终iPhone/iPad截图与对应版本交互证据；使用合成阅读资料，中英文截图和说明必须反映真实功能。
- 商店隐私标签、年龄分级、分类/副标题、加密出口、DSA及中国等地区适用资质仍需完成；不得代填未经确认的经营或法律声明。
- 依赖许可已有声明，仍需最终归档隐私报告与数据流复核。GitHub请求、令牌存储、邮件反馈处理必须纳入评估；没有广告SDK不直接等于“完全不收集”。
- 审核说明需覆盖本地文件、文件夹、公开GitHub样例及离线阅读，说明私有仓库为可选，不提供私人令牌或用户文档。
- 上传、审核及正式发布另行授权。分发证书和记录已创建，不重复创建；缺失原IPA须先重新构建验证。

## 隐私元数据补充（最新）

已添加ReaderApp/Resources/PrivacyInfo.xcprivacy并纳入iOS/Mac资源阶段；仅元数据，不改变运行逻辑、权限或网络。build34归档已验证包含清单；build33“缺清单”仅为历史记录。Mac当前包与移动开发设备安装版本以STATUS为准。

| 类别 | 原因 | 源码依据和实际用途 |
| --- | --- | --- |
| NSPrivacyAccessedAPICategoryUserDefaults | CA92.1 | ReaderStore.swift:167、204–210及ReaderScreen.swift:40–49；只保存本App书签索引、阅读位置和外观偏好，无跨App/App Group读取 |
| NSPrivacyAccessedAPICategoryFileTimestamp | C617.1 | OfflineCache.swift:74、103–109；App缓存容器内的修改日期，用于缓存淘汰，无上传时间戳 |

已按2026-10-26 Apple官方结构化文档核对代码与范围：[许可理由](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)。LocalDocuments.swift:87读取文件大小，不是该表列出的时间戳API；未因其用途机械添加3B52.1。固定swift-markdown Sources与swift-cmark src中未检出所查stat/boot-time/UserDefaults调用；这不是全部系统实现或供应链审计。

NSPrivacyTracking为false、TrackingDomains为空：源码无广告标识、跨App关联或广告/数据经纪跟踪用途。尚未设置NSPrivacyCollectedDataTypes，避免把未完成的商店收集评估写成空数组承诺。该文件目前仅完成已证实API及跟踪部分；运营主体、支持反馈处理和GitHub服务的数据保留仍需最终核实，商店隐私标签未提交。

验证：build34 unsigned iOS Release Archive成功；App包内清单与源码解析结果完全一致，plist及工程语法检查通过。未上传Apple验证；后续Mac build37/38/39已构建并包含同一资源阶段，不能将此归档检查等同于Apple审核通过。


## 数据流与政策证据

本地保存来源引用、书签、阅读位置、偏好和缓存；访问GitHub时向GitHub请求目录、正文及相对资源，用户令牌保存在设备钥匙串。外部链接由用户点击打开，目标网站适用自身政策。WebView采用非持久存储，Markdown外部图片过滤；依赖为固定版本swift-markdown/swift-cmark及内置高亮资源。政策网页存在不代表商店标签或所有供应链审计完成。

Apple依据：[App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)、[required-reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)。隐私清单与商店标签是两项不同交付。
