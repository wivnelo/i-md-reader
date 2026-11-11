# iOS：14 天全功能免费试用 + 到期后买断

## 当前故障与界面调整 · 2026-11-11

55 已可安装，但用户真机商品加载仍失败。Chrome 核实两个商品已“准备提交”，标识、当前价格、175 地区及五语言信息一致；付费 App 协议实际为“新”、无生效日期，用户需本人处理商务页要求。不能以“已接受开发者许可协议”替代付费协议生效，未取得设备日志前不能断言唯一根因。完整证据与后续复测见 [STATUS](STATUS.md)。

用户另明确移除旧锁定入口页，保留新付费墙、设置/资料管理和收费规则；旧页已移除并完成所列双设备受影响回归，安全回写本地主仓库，尚未进入 55。真实试用、购买、恢复、取消、家庭共享及到期均仍需设备验收。本轮不代填身份/财务、代签协议或提交审核。

2026-11-11 22:15 UTC 更新：用户授权的最新修复已签名归档并上传 TestFlight 0.4.0（55），Chrome 回读正在处理；现有 Internal 组沿用，不新增权限或邀请，不正式提审或上架。下面未上传/不升版本描述为此前修复阶段；本次命令覆盖 App/Widget 构建号，工程默认值未改。处理完成及双设备可安装仍待核实，详见 STATUS。

2026-11-11 已定「14 天全功能试用＋买断」。实现已合入公开 main `c7b52e9`（0.4.0 / 54）；交接记录该构建已进入 TestFlight，正式 iOS 仍为免费 0.3.0（53）。两个 ASC 商品已创建（交接记录），不重复创建。当前接手修复不改版本、不安装正式 App、不上传、不提交审核或发布；StoreKit 集成测试仅安装独立模拟器宿主。

## 接手修复：商品加载、等待与恢复

- 商品加载独立于交易操作，启动并行读取权益与价格。加载期间可以恢复购买；恢复期间仍能重试商品请求。空结果、缺试用商品、请求失败、超时分别反馈；只取得买断商品时仍可买断，领取试用仍须两个商品及买断本地化价格。
- 商品请求与完整权益读取各等待 15 秒。超时不等待不响应取消的框架任务；迟到的读取结果不再写入状态或 Keychain。读取失败不清空已缓存权益。并发权益读取合并；验证通过的购买/撤销先应用，旧快照不能覆盖新通知，新交易也不会被尚未更新的当前权益列表抹掉。
- 购买和恢复分别显示进度。购买系统窗口等待超过 60 秒时提示完成或取消系统操作，不将超时当作交易取消、不开放重复购买。恢复等待超过 60 秒时显示仍在等待，允许再次点击恢复以继续等待同一个底层 `AppStore.sync()`；不重复调用认证。底层迟到的成功/失败/取消仍更新 UI，`Transaction.updates` 继续监听。
- 用户取消静默回到可操作状态；恢复结果区分成功、无记录、失败和等待中。没有账户/设备日志时，不根据 UI 推断协议、银行税务或商品截图就是根因。日志仅记阶段、错误域/代码、缺失商品 ID，不记录账户、收据、交易详情或错误 userInfo。
- 首阶段在原 Form 中补状态反馈；后续用户明确确认付费墙设计，已按稿改为原生页面（见下节）。品牌、语言选择器、14 天规则、老用户判定及家庭共享策略未改；新译文仍待母语审校。

用户报告已完成协议、税务、银行检查及 TestFlight 重测，并已更新 ASC 审核联系邮箱；本轮未回读 ASC，重测的具体成功/失败现象仍未提供。GitHub PR #8（支持页/首页邮箱、0.4.1 / 55 版本号）和 #2（隐私页）接手只读核对仍 open，未合并；Pages 主线仍含旧邮箱。后续创建审核版本须核对联系方式继承结果。

本机验证新增：根包 `PurchaseStoreChecksTests` 用实际 `PurchaseStore.swift` 与注入的 StoreKit 响应、内存缓存运行；`IMD_PURCHASE_TESTS` 仅该测试 target 定义，Mac App 不包含购买控制器。ReaderCore 的 `PurchaseDeadlineTests` 覆盖不响应取消、取消、重试、迟到结果及恢复单请求。测试命令为 `swift test --disable-sandbox` 与 `swift test --package-path ReaderCore --disable-sandbox -c release`（构建目录使用独立 scratch path）。结果与限制见 STATUS；它们不等于真实 StoreKitTest、沙盒或 TestFlight 交易通过。

## StoreKit 集成测试（独立模拟器宿主）

`Tests/StoreKitIntegration/iMDReaderStoreKitTests.xcodeproj` 直接编译实际 PurchaseStore 与 ReaderCore，复用 `ReaderApp/StoreKit/iMDReader.storekit`。宿主使用独立测试标识和内存缓存，无 ReaderStore、CloudKit、生产数据或真实 Apple 账户；测试必须串行，因为 SKTestSession 共享交易环境。测试购买前按实际 App 顺序调用 `start()` 建立交易监听；控制器释放时取消监听，避免跨测试残留。

```sh
# IMD_TEST_DEVICE 指向专用 iOS 模拟器；IMD_QA_DIR 指向本轮独立产物目录。
xcodebuild -project Tests/StoreKitIntegration/iMDReaderStoreKitTests.xcodeproj \
  -scheme iMDReaderStoreKitTests \
  -destination "platform=iOS Simulator,id=$IMD_TEST_DEVICE" \
  -derivedDataPath "$IMD_QA_DIR/build" \
  -resultBundlePath "$IMD_QA_DIR/results.xcresult" \
  -parallel-testing-enabled NO test
```

2026-11-11，Xcode 27.2 / iOS 27.0：8 项执行，7 项通过，1 项明确 known issue。覆盖价格及共享配置标志、免费试用、原试用起点恢复、到期买断/退款、待批准交易通知、购买失败、商品失败重试及恢复独立性、无记录/同步失败。取消注入 `.generic(.userCancelled)` 在此组合返回 `.unknown`；测试记录 known issue，并未更改生产处理去猜测错误码。仍须真机操作系统购买页取消；不能把框架的整体 TEST SUCCEEDED 当作这一项通过。

新控制器使用新内存缓存只验证交易恢复，不等同卸载重装；配置的 familyShareable 标志不等同跨账户家庭共享；本地商品和价格不验证 ASC/TestFlight 可用性。生产老用户资格、真机恢复认证、家庭共享撤销、离线及入口锁定/解锁画面仍按下文验收。付费墙审阅稿随后获得用户确认，已实施为下节的原生页面。

## 已确认的原生付费墙

用户于 2026-11-11 明确回复“付费墙没问题”，授权按已交付审阅稿实施。`PurchaseSheet.swift` 复用原 ReaderBrand 和雾蓝浅深色，完整保留 iMDReader 名称；首次试用、试用剩余、到期买断、商品失败/缺试用商品、交易等待/待批准、恢复与已解锁状态接入同一 PurchaseStore。价格及带价格的按钮只用 `Product.displayPrice`；没有把稿中的 USD 示例价写进 App。

购买页顶部关闭入口固定可达，内容可滚动，价格和底部链接在空间不足时改为纵向。按钮采用动态文字、至少 44pt 操作高度；恢复、隐私和支持的最小高度放在控件 label 内，保证实际触控区也是 44pt；浅深色主按钮文字分别用浅色/深色以保证对比度。待批准时不再显示重复购买操作；收到验证通过的更新后显示继续阅读。已永久解锁时不再请求价格或显示无关商品加载失败。关闭或管理资料只是返回既有锁定层，不放开阅读。

付费页从 PurchaseViews 提取以便独立测试；锁定与设置入口行为、语言选择器、ReaderScreen、导航和数据管理实现不变。用户另行确认浅色锁定页“试用与购买、应用设置、隐私政策、使用支持”四处文字改用现有雾蓝 #426B87；只对这些控件设置浅色 tint，深色继承原 tint，不改变整个锁定层、语言选择器或付费页的颜色。Mac 目标不包含该页面，收费开关和既定收费规则均不变。新增 39 条五语言文案，合计 230 条；机器完整性检查不能替代母语审校。

`PaywallUITests` 在独立宿主上调用真实 SwiftUI 页面与本地 StoreKitTest，覆盖试用/买断/恢复按钮、商品失败/缺项、五语言、横屏、动态大字号滚动和待批准后解锁。`-paywall-qa` 等参数只存在于测试宿主，不引入正式 App 的调试旁路。它不包含 ReaderScreen，因而不能证明阅读区导航、深链和锁定后回到原文章等整 App 行为通过。运行命令沿用上节，可加 `-only-testing:PaywallUITests`；六类用例在短屏 iPhone SE 与 iPad Air 均分批取得通过记录。历史交易画面预置需先启动宿主建立 StoreKit，再插入交易并重启读取快照；不能把测试进程插入交易当作已经传给运行中 App 的购买事件。待批准用例另行验证 Transaction.updates 自动解锁。具体结果与未测项见 STATUS。

## 整 App 导航与辅助功能回归

`Tests/FullAppUITests/FullAppUITests.swift` 与独立 `iMDReaderFullAppQA` scheme 编译完整 iOS App，包含 ReaderScreen、导航、阅读锁和资料管理；不增加生产调试旁路。测试命令指定独立 bundle ID，使用本任务专用模拟器，启动参数 `-IMDPurchaseEnabled -IMDDisableCloudKit`；通过测试进程的 `-readingSampleRemoved NO` 提供可重复的内置示例，不改生产示例移除规则。StoreKit 清空交易不会抹除 App 的 Keychain 权益，测试先通过实际“恢复购买”流程清理旧测试授权，再重启验证首次锁定。采用本地 StoreKitTest，不登录 Apple/GitHub 账号，不读正式 App 数据。请勿把本测试命令指向日常使用的模拟器或真机。

```sh
xcodebuild -project iMDReader.xcodeproj -scheme iMDReaderFullAppQA \
  -destination "platform=iOS Simulator,id=$IMD_TEST_DEVICE" \
  -derivedDataPath "$IMD_QA_DIR/fullapp-build" \
  -resultBundlePath "$IMD_QA_DIR/fullapp.xcresult" \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=YES \
  IMD_BUNDLE_ID=com.example.imdreader.fullapp-qa \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
```

测试附件保留关键画面、可访问性树及未过滤的辅助功能审计。用户反馈模拟器朗读打扰后，已停止 VoiceOver 测试并确认两个专用模拟器关闭朗读；当前测试源码不再启用 VoiceOver，只保留静默 `performAccessibilityAudit`。既有 iPad 焦点遍历文本仅作部分历史证据，不能写成 VoiceOver 全套验收。未经用户另行明确同意，不再运行有声测试。

整 App 需要可访问 Keychain 的模拟器构建；未签名测试曾出现安全凭据不可用提示，干扰导航，因此命令使用本地 ad-hoc 签名，不使用发行证书。所有审计发现均收集后断言，不静默过滤；含屏幕外元素的报告也保留原始位置与截图。导航与购买入口最终在两台模拟器各两项通过；静默辅助功能审计两项仍因未过滤的报告而失败。后续实测 48 次普通/最大字号、浅深色量测均完整可见，未复现字号不缩放；已确认的配色问题仅收敛到浅色锁定层四项文字，用户已确认并实施最小修复；两端浅深色锁定页静默审计无发现，证据及边界见 STATUS。具体通过、失败和未测以 STATUS 为准。

## 状态与权益

ReaderCore 的 `PurchaseAccess` 是不依赖 StoreKit/UIKit 的纯逻辑；输入交易记录、可选 AppTransaction 快照、可选缓存及当前时间，输出状态与更新后的缓存。

| 状态 | 条件 | 行为 |
| --- | --- | --- |
| disabled | 总开关关闭 | 全功能可用，无购买界面、无交易监听 |
| lockedNotStarted | 无有效试用、买断或老用户权益 | 全锁；首次启动自动出示说明页，由用户点击开始试用或购买 |
| trial | 当前有效时间早于起点 + 14×24 小时 | 全功能可用，显示起止日期与剩余整天数（状态携带）；菜单显示剩余天数，最后 3 天 App 内提示，无推送 |
| lockedExpired | 有试用起点且有效时间达到或超过到期点 | 全锁并自动出示到期购买页，购买与恢复可用 |
| unlockedLifetime | 已验证未撤销的买断（含 familyShared），或生产环境确认老用户 | 永久开放，不强迫反复显示购买页 |

用户点击「开始 14 天试用」才调用免费商品的 `Product.purchase()`；不自动购买。起点取试用交易 `originalPurchaseDate`，不是安装时间或本地首次启动时间。到期严格按秒计算，第 14 天刚好到期即锁定；剩余天数为尚余秒数除以 86400 向上取整，到期为 0。试用退款/撤销、未验证交易不授予权益；买断撤销后重新按有效试用、未开始或已到期判断。买断接受 `.familyShared`，不要求先领取试用；共享撤销按 `revocationDate` 处理。

开关开启且锁定时，所有 PremiumFeature 均不可用；解锁后保留 `gatedFeatures` 钩子的既有判断，默认空集合，无额外功能限制。开关关闭时全部钩子放行。

到期后按 KB main 合并提交 `3bc39f7`（PR #22） 第 11.3 节执行：阅读、打开本地文件或文件夹、GitHub 来源、阅读页、目录、文内查找、来源内容、最近文件及外观设置全部锁住，不允许只读打开已有文件。Spotlight、快捷指令、小组件和深链进入都落到购买页，并把待打开的文档/来源暂存；买断或恢复购买成功后立即回到原状态（含原先打开的文档或来源）。不删除任何用户数据。Mac 不受影响。

锁定层保留：购买页、恢复购买、隐私政策、联系方式与版本、语言切换、数据管理（清缓存、移除来源、清 GitHub 授权、关 iCloud 同步）。完成按钮可关闭购买页以访问这些设置，但不能绕过底层锁定。未采纳「只读打开已有文件」。

未开始试用也锁定的代价是首次使用需要明确领取；可替代为先免费阅读再提示试用，但本次代码按已定的「首次启动引导开始试用」实现。

## 离线与缓存

StoreKit 2 `currentEntitlements` 可读取离线本地收据；同时读取 `Transaction.all` 中撤销记录（当前权益序列可能不含退款项），监听 `Transaction.updates`。当前权益序列包含验证通过的记录时，以完整当前快照为准更新交易缓存；仅有历史/更新记录时，按对应商品的验证记录更新或撤销其缓存。用户主动 `AppStore.sync()` 成功后，将重新读取的完整交易结果作为权威快照，包括空结果。普通刷新中的空序列没有错误信号，不能据此区分离线无结果与无购买；无可用当前快照且没有对应商品的验证记录时保留缓存，宁可对已付费者宽松。该策略可能让无法取得撤销记录的设备延后收回权益；收到可验证撤销或主动恢复后会纠正。未验证交易不会新增已买断或试用缓存。

缓存协议 `PurchaseAccessStorage` 位于 ReaderCore，可注入内存存储测试。ReaderApp 的实现使用 Keychain generic password，service = bundleId + `.purchase-access`，独立于 GitHub service，`synchronizable = false`，`WhenUnlockedThisDeviceOnly`。保存试用起始日、是否买断和最大已见时间；不写真实账号、邮箱、密钥。旧缓存里可能仍带有 `productionLegacyUser` 字段，解码兼容但每次评估都会清空，且不用于授予。Keychain 写入失败时保留本次内存结果，后续评估重试写入，不把落盘成功作为解锁条件。若启动时读取失败，本次会话不覆盖可能已有的付费缓存；解锁设备并重新打开 App 后重读，当前会话仍可依据可验证的 StoreKit 记录解锁。

| 无可用 StoreKit 结果 | 离线行为 |
| --- | --- |
| 缓存已买断 | 开放 |
| 仅缓存试用起点 | 起点 + 14 天与最大已见时间判断 |
| 仅缓存旧的生产环境老用户标记、或取不到 AppTransaction | 按新用户处理，不放行；联网拿到已验证生产快照后再判定 |
| 无缓存 | lockedNotStarted；不能永久放行新用户 |

## 老用户升级：已定 B

只用已验证 `AppTransaction.originalAppVersion` 和 `environment`。iOS 的该字段为首次下载的 CFBundleVersion（构建号）：仅 production 且字符串全部为 ASCII 数字、能解析成整数并且整数 ≤53 才授予。按整数比较，`100` 不小于 `54`。未知格式、`1.0`、空串、溢出均不授予。

sandbox、TestFlight（始终沙盒）、Xcode/StoreKit 本地测试（`.xcode`）及未知环境排除；测试环境的 `originalAppVersion` 为 `1.0`，不据此放行，审核员可以看到购买页。非生产结果不得写入老用户 true 缓存；已取得非生产快照时也不使用生产老用户缓存来绕过测试。

只依据当场拿到的已验证 `AppTransaction` 授予老用户。抛错、未验证或取不到快照时按新用户处理，显示试用页，联网后重新判定；不默认放行，不另存老用户标记。参考 [Apple originalAppVersion](https://developer.apple.com/documentation/storekit/apptransaction/originalappversion) 和 [AppTransaction 商业模式变更](https://developer.apple.com/documentation/storekit/supporting-business-model-changes-by-using-the-app-transaction)。

## 时钟篡改策略

采用 Keychain 同一缓存协议中的 `maxObservedNow` 水印，`effectiveNow = max(now, maxObservedNow)`，每次计算更新水印，只用于试用到期计算。买断及老用户直接开放，不受回拨误锁。前台刷新及前台每分钟重新评估，冷启动也评估；没有生产隐藏时间偏移开关。

评估：虽然单价低，回拨仍可白得试用期，加水印成本低，采用此方案。如果先把时钟拨到未来再拨回，试用可能提前到期，此代价可接受。不是可信服务器时间；从未被观察到的回拨、清除缓存后的本地时钟仍有限制，不能声称彻底防篡改。

## 家庭共享与 3.1.1

买断开启家庭共享（`.storekit` 中 `lifetime` 的 `familyShareable = true`）：已验证、未撤销的买断交易，不论 `ownershipType` 为购买者还是 `.familyShared`，均永久解锁，不要求先领取试用。共享撤销按 `revocationDate` 处理。试用关闭家庭共享（`trial14d` 的 `familyShareable = false`）：每人各自试用；家庭共享来的试用交易不授予试用（`isFamilyShared` 不计起点）。Boss 于 2026-11-11 12:14（Asia/Manila）确认这两项设置。Family Sharing 开启后不能关闭，ASC 创建时必须核对。KB main `3bc39f7` 第十二节第 4 项与 3.4 仍写试用为「建议不开、未单独转达确认」，以本次 Boss 确认为准。

按 Guideline 3.1.1：试用名称写明 14 天；领取前明确告知时长及到期后无法打开文档、无法继续使用全部功能，必须买断；购买前显示永久解锁价格。UI 价格只来自 `Product.displayPrice`，不写死美元金额。领取试用与购买永久解锁都要求已加载并展示本地化买断价格（`Product.displayPrice`）；试用商品未加载或价格未展示时禁用「开始 14 天试用」，并提供重试。买断按钮在永久解锁价格未加载时禁用。这是 Guideline 3.1.1 与 KB 9.1 的领取前价格告知要求。最后 3 天 App 内再次提示；到期页提供购买、恢复及设置/支持入口。[Apple 审核指南](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase)。

## 开发者本人正式版使用（用户已确认）

用户同意在付费版本审核通过后，为买断 IAP 创建免费 Offer Code，供自己的账号兑换解锁。此为审核通过后的待办，本轮不创建或兑换，不添加开发者豁免或硬编码账号。实际创建与兑换结果届时单独记录。

## ASC 创建清单（仅清单，本轮不创建）

| 项目 | 买断 | 试用 |
| --- | --- | --- |
| 类型 | 非消耗型 | 免费非消耗型 |
| ID（已定） | `com.readerprototype.3z4gd8c2jp.ipadmarkdownreader.lifetime` | `com.readerprototype.3z4gd8c2jp.ipadmarkdownreader.trial14d` |
| 基准价格档 | USD 2.99（其他地区由 ASC 定价） | 免费 / 0.00 |
| 家庭共享 | 开启 | 关闭（个人一次性试用，开启不可关闭） |

以下名称 ≤30、描述 ≤45 字符，StoreKit 配置一致；繁中、日、韩为 AI 起草、待母语审校。

| 商品 | 语言 | 显示名 | 描述 |
| --- | --- | --- | --- |
| lifetime | en | Lifetime Unlock | Buy once, unlock forever on iPhone and iPad. |
| lifetime | zh-Hans | 永久解锁 | 一次购买，永久解锁，iPhone 和 iPad 通用。 |
| lifetime | ja | 永久アンロック | 一度の購入で永久にアンロック。iPhone と iPad で利用可。 |
| lifetime | ko | 평생 잠금 해제 | 한 번 구매로 영구 잠금 해제. iPhone·iPad 지원. |
| lifetime | zh-Hant | 永久解鎖 | 一次購買，永久解鎖，iPhone 和 iPad 通用。 |
| trial14d | en | 14-day Trial | Try every feature free for 14 days. |
| trial14d | zh-Hans | 14天试用 | 免费试用全部功能14天，到期后需购买永久解锁。 |
| trial14d | ja | 14日間トライアル | 全機能を14日間無料でお試し。期間後は買い切りが必要です。 |
| trial14d | ko | 14일 체험 | 모든 기능을 14일간 무료로 체험. 이후 구매가 필요합니다. |
| trial14d | zh-Hant | 14天試用 | 免費試用全部功能14天，到期後需購買永久解鎖。 |

每个商品准备实际 App 内审核截图（按 ASC 上传要求，建议 640×920）：试用截图应展示时长、到期影响、真实本地价格、领取与恢复；买断截图展示到期锁定、价格、购买与恢复。使用合成文档，不含私人资料。审核备注解释免费旧版 build≤53 的升级权益、测试环境排除及完整购买/恢复路径；首次提交内购须与包含该功能的新 App 版本一同送审。截图及元数据需在 Xcode/Sandbox 实测后制作，不能用文档或编译结果冒充实拍。

## 开关与发版

`PurchaseConfig.current`：iOS Release 默认启用（上线当天收费，无日期开关）；iOS DEBUG 默认关闭，仅 `-IMDPurchaseEnabled` 启用。非 iOS（含 Mac、Linux）永远关闭。`gatedFeatures` 默认空集合。ReaderScreen 的购买菜单、锁定层和购买界面均仅 iOS。

**发版前必须先在 ASC 配好这两个商品。Release 会启用收费；未配置商品时购买/试用不了，但会锁功能。** 商品真实价格与可售性必须 Sandbox/ASC 核对。Mac 不收费、不锁、无购买界面：Mac 不上 Mac App Store，无法使用 App Store 内购；StoreKit 不加入 Mac target。CloudKit 与其启动参数均不改。

发布前同步商店描述、截图和审核备注，说明此前免费、无内购的 0.3.0 与新版商业模式区别；隐私政策按 11.2 在独立 PR #2（`docs/privacy-contact-email`）更新，本分支不改 `privacy.html`。合并该 PR 的 `main` 即 GitHub Pages 发布，正式发布前须报小二。隐私标签提交前对照 Apple 隐私详情复核。DSA 交易者申报（11.1）由 Boss 在 ASC 完成，本轮不进 ASC。

## 验证与重装实测门槛

### 当前设备验收前提（只整理，尚未执行）

此前用户报告完成协议、税务、银行检查及 TestFlight 重测；最新 Chrome 商务页却明确显示付费 App 协议“新”、无生效日期，已请用户处理法律实体信息与付费协议，银行/税务有效状态待独立核实。55 真机商品加载失败；旧入口移除尚未上传，54/55 的安装记录均不能替代当前本地修改或真实交易验收。

| 验证 | 必要条件与可接受证据 |
| --- | --- |
| Apple 服务链路购买 | 采用授权安装的开发签名候选包，或另行授权上传的 TestFlight 候选包；必须使用现有正式 App 标识及两个正确商品 ID。开发包收费开关开启，并将 Xcode scheme 的 StoreKit Configuration 设为 None（现有主 scheme 引用了本地 `.storekit`，不能拿本地模拟交易当 Sandbox）。实际取得两项商品及地区价格，购买后收到已验证的 Sandbox 交易并更新权益。 |
| 设备与账号 | 本轮只读看到两台已配对且开启开发者模式的真机，当前连接分别为 disconnected / unavailable；开发安装需先恢复连接、解锁并获得安装许可。若由用户在 TestFlight 人工操作，不要求 Mac 在线连接，但仍需记录构建和结果。基本 TestFlight 购买不必另建 Sandbox 账号；要使用中断、家庭等 Sandbox 控制时，需同一开发者团队的测试账号和用户登录操作。 |
| 同账号重装 / 恢复 | 领取试用后记录已验证交易的 originalPurchaseDate、起止时间和剩余天数；不清除该 Sandbox 账号购买历史，删除测试 App 后用同账号重装，先冷启动、再恢复，起点不变且不能重复领取。单纯卸载不能证明本地缓存已清空，增加第二台全新测试环境可排除缓存掩盖问题。使用合成资料，不操作日常资料库。 |
| 实际到期 | 本产品是免费非消耗型商品加 App 自行计算的 14×24 小时，不能套用自动续订订阅的 Sandbox 加速时间。Apple 链路的真实到期验收需要原交易已超过 14 天的测试账号，或实际等待；现有 StoreKitTest 历史日期与边界测试只证明本地模型。 |
| 家庭共享 / 撤销 | 至少两个同地区 Sandbox 账号，组成 Sandbox Test Family；买断商品已开启共享，试用商品不共享。建议两台独立测试设备，接收方无自己的买断或其他解锁资格。先验证试用不传给接收方，再验证买断收到 ownershipType=familyShared 并解锁；停止共享后收到带 revocationDate 的更新，按接收方自己的有效权益重新判断。不能只凭“能打开文章”或配置勾选推断通过。 |
| 系统取消与异常 | 真机实际取消 Apple 购买窗口；另测中断后完成、无记录恢复、恢复失败和迟到结果。记录操作与界面变化；本地 userCancelled 注入的 known issue 不算此项已通过。 |
| 老用户生产升级 | 需要真实生产环境旧版购买/下载记录及同账号升级，验证实际 AppTransaction 字段；Sandbox/TestFlight 不证明生产老用户资格。 |

Apple 说明 TestFlight 和开发签名测试的购买均走 Sandbox、不实际扣款；商品元数据更新可能最多约一小时才反映到 Sandbox。若 TestFlight 需要 Sandbox 控制，需按官方流程切换“媒体与购买项目”及 Developer 中的账号，宜在专用测试设备由用户操作，本轮未切换任何账号。[Apple Sandbox 测试说明](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox)

Sandbox 家庭至少两名成员，且地区必须相同；可用一台设备轮换账号，但独立设备更便于排除缓存影响。[Sandbox 家庭设置](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings/#create-a-sandbox-test-family) [共享与撤销验收](https://developer.apple.com/documentation/storekit/testing-family-sharing)

以下保留原有基础测试策略与重装步骤；不代表上述真机条件或验收已经完成。

纯逻辑 Swift 6 / swift-testing 覆盖各状态、恰好第14天、剩余天数向上取整、未验证/撤销、买断撤销后的试用回退、家席共享、离线买断/无缓存、生产数字比较（含边界 53/54、00053）、未知格式/空串/非数字、sandbox/xcode/1.0 排除、取不到 AppTransaction 或仅有旧缓存标记时按新用户、时钟回拨、关闭总开关和缓存协议。另覆盖「交易保留、本地缓存清空」后仍按 `originalPurchaseDate` 回到同一起点，以及 Spotlight / 快捷指令 / 深链在锁定时暂存、解锁后恢复原意图。原开发阶段的 Linux 验证仅运行纯逻辑测试；本次接手新增的 Apple 平台与独立宿主验证见文首及 STATUS，仍不能证明真实重装行为。

上线前**必须实测**同 Apple ID 重装后试用起始日保持。推荐 Sandbox 测试账号（开发签名包，在“设置 > 开发者”登录沙盒账号）或 TestFlight（始终沙盒）。需要 Boss 提供一台可装开发包或 TestFlight 的真机及沙盒测试账号，或授权使用已有账号；不要把账号凭据写进文档。

1. 同一沙盒账号领取试用，记录 `originalPurchaseDate` 与剩余天数。
2. 删除 App，但不要清除沙盒购买记录。
3. 重装，同一账号冷启动，不点「开始试用」；应仍处于同一试用起点，不能再领取。
4. 再点「恢复购买」，检查起点与剩余天数连续。
5. 判定：起点不变、剩余天数连续、不能重复领取；另验证买断、家庭共享/撤销、取消、待批准、恢复失败、完全离线及老用户生产升级。

原开发阶段未在真机或模拟器启动 App。本次接手的原生付费页验证及 Apple SDK 构建见文首和 STATUS；整 App 导航、品牌/工具栏/设置等固定门槛未因独立宿主检查而自动通过。运行方法与实际结果见 [STATUS](STATUS.md) 及 [StoreKit/README](../ReaderApp/StoreKit/README.md)。

## 与 KB main（合并提交 `3bc39f7`，PR #22）的对齐

已对照该提交第十一节、4.3 与 9.1 实现。本仓库实现范围：4.3 老用户规则、11.3 到期入口、试用+买断状态机与测试。11.1 DSA 交易者申报只写入文档，由 Boss 在 ASC 完成。11.2 隐私政策在 PR #2 单独提交，不经本分支、不合 main。

## 原开发阶段测试与复现（历史记录）

Swift 6.1.2 的无依赖临时包直接复制实际两个购买源码/测试文件，Debug 与 Release 各 10 项全部通过；没有启动 App。iOS 三文件语法解析、五语言修改范围/占位符/translated、商品字段/长度、UTF-8 与 diff 检查通过。完整 ReaderCore 的 `swift test` 已尝试，但 Linux 缺少既有 OfflineCache 所需 CryptoKit，未能完成；没有修改该模块来迁就测试。

Apple 开发环境可运行 `swift test --package-path ReaderCore --filter purchase`。本轮在 Linux 使用以下隔离方式（确保 Swift 6 在 PATH；当前环境另需将 `/workspace/swift-toolchain/lib` 加入 LD_LIBRARY_PATH，并将模块/SwiftPM 缓存路径指向可写的 `/tmp`）：

```sh
mkdir -p /tmp/imd-purchase-checks/Sources/ReaderCore /tmp/imd-purchase-checks/Tests/ReaderCoreTests
cp ReaderCore/Sources/ReaderCore/PurchaseAccess.swift /tmp/imd-purchase-checks/Sources/ReaderCore/
cp ReaderCore/Tests/ReaderCoreTests/PurchaseAccessTests.swift /tmp/imd-purchase-checks/Tests/ReaderCoreTests/
cat > /tmp/imd-purchase-checks/Package.swift <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PurchaseChecks", targets: [.target(name: "ReaderCore"), .testTarget(name: "ReaderCoreTests", dependencies: ["ReaderCore"])])
SWIFT
swift test --package-path /tmp/imd-purchase-checks
swift test -c release --package-path /tmp/imd-purchase-checks
```

这些测试不依赖 UIKit、StoreKit 或测试宿主。当前工具链未在 PATH，实际使用 `/workspace/swift-toolchain/swift-6.1.2-RELEASE-ubuntu24.04/usr/bin/swift`，并设置 `XDG_CACHE_HOME=/tmp/imd-swift-cache`、`CLANG_MODULE_CACHE_PATH=/tmp/imd-swift-cache/clang`、`SWIFTPM_MODULECACHE_OVERRIDE=/tmp/imd-swift-cache/modules`，传入 `--cache-path /tmp/imd-swift-cache/pm --config-path /tmp/imd-swift-cache/config --security-path /tmp/imd-swift-cache/security`，不写用户系统目录。
