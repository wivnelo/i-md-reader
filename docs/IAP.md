# iOS 一次性买断接入

范围：仅 iPhone/iPad 的 StoreKit 2 非消耗型；Mac 继续 GitHub 直装，工程源码清单未接入。无版本号、发布或隐私政策改动。

- 已验证（源码/纯逻辑范围）：唯一总开关为 `ReaderCore/Sources/ReaderCore/PurchaseAccess.swift` 的 `PurchaseConfig.current`，默认关闭；仅 DEBUG 允许 `-IMDPurchaseEnabled`。关闭时无入口、不加载商品、不监听交易、不锁功能。`gatedFeatures` 为空，现有功能均未接入限制。
- 占位：`PurchaseConfig.placeholderProductID` 为 `com.placeholder.imdreader.pro`；Boss 未定，最终见 KB PR#20，创建后不可改不可重用。本地配置 `ReaderApp/StoreKit/iMDReader.storekit` 的名称/描述与测试价格均为 PLACEHOLDER；UI 只用 `Product.displayPrice`。
- 接入方式（待 Boss 确认后）：在 `PremiumFeature` 定义确认的功能，将其加入 `gatedFeatures`，再在 iOS 功能入口调用 `PurchaseStore.shared.isAvailable(feature)`。当前五项仅候选，不展示解锁清单，不改变既有功能。

## 验证

已验证（Linux）：5 个新增/改动 Swift 文件语法解析通过，3 个 App 文件另以 iOS target 做语法解析（不做类型检查）；`swift test --filter PurchaseAccessTests` 因 github.com DNS 失败无法拉取依赖，改用 swiftc 独立构建纯逻辑模块并运行新增 swift-testing 测试，7 项全部通过，使用 Swift 6 严格并发模式。另运行 DEBUG/Release 配置断言，确认参数仅 DEBUG 生效。11 个文件严格 UTF-8、JSON/XML、工程括号/ID 引用/重复 ID、`git diff --check` 检查通过；既有文案及顺序、PBXProject/Mac/Widget 对象保持不变。这些不能证明 iOS 编译或交互通过。

未验证：Xcode 16 StoreKit 配置兼容性、Swift 6 iOS SDK 类型及并发检查、商品加载/真实本地价格、购买/取消/待批准/未验证交易/恢复/退款撤销、跨设备与重启权益；iPhone/iPad 中英文、明暗、菜单开关前后逐项一致、弹窗关闭及既定导航布局回归。按 StoreKit/README.md 在 Xcode 本地配置验证后，还需 Sandbox 与真实商品核对；尚未接入正式商品或提交商店。

## 发布前隐私与商店清单（KB PR#20 第六节 9–11，未验证）

- 隐私政策增加购买说明：付款由 Apple 处理；App 不接收支付信息；买断状态由 StoreKit 在设备上判断；恢复与退款走 Apple。与隐私政策修正合并发布，生效日期改为实际发布日。本轮不修改 `privacy.html`。
- 隐私标签现为“未收集数据”。推断：不接收也不保存购买记录预计可维持；提交前须对照 Apple 隐私详情与最终数据流重新核对，不能当作已确认结论。
- 推断，须核对：PrivacyInfo.xcprivacy 暂不需改，StoreKit 不在 required-reason API 名单内；发布前对照 Apple 当时的名单与最终 API 使用复核。
- README、商店描述与截图须写明最终付费内容，本轮按范围不修改。
- 审核备注须更新：此前已回复完全免费、无内购；新版本必须解释最终买断范围、购买与恢复步骤及审核测试方式。
