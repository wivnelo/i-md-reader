#if os(iOS)
import Combine
import ReaderCore
import StoreKit

enum PurchaseMessage: Sendable {
    case productUnavailable, pending, unverified, purchaseFailed, restored, nothingToRestore, restoreFailed
}

@MainActor
final class PurchaseStore: ObservableObject {
    static let shared = PurchaseStore()

    @Published private(set) var isUnlocked = false
    @Published private(set) var product: Product?
    @Published private(set) var isBusy = false
    @Published private(set) var message: PurchaseMessage?

    let config: PurchaseConfig
    private var hasStarted = false
    private var updatesTask: Task<Void, Never>?

    init(config: PurchaseConfig = .current) {
        self.config = config
    }

    func start() async {
        guard config.isEnabled, !hasStarted else { return }
        hasStarted = true
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        await loadProduct()
        await refreshEntitlements()
    }

    /// 商品加载失败时，购买弹窗打开会再试一次。
    func loadProduct() async {
        guard config.isEnabled, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            product = try await Product.products(for: [config.productID]).first
            message = product == nil ? .productUnavailable : nil
        } catch {
            message = .productUnavailable
        }
    }

    func refreshEntitlements() async {
        guard config.isEnabled else { return }
        var records: [EntitlementRecord] = []
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                records.append(EntitlementRecord(productID: transaction.productID, isVerified: true, revocationDate: transaction.revocationDate))
            case .unverified(let transaction, _):
                records.append(EntitlementRecord(productID: transaction.productID, isVerified: false, revocationDate: transaction.revocationDate))
            }
        }
        isUnlocked = PremiumAccess.isUnlocked(records, config: config)
    }

    func purchase() async {
        guard config.isEnabled, !isBusy else { return }
        guard let product else { message = .productUnavailable; return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshEntitlements()
            case .success(.unverified): message = .unverified
            case .userCancelled: break
            case .pending: message = .pending
            @unknown default: message = .purchaseFailed
            }
        } catch {
            message = .purchaseFailed
        }
    }

    func restore() async {
        guard config.isEnabled, !isBusy else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            // 仅用户点击“恢复购买”时调用，启动及回前台不触发账户同步。
            try await AppStore.sync()
            await refreshEntitlements()
            message = isUnlocked ? .restored : .nothingToRestore
        } catch {
            message = .restoreFailed
        }
    }

    /// 将来在功能入口调用 store.isAvailable(.imageZoom)；当前无功能接入，gatedFeatures 为空。
    func isAvailable(_ feature: PremiumFeature) -> Bool {
        PremiumAccess.isAvailable(feature, config: config, isUnlocked: isUnlocked)
    }
}
#endif
