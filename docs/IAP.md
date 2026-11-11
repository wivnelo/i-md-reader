# iOS：14 天全功能免费试用 + 到期后买断

2026-11-11 Boss 已定，替代旧占位方案；实现位于 `feat/storekit-purchase`，尚未发布。当前正式 0.3.0（53）免费上架，已上架最高 build 为 53（见 [STATUS](STATUS.md)）。本轮不改版本、不创建 ASC 商品、不启动 App、不安装、提交或发布。

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

到期后按 KB PR #22 提交 `40fde35` 第 11.3 节执行：阅读、打开本地文件或文件夹、GitHub 来源、阅读页、目录、文内查找、来源内容、最近文件及外观设置全部锁住，不允许只读打开已有文件。Spotlight、快捷指令、小组件和深链进入都落到购买页，并把待打开的文档/来源暂存；买断或恢复购买成功后立即回到原状态（含原先打开的文档或来源）。不删除任何用户数据。Mac 不受影响。

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

买断开启家庭共享，已验证、未撤销的共享交易永久解锁。试用关闭家庭共享：试用是按 Apple ID 领取的个人一次性权益；Family Sharing 开启后不能关闭，创建时必须核对。

按 Guideline 3.1.1：试用名称写明 14 天；领取前明确告知时长及到期后无法打开文档、无法继续使用全部功能，必须买断；购买前显示永久解锁价格。UI 价格只来自 `Product.displayPrice`，不写死美元金额。领取试用只需试用商品已加载；买断按钮在永久解锁价格未加载时禁用。最后 3 天 App 内再次提示；到期页提供购买、恢复及设置/支持入口。[Apple 审核指南](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase)。

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

纯逻辑 Swift 6 / swift-testing 覆盖各状态、恰好第14天、剩余天数向上取整、未验证/撤销、买断撤销后的试用回退、家席共享、离线买断/无缓存、生产数字比较（含边界 53/54、00053）、未知格式/空串/非数字、sandbox/xcode/1.0 排除、取不到 AppTransaction 或仅有旧缓存标记时按新用户、时钟回拨、关闭总开关和缓存协议。另覆盖「交易保留、本地缓存清空」后仍按 `originalPurchaseDate` 回到同一起点，以及 Spotlight / 快捷指令 / 深链在锁定时暂存、解锁后恢复原意图。本轮没有增加会启动 App 的 test host；当前 Linux 环境无 StoreKitTest/Apple SDK，仅运行纯逻辑测试，不能证明 StoreKit 重装行为。

上线前**必须实测**同 Apple ID 重装后试用起始日保持。推荐 Sandbox 测试账号（开发签名包，在“设置 > 开发者”登录沙盒账号）或 TestFlight（始终沙盒）。需要 Boss 提供一台可装开发包或 TestFlight 的真机及沙盒测试账号，或授权使用已有账号；不要把账号凭据写进文档。

1. 同一沙盒账号领取试用，记录 `originalPurchaseDate` 与剩余天数。
2. 删除 App，但不要清除沙盒购买记录。
3. 重装，同一账号冷启动，不点「开始试用」；应仍处于同一试用起点，不能再领取。
4. 再点「恢复购买」，检查起点与剩余天数连续。
5. 判定：起点不变、剩余天数连续、不能重复领取；另验证买断、家庭共享/撤销、取消、待批准、恢复失败、完全离线及老用户生产升级。

本轮不在真机或模拟器启动 App。视觉、五语言长文布局、iPhone 单栏旋转/iPad 双栏、明暗、现有品牌/工具栏/设置可达性以及 Apple SDK 类型检查均待 Xcode 验证，不能记为通过。运行方法与实际结果见 [STATUS](STATUS.md) 及 [StoreKit/README](../ReaderApp/StoreKit/README.md)。

## 与 KB PR #22（提交 40fde35）的对齐

已对照该提交第十一节、4.3 与 9.1 实现。本仓库实现范围：4.3 老用户规则、11.3 到期入口、试用+买断状态机与测试。11.1 DSA 交易者申报只写入文档，由 Boss 在 ASC 完成。11.2 隐私政策在 PR #2 单独提交，不经本分支、不合 main。

## 本轮实际测试与复现

Swift 6.1.2 的无依赖临时包直接复制实际两个购买源码/测试文件，Debug 与 Release 各 9 项全部通过；没有启动 App。iOS 三文件语法解析、五语言修改范围/占位符/translated、商品字段/长度、UTF-8 与 diff 检查通过。完整 ReaderCore 的 `swift test` 已尝试，但 Linux 缺少既有 OfflineCache 所需 CryptoKit，未能完成；没有修改该模块来迁就测试。

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
