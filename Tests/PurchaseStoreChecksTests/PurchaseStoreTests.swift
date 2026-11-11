import Foundation
import StoreKit
import Testing
import ReaderCore
@testable import PurchaseStoreChecks

@MainActor private final class MemoryStorage: PurchaseAccessStorage {
    var cache: PurchaseAccessCache?
    init(_ cache: PurchaseAccessCache? = nil) { self.cache = cache }
    func read() throws -> PurchaseAccessCache? { cache }
    func write(_ cache: PurchaseAccessCache) throws { self.cache = cache }
}

@MainActor private final class SuspendedRequest {
    var continuation: CheckedContinuation<Void, Never>?
    var calls = 0
    func wait() async {
        calls += 1
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(); continuation = nil }
}

@MainActor private func snapshot(paid: Bool = false) -> PurchaseEntitlementSnapshot {
    PurchaseEntitlementSnapshot(records: paid ? [EntitlementRecord(
        productID: PurchaseConfig.lifetimeProductID, isVerified: true,
        originalPurchaseDate: Date(), transactionID: "test-only")] : [],
        app: nil, authoritative: true)
}

@Test @MainActor func catalogDistinguishesEmptyFailureAndTimeoutAndAllowsRetry() async {
    let gate = SuspendedRequest()
    var attempt = 0
    let store = PurchaseStore(config: .init(isEnabled: true), storage: MemoryStorage(),
                              requestTimeout: .milliseconds(30), fetchProducts: { _ in
        attempt += 1
        switch attempt {
        case 1: throw URLError(.notConnectedToInternet)
        case 2: await gate.wait(); return []
        default: return []
        }
    })
    await store.loadProduct()
    #expect(store.catalogMessage == .productLoadFailed)
    await store.loadProduct()
    #expect(store.catalogMessage == .productLoadTimedOut)
    #expect(!store.isLoadingProducts)
    await store.loadProduct()
    #expect(store.catalogMessage == .productUnavailable)
    #expect(attempt == 3)
    gate.finish()
    await Task.yield()
    #expect(store.catalogMessage == .productUnavailable)
    #expect(!store.isBusy)
}

@Test @MainActor func restoreWorksWhileCatalogIsStillLoading() async {
    let gate = SuspendedRequest()
    let store = PurchaseStore(config: .init(isEnabled: true), storage: MemoryStorage(),
                              requestTimeout: .seconds(2), fetchProducts: { _ in await gate.wait(); return [] },
                              synchronize: {}, entitlementReader: { _ in snapshot(paid: true) })
    let loading = Task { await store.loadProduct() }
    while gate.continuation == nil { await Task.yield() }
    #expect(store.isLoadingProducts)
    #expect(!store.isBusy)
    await store.restore()
    #expect(store.message == .restored)
    #expect(store.isUnlocked)
    #expect(store.isLoadingProducts)
    gate.finish()
    await loading.value
}

@Test @MainActor func restoreReportsNoPurchaseErrorAndCancellation() async {
    let empty = PurchaseStore(config: .init(isEnabled: true), storage: MemoryStorage(),
                              synchronize: {}, entitlementReader: { _ in snapshot() })
    await empty.restore()
    #expect(empty.message == .nothingToRestore)
    #expect(!empty.isBusy)
    let failed = PurchaseStore(config: .init(isEnabled: true), storage: MemoryStorage(),
                               synchronize: { throw URLError(.notConnectedToInternet) })
    await failed.restore()
    #expect(failed.message == .restoreFailed)
    #expect(!failed.isBusy)
    let cancelled = PurchaseStore(config: .init(isEnabled: true), storage: MemoryStorage(),
                                  synchronize: { throw StoreKitError.userCancelled })
    await cancelled.restore()
    #expect(cancelled.message == nil)
    #expect(!cancelled.isBusy)
}

@Test @MainActor func restoreTimeoutRetryDoesNotDuplicateSyncAndLateSuccessUnlocks() async {
    let gate = SuspendedRequest()
    let store = PurchaseStore(config: .init(isEnabled: true), storage: MemoryStorage(),
                              operationTimeout: .milliseconds(30), synchronize: { await gate.wait() },
                              entitlementReader: { _ in snapshot(paid: true) })
    await store.restore()
    #expect(store.message == .restoreWaiting)
    #expect(store.operation == .restoring)
    #expect(!store.isWaitingForRestore)
    await store.restore()
    #expect(gate.calls == 1)
    #expect(store.message == .restoreWaiting)
    gate.finish()
    // Completion updates the actual controller even with no UI waiter remaining.
    while store.operation != nil { await Task.yield() }
    #expect(store.message == .restored)
    #expect(store.isUnlocked)
}

@Test @MainActor func entitlementTimeoutPreservesCacheAndIsNotReportedAsNothingToRestore() async {
    let gate = SuspendedRequest()
    let storage = MemoryStorage(.init(hasLifetime: true, maxObservedNow: Date()))
    let store = PurchaseStore(config: .init(isEnabled: true), storage: storage,
                              requestTimeout: .milliseconds(30), synchronize: {}, entitlementReader: { _ in
        await gate.wait()
        return snapshot()
    })
    await store.restore()
    #expect(store.message == .restoreFailed)
    #expect(store.isUnlocked)
    #expect(storage.cache?.hasLifetime == true)
    #expect(store.hasRefreshed)
    gate.finish()
    await Task.yield()
    #expect(store.isUnlocked)
}

@Test @MainActor func catalogCanLoadDuringEntitlementRefresh() async {
    let gate = SuspendedRequest()
    var fetched = false
    let store = PurchaseStore(config: .init(isEnabled: true), storage: MemoryStorage(),
                              fetchProducts: { _ in fetched = true; return [] }, entitlementReader: { _ in
        await gate.wait()
        return snapshot()
    })
    // Exercise the two operations used by start without opening a live StoreKit listener.
    let refresh = Task { await store.refreshEntitlements() }
    while gate.continuation == nil { await Task.yield() }
    await store.loadProduct()
    #expect(fetched)
    #expect(store.catalogMessage == .productUnavailable)
    gate.finish()
    _ = await refresh.value
}

@Test @MainActor func verifiedPurchaseSurvivesStoreKitSnapshotLag() async {
    let store = PurchaseStore(config: .init(isEnabled: true), storage: MemoryStorage(),
                              entitlementReader: { _ in snapshot() })
    let bought = EntitlementRecord(productID: PurchaseConfig.lifetimeProductID, isVerified: true,
                                  originalPurchaseDate: Date(), transactionID: "new-purchase")
    await store.refreshEntitlements(verifiedUpdate: bought)
    #expect(store.access == .unlockedLifetime)
}

@Test @MainActor func revocationCannotBeOverwrittenByAnOlderInFlightSnapshot() async {
    let gate = SuspendedRequest()
    let store = PurchaseStore(config: .init(isEnabled: true),
                              storage: MemoryStorage(.init(hasLifetime: true, maxObservedNow: Date())),
                              entitlementReader: { _ in await gate.wait(); return snapshot(paid: true) })
    let oldRefresh = Task { await store.refreshEntitlements() }
    while gate.continuation == nil { await Task.yield() }
    let revoked = EntitlementRecord(productID: PurchaseConfig.lifetimeProductID, isVerified: true,
                                   revocationDate: Date(), originalPurchaseDate: Date(), transactionID: "test-only")
    let update = Task { await store.refreshEntitlements(verifiedUpdate: revoked) }
    while store.isUnlocked { await Task.yield() }
    gate.finish()
    _ = await oldRefresh.value
    _ = await update.value
    #expect(!store.isUnlocked)
}
