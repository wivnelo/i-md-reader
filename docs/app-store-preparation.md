# App Store 分发准备（等待审核）

2026-10-28：移动0.2.1（51）Apple Distribution归档及本地IPA导出成功；严格验签、生产标识、iPhone/iPad设备族、App Store描述文件（无设备限制、关闭调试权限）及隐私清单与源码一致性均通过。最低iOS17，构建SDK为iOS27.1。签名授权阻塞已解除，无需重复申请。IPA已通过Transporter交付并提交审核，当前状态见本轮App Store状态。

IPA大小6,546,071字节，SHA256：`79446268ef68dc5475b540579c05e4aa39d85f0188b092376b12b4cba6e46a49`。新51摘要独立核验，不沿用已缺失的历史49产物。Mac0.2.1（51）已正式发布，三端51获用户验收；剩余商店硬性资料见下表。

## 本轮 App Store 状态

2026-10-28 21:42（Asia/Manila），用户明确同意后，App Store Connect已发布“未收集数据”隐私标签，并提交iOS 0.2.1（51）供审核；后台回读状态为“等待审核”。仍为手动发布，尚未上架。GitHub直接请求信息及外部支持的标签适用范围已向Apple Developer Support咨询，等待回复；如Apple要求调整，应及时修正。主要类别效率、DSA非交易商；供应174个地区，中国大陆不供应，Apple芯片Mac和Vision Pro兼容供应未启用。年龄问卷已保存，Apple计算全球4+（部分地区另有分级）；内容版权和构建51出口问卷按用户确认保存。中英文商店资料和8张iPhone/iPad截图已保存；IPA于21:30通过Transporter交付。

截图：用户授权的8张图已上传至App Store Connect 0.2.1草稿，简中和英语（美国）的iPhone及13英寸iPad各2张；页面重载后各栏均回读为2张，阅读在前、代码在后。iPhone为用户提供的真实设备截图（英文选IMG_8070/8071），iPad为真实51模拟器截图；图片未显示版本，英文iPad图系统日期仍为中文。资料库含个人目录名的图未上传。后台显示不等于Apple审核接受。

## 历史问卷建议与截图清单（提交前记录）

以下为提交前评估；实际填报及当前状态以上节为准。

| 项目 | 源码支持的建议 | 尚缺确认 |
| --- | --- | --- |
| 跟踪/广告 | 建议否；无IDFA、广告或统计SDK，Tracking=false | 不把第三方整个网站行为等同本App行为 |
| 本地正文/书签/阅读记录 | 设备本地处理，不因本地存储申报收集；无正文上传接口 | 用户主动支持附件另行评估 |
| GitHub请求 | HTTPS GET到api.github.com，路径/固定提交和可选令牌；禁cookie和重定向 | 官方政策包含IP及服务使用信息，需核定用户指定服务在商店标签中的适用范围；不能直接填全局“未收集数据” |
| 支持邮件/Issues | 自愿外部支持，无App自动上传 | 责任人确认用途、留存/删除及是否营销/转交；自愿不自动满足可选披露全部条件 |
| 加密 | 使用加密：系统TLS/Keychain、CryptoKit AES-GCM私有缓存和SHA256派生；未发现自研算法 | 根据ASC实际问题核定豁免及出口/法国等要求；不擅填非豁免加密为false |
| 年龄与内容 | 无聊天、社区发布、广告、购买或开发者提供成人/赌博内容 | 自有/GitHub内容及外链按问卷定义判断，不自动给年龄等级 |
| 经营/地区 | 已定免费、手动发布及目标地区 | DSA交易者身份、地区资质/备案、内容权利须责任人据实确认，免费不代表非交易者 |

新归档许可声明与隐私清单逐字节匹配源码，无额外嵌入Frameworks；不等于全量供应链审计。新增日期查询只向GitHub发送当前仓库文件路径/提交，无正文上传；新增授权文件时间戳用途为3B52.1。

截图：旧临时截图已缺失，历史design预览及网站图片不算最终套图。待首发界面定稿后拍简中/英文各5张×iPhone/iPad共20张：阅读与目录、来源层级、代码表格、明暗配色、公开文档离线阅读。iPhone采用1206×2622竖屏，iPad13英寸采用2752×2064横屏；无透明PNG/JPEG，每档1–10张。记录build/系统/机型/语言，使用合成资料，核查裁切和私人信息；隐私入口另拍交互证据。50日期排版截图只作开发验证，不当商店实拍。

官方截图页当前要求iPhone灵动岛中等屏幕和13英寸iPad；iPhone Duo要求注明2027年4月起适用于iOS27.1+构建，当前不阻塞既有机型准备，亦不代表已经适配验收。

依据：[Apple隐私定义与可选披露](https://developer.apple.com/app-store/app-privacy-details/)、[GitHub隐私政策](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)、[出口合规](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)、[截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)。建议不是已提交答案。


## 历史准备证据（以下为早期阶段，当前以页首为准）

历史记录：Mac当时正式版为0.2.0（46）；移动首发准备版本为0.2.1。源码、恢复及验证边界见[STATUS](STATUS.md)。

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

## 隐私元数据补充（历史）

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
