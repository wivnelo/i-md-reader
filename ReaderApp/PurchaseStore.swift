#if os(iOS) || IMD_PURCHASE_TESTS
import Combine
import Foundation
import ReaderCore
import Security
import StoreKit
import OSLog

enum PurchaseMessage: Equatable, Sendable {
    case productUnavailable, productLoadFailed, productLoadTimedOut, trialUnavailable
    case pending, unverified, purchaseFailed, restored, nothingToRestore, restoreFailed
    case purchaseWaiting, restoreWaiting
}

enum PurchaseOperation {
    case purchasing, restoring, verifying
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

struct PurchaseEntitlementSnapshot: Sendable {
    var records: [EntitlementRecord]
    var app: AppTransactionSnapshot?
    var authoritative: Bool
}

@MainActor
final class PurchaseStore: ObservableObject {
    static let shared = PurchaseStore()
    @Published private(set) var access: PurchaseAccess
    @Published private(set) var product: Product?
    @Published private(set) var trialProduct: Product?
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var catalogMessage: PurchaseMessage?
    @Published private(set) var operation: PurchaseOperation?
    @Published private(set) var isWaitingForRestore = false
    var isBusy: Bool { operation != nil }
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
    private var refreshTask: Task<Bool, Never>?
    private var restoreTask: Task<Void, Never>?
    private var entitlementRevision = 0
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "i-md-reader", category: "Purchase")

    private let fetchProducts: @MainActor @Sendable ([String]) async throws -> [Product]
    private let synchronize: @MainActor @Sendable () async throws -> Void
    private let entitlementReader: (@MainActor @Sendable (Bool) async -> PurchaseEntitlementSnapshot)?
    private let requestTimeout: Duration
    private let operationTimeout: Duration

    init(config: PurchaseConfig = .current, storage: (any PurchaseAccessStorage)? = nil,
         requestTimeout: Duration = .seconds(15), operationTimeout: Duration = .seconds(60),
         fetchProducts: @escaping @MainActor @Sendable ([String]) async throws -> [Product] = { try await Product.products(for: $0) },
         synchronize: @escaping @MainActor @Sendable () async throws -> Void = { try await AppStore.sync() },
         entitlementReader: (@MainActor @Sendable (Bool) async -> PurchaseEntitlementSnapshot)? = nil) {
        self.config = config
        self.fetchProducts = fetchProducts
        self.synchronize = synchronize
        self.entitlementReader = entitlementReader
        self.requestTimeout = requestTimeout
        self.operationTimeout = operationTimeout
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

    deinit { updatesTask?.cancel() }

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
        // Loading prices must not wait for a network-backed AppTransaction read.
        async let refresh: Bool = refreshEntitlements()
        await loadProduct()
        _ = await refresh
    }

    func loadProduct() async {
        guard config.isEnabled, !isLoadingProducts else { return }
        isLoadingProducts = true
        catalogMessage = nil
        defer { isLoadingProducts = false }
        let ids = [config.productID, PurchaseConfig.trialProductID]
        do {
            let products = try await withPurchaseDeadline(requestTimeout) { [self] in
                try await fetchProducts(ids)
            }
            product = products.first { $0.id == self.config.productID }
            trialProduct = products.first { $0.id == PurchaseConfig.trialProductID }
            if product == nil { catalogMessage = .productUnavailable }
            else if trialProduct == nil { catalogMessage = .trialUnavailable }
            let missing = ids.filter { id in !products.contains { $0.id == id } }.joined(separator: ",")
            if !missing.isEmpty { logger.notice("Catalog missing product IDs: \(missing, privacy: .public)") }
        } catch is CancellationError {
            // View cancellation is not an App Store failure.
        } catch {
            catalogMessage = error as? PurchaseRequestError == .timedOut ? .productLoadTimedOut : .productLoadFailed
            logFailure("catalog", error)
        }
    }

    private func logFailure(_ stage: String, _ error: any Error) {
        let value = error as NSError
        // Avoid descriptions/userInfo: these may include account or receipt data.
        logger.error("StoreKit stage=\(stage, privacy: .public) domain=\(value.domain, privacy: .public) code=\(value.code)")
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

    @discardableResult
    func refreshEntitlements(update: VerificationResult<Transaction>? = nil, synced: Bool = false) async -> Bool {
        await refreshEntitlements(verifiedUpdate: update.map(record), synced: synced)
    }

    @discardableResult
    func refreshEntitlements(verifiedUpdate: EntitlementRecord?, synced: Bool = false) async -> Bool {
        guard config.isEnabled else { return true }
        let incoming = verifiedUpdate.flatMap { $0.isVerified ? $0 : nil }
        // Apply a verified purchase/revocation immediately. A network read must not
        // delay granting it, nor may an older snapshot overwrite this update.
        if let incoming {
            entitlementRevision += 1
            apply(records: [incoming], snapshot: appSnapshot, authoritative: false)
            if isUnlocked { message = nil }
        }
        while let refreshTask {
            let refreshed = await refreshTask.value
            // Explicit sync must get a fresh authoritative read after any earlier one.
            if !synced { return refreshed }
        }
        let revision = entitlementRevision
        let task = Task { @MainActor [self] in
            defer { refreshTask = nil; hasRefreshed = true }
            do {
                var snapshot = try await withPurchaseDeadline(requestTimeout) { [self] in
                    if let entitlementReader { return await entitlementReader(synced) }
                    return await readEntitlements(synced: synced)
                }
                guard revision == entitlementRevision else { return true }
                // StoreKit's current sequence may not yet contain the transaction
                // that triggered this refresh. Preserve that verified event.
                if let incoming {
                    snapshot.records.removeAll { $0.transactionID == incoming.transactionID }
                    snapshot.records.append(incoming)
                }
                apply(records: snapshot.records, snapshot: snapshot.app, authoritative: snapshot.authoritative)
                return true
            } catch {
                logFailure("entitlements", error)
                return false
            }
        }
        refreshTask = task
        return await task.value
    }

    private func readEntitlements(synced: Bool) async -> PurchaseEntitlementSnapshot {
        var records: [EntitlementRecord] = []
        var hasVerifiedCurrentEntitlements = false
        for await result in Transaction.currentEntitlements {
            let value = record(result)
            records.append(value)
            if value.isVerified { hasVerifiedCurrentEntitlements = true }
        }
        for await result in Transaction.all {
            let value = record(result)
            if value.isVerified, value.revocationDate != nil {
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
        return PurchaseEntitlementSnapshot(records: records, app: snapshot,
                                   authoritative: synced || hasVerifiedCurrentEntitlements)
    }

    private func apply(records: [EntitlementRecord], snapshot: AppTransactionSnapshot?, authoritative: Bool) {
        appSnapshot = snapshot
        let result = PurchaseAccess.resolve(config: config, records: records, appTransaction: snapshot,
                                           cache: cache, now: Date(), transactionsAreAuthoritative: authoritative)
        cache = result.cache
        access = result.state
        if canPersistCache { try? storage.write(result.cache) }
    }

    func purchase(trial: Bool = false) async {
        guard config.isEnabled, !isBusy else { return }
        if trial, product == nil || trialProduct == nil { message = .productUnavailable; return }
        guard let selected = trial ? trialProduct : product else { message = .productUnavailable; return }
        operation = .purchasing
        message = nil
        // The system sheet can legitimately wait for user input. Report a long
        // wait without treating it as a cancelled transaction or allowing duplicates.
        let operationTimeout = self.operationTimeout
        let watchdog = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: operationTimeout) } catch { return }
            if self?.operation == .purchasing { self?.message = .purchaseWaiting }
        }
        defer { watchdog.cancel(); operation = nil }
        do {
            switch try await selected.purchase() {
            case .success(.verified(let transaction)):
                operation = .verifying
                message = nil
                await refreshEntitlements(update: .verified(transaction))
                await transaction.finish()
            case .success(.unverified): message = .unverified
            case .userCancelled: message = nil
            case .pending: message = .pending
            @unknown default: message = .purchaseFailed
            }
        } catch StoreKitError.userCancelled { message = nil }
        catch { message = .purchaseFailed; logFailure("purchase", error) }
    }

    func restore() async {
        guard config.isEnabled, !isWaitingForRestore else { return }
        guard operation == nil || operation == .restoring else { return }
        // Keep one underlying sync alive across UI timeouts. Retrying observes
        // that same request; it never opens a second Apple authentication flow.
        if restoreTask == nil {
            operation = .restoring
            message = nil
            restoreTask = Task { @MainActor [self] in
                defer { restoreTask = nil; operation = nil }
                do {
                    try await synchronize()
                    let refreshed = await refreshEntitlements(synced: true)
                    message = refreshed ? (isUnlocked ? .restored : .nothingToRestore) : .restoreFailed
                } catch StoreKitError.userCancelled { message = nil }
                catch { message = .restoreFailed; logFailure("restore", error) }
            }
        }
        guard let task = restoreTask else { return }
        isWaitingForRestore = true
        defer { isWaitingForRestore = false }
        do {
            try await withPurchaseDeadline(operationTimeout) { await task.value }
        } catch is CancellationError {
            // The retained task still reconciles a late result after the sheet closes.
        } catch {
            if operation == .restoring { message = .restoreWaiting }
            logFailure("restore-wait", error)
        }
    }

    func updateClock() {
        guard config.isEnabled else { return }
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
