# StoreKit 本地配置

全部为 PLACEHOLDER：商品 ID、0.99 测试价、名称、描述与家庭共享策略均未定，不代表正式售价或付费范围。界面价格只读 Product.displayPrice。

在 Xcode 16 或更新版本打开 iOS 的 iMDReader scheme（已挂载此配置），在 Run → Arguments 勾选默认未勾选的 `-IMDPurchaseEnabled`，以 DEBUG 运行。可在 StoreKit 交易管理器检查购买、取消、待批准、恢复、退款/撤销与重新启动后的权益。取消勾选后确认菜单无购买入口、功能与原来一致。Release 忽略该参数。Linux 未验证这些步骤。

真实 ID 创建后不可改、不可重用（KB PR#20）。确定后同步修改 ReaderCore 的 PurchaseConfig.placeholderProductID、本配置 productID、App Store Connect 商品与相关测试断言；正式名称、描述、价格、家庭共享及付费范围另需确认。发布前完成 docs/IAP.md 的核对清单。
