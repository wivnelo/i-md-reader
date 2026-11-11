#if os(iOS)
import Combine
import Foundation
import ReaderCore
import Security
import StoreKit

enum PurchaseMessage: Sendable {
    case productUnavailable, pending, unverified, purchaseFailed, restored, nothingToRestore, restoreFailed, cancelled
}

@MainActor
private final class PurchaseKeychain: PurchaseAccessStorage {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "i-md-reader") + ".purchase-access",
         kSecAttrAccount as String: "access", kSecAttrSynchronizable as String: false]
    }
    func read() throws -> PurchaseAccessCache? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CocoaError(.fileReadNoPermission) }
        return try JSONDecoder().decode(PurchaseAccessCache.self, from: data)
    }
    func write(_ cache: PurchaseAccessCache) throws {
        let values: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(cache),
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil) == errSecSuccess else {
                throw CocoaError(.fileWriteNoPermission)
            }
        } else if status != errSecSuccess { throw CocoaError(.fileWriteNoPermission) }
    }
}

@MainActor
final class PurchaseStore: ObservableObject {
    static let shared = PurchaseStore()
    @Published private(set) var access: PurchaseAccess
    @Published private(set) var product: Product?
    @Published private(set) var trialProduct: Product?
    @Published private(set) var isBusy = false
    @Published private(set) var message: PurchaseMessage?
    @Published private(set) var hasRefreshed = false
    var isUnlocked: Bool { access.isUnlocked }
    let config: PurchaseConfig
    private let storage: any PurchaseAccessStorage
    private var cache: PurchaseAccessCache?
    private let canPersistCache: Bool
    private var appSnapshot: AppTransactionSnapshot?
    private var hasStarted = false
    private var updatesTask: Task<Void, Never>?
    private var isRefreshing = false

    init(config: PurchaseConfig = .current, storage: (any PurchaseAccessStorage)? = nil) {
        self.config = config
        let vault = storage ?? PurchaseKeychain()
        self.storage = vault
        let cached: PurchaseAccessCache?
        do {
            cached = try vault.read()
            canPersistCache = true
        } catch {
            cached = nil
            // Do not overwrite an unreadable paid cache with a provisional empty state.
            canPersistCache = false
        }
        self.cache = cached
        self.access = PurchaseAccess.resolve(config: config, records: nil, cache: cached, now: Date()).state
    }

    func start() async {
        guard config.isEnabled, !hasStarted else { return }
        hasStarted = true
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                await self?.refreshEntitlements(update: result)
                if case .verified(let transaction) = result { await transaction.finish() }
            }
        }
        await refreshEntitlements()
        await loadProduct()
    }

    func loadProduct() async {
        guard config.isEnabled, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let products = try await Product.products(for: [config.productID, PurchaseConfig.trialProductID])
            product = products.first { $0.id == config.productID }
            trialProduct = products.first { $0.id == PurchaseConfig.trialProductID }
            message = product == nil || trialProduct == nil ? .productUnavailable : nil
        } catch { message = .productUnavailable }
    }

    private func record(_ result: VerificationResult<Transaction>) -> EntitlementRecord {
        let transaction: Transaction
        let verified: Bool
        switch result {
        case .verified(let value): transaction = value; verified = true
        case .unverified(let value, _): transaction = value; verified = false
        }
        return EntitlementRecord(productID: transaction.productID, isVerified: verified,
                                 revocationDate: transaction.revocationDate,
                                 originalPurchaseDate: transaction.originalPurchaseDate,
                                 isFamilyShared: transaction.ownershipType == .familyShared,
                                 transactionID: String(transaction.id))
    }

    func refreshEntitlements(update: VerificationResult<Transaction>? = nil, synced: Bool = false) async {
        guard config.isEnabled else { return }
        // Serialize reads so an older snapshot cannot overwrite a revocation update.
        if isRefreshing {
            while isRefreshing {
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            }
        }
        isRefreshing = true
        defer { isRefreshing = false }
        var records: [EntitlementRecord] = []
        var hasVerifiedCurrentEntitlements = false
        for await result in Transaction.currentEntitlements {
            let value = record(result)
            records.append(value)
            if value.isVerified { hasVerifiedCurrentEntitlements = true }
        }
        // History includes refunded/revoked transactions omitted from currentEntitlements.
        for await result in Transaction.all {
            let value = record(result)
            if value.isVerified, value.revocationDate != nil {
                records.removeAll { $0.transactionID == value.transactionID }
                records.append(value)
            }
        }
        if let update {
            let value = record(update)
            if value.isVerified {
                records.removeAll { $0.transactionID == value.transactionID }
                records.append(value)
            }
        }
        var snapshot: AppTransactionSnapshot?
        if let result = try? await AppTransaction.shared, case .verified(let transaction) = result {
            let environment: AppTransactionSnapshot.Environment
            switch transaction.environment {
            case .production: environment = .production
            case .sandbox: environment = .sandbox
            case .xcode: environment = .xcode
            default: environment = .unknown
            }
            snapshot = AppTransactionSnapshot(originalAppVersion: transaction.originalAppVersion, environment: environment)
        }
        appSnapshot = snapshot
        // A verified current-entitlement snapshot (or explicit sync) supersedes transaction cache.
        // Empty sequences have no error signal: retain cache unless history/updates verify a change.
        let result = PurchaseAccess.resolve(config: config, records: records, appTransaction: snapshot,
                                           cache: cache, now: Date(),
                                           transactionsAreAuthoritative: synced || hasVerifiedCurrentEntitlements)
        cache = result.cache
        access = result.state
        if canPersistCache { try? storage.write(result.cache) }
        hasRefreshed = true
    }

    func purchase(trial: Bool = false) async {
        guard config.isEnabled, !isBusy else { return }
        if trial, product == nil || trialProduct == nil { message = .productUnavailable; return }
        guard let selected = trial ? trialProduct : product else { message = .productUnavailable; return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            switch try await selected.purchase() {
            case .success(.verified(let transaction)):
                await refreshEntitlements(update: .verified(transaction))
                await transaction.finish()
            case .success(.unverified): message = .unverified
            case .userCancelled: message = .cancelled
            case .pending: message = .pending
            @unknown default: message = .purchaseFailed
            }
        } catch { message = .purchaseFailed }
    }

    func restore() async {
        guard config.isEnabled, !isBusy else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            // Only an explicit user action calls sync.
            try await AppStore.sync()
            await refreshEntitlements(synced: true)
            message = isUnlocked ? .restored : .nothingToRestore
        } catch StoreKitError.userCancelled { message = .cancelled }
        catch { message = .restoreFailed }
    }

    func updateClock() {
        guard config.isEnabled, !isRefreshing else { return }
        let result = PurchaseAccess.resolve(config: config, records: nil, appTransaction: appSnapshot, cache: cache, now: Date())
        cache = result.cache
        access = result.state
        if canPersistCache { try? storage.write(result.cache) }
    }

    func isAvailable(_ feature: PremiumFeature) -> Bool {
        PremiumAccess.isAvailable(feature, config: config, isUnlocked: isUnlocked)
    }
}
#endif
