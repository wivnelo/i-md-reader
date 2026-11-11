# StoreKit 本地配置

iOS scheme 已挂载 `iMDReader.storekit`，保持 scheme 不变。两个已定的非消耗型商品：

- `com.readerprototype.3z4gd8c2jp.ipadmarkdownreader.lifetime`：Lifetime Unlock，测试价 2.99，familyShareable = true。
- `com.readerprototype.3z4gd8c2jp.ipadmarkdownreader.trial14d`：14-day Trial，免费 0.00，familyShareable = false。个人 Apple ID 一次性试用，家庭共享开启后不能关闭。

五语言名称/描述与 [IAP ASC 清单](../../docs/IAP.md) 一致；界面仅显示 `Product.displayPrice`。本地配置不代表 ASC 商品已创建。

iOS DEBUG 默认关闭，在 Run → Arguments 勾选 `-IMDPurchaseEnabled` 才启用。iOS Release 默认启用，忽略该参数；**发版前必须先配置 ASC 两个商品，否则会锁功能但无法领取/购买**。Mac/Linux 永远关闭。

在 Xcode 验证：首次说明页不自动购买 → 点击领取 → 全功能开放与菜单剩余天数 → 最后三天提示 → 恰好14天到期全锁 → 买断/恢复。另测取消、待批准、失败、退款/撤销、家庭共享买断及撤销、重启与离线缓存、关闭开关后所有旧功能。锁定后检查 GitHub、iCloud、离线缓存/清缓存、隐私、支持入口仍可达。测试环境不享受生产老用户升级权益；时间试验用 StoreKit 测试工具或测试注入，不加生产时间偏移开关。

本轮只做纯逻辑测试，不启动 App。未创建 StoreKitTest App host。上线前需按 IAP 文档在 Sandbox/真机测试领取 → 记下 originalPurchaseDate → 删除 App（保留购买记录）→ 同账号重装且不再点击领取 → 恢复购买；起点不变、剩余天数连续且不能重复领取才通过。纯逻辑「清空缓存但保留交易」覆盖不替代此实测。
