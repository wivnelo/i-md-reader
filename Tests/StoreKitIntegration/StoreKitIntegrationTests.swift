import Foundation
import StoreKit
import StoreKitTest
import Testing
import ReaderCore
@testable import iMDReaderStoreKitHost

private final class TestBundle: NSObject {}
@MainActor private final class MemoryStorage: PurchaseAccessStorage {
    var cache: PurchaseAccessCache?
    func read() throws -> PurchaseAccessCache? { cache }
    func write(_ cache: PurchaseAccessCache) throws { self.cache = cache }
}

// SKTestSession controls one shared environment; never parallelize these tests.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct StoreKitIntegrationTests {
    @MainActor private func session() throws -> SKTestSession {
        let url = try #require(Bundle(for: TestBundle.self).url(forResource: "iMDReader", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.storefront = "USA"
        session.locale = Locale(identifier: "en_US")
        return session
    }

    @MainActor private func store() -> PurchaseStore {
        PurchaseStore(config: .init(isEnabled: true), storage: MemoryStorage())
    }

    @MainActor private func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(condition())
    }

    @Test @MainActor func productsPriceAndSharingFlags() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let store = store()
        await store.loadProduct()
        let lifetime = try #require(store.product)
        let trial = try #require(store.trialProduct)
        #expect(lifetime.price == Decimal(string: "2.99"))
        #expect(trial.price == 0)
        #expect(!lifetime.displayPrice.isEmpty)
        #expect(lifetime.isFamilyShareable)
        #expect(!trial.isFamilyShareable)
        #expect(store.catalogMessage == nil)
        #expect(store.access == .lockedNotStarted)
    }

    @Test @MainActor func trialPurchaseAndFreshLocalStateKeepOriginalStart() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let first = store()
        await first.start()
        await first.purchase(trial: true)
        guard case .trial(let start, let end, _) = first.access else {
            Issue.record("Verified free trial did not unlock: \(first.access)"); return
        }
        #expect(end.timeIntervalSince(start) == 14 * 86400)
        let fresh = store()
        await fresh.refreshEntitlements()
        guard case .trial(let restoredStart, _, _) = fresh.access else {
            Issue.record("Fresh in-memory state did not recover trial"); return
        }
        #expect(restoredStart == start)
        await fresh.restore()
        #expect(fresh.message == .restored)
        // Fresh controller/cache is a local-state reset, not an actual app reinstall.
        #expect(session.allTransactions().count == 1)
    }

    @Test @MainActor func expiredTrialCanBuyLifetimeAndRefundRelocks() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        try await session.buyProduct(identifier: PurchaseConfig.trialProductID,
                                     options: [.purchaseDate(Date().addingTimeInterval(-15 * 86400))])
        let store = store()
        await store.start()
        #expect(store.access == .lockedExpired, "Observed: \(store.access)")
        await store.purchase()
        #expect(store.access == .unlockedLifetime)
        let bought = try #require(session.allTransactions().first { $0.productIdentifier == PurchaseConfig.lifetimeProductID })
        try session.refundTransaction(identifier: bought.identifier)
        try await eventually { store.access == .lockedExpired }
    }

    @Test @MainActor func pendingApprovalUnlocksThroughTransactionUpdates() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        session.askToBuyEnabled = true
        let store = store()
        await store.start()
        await store.purchase()
        #expect(store.message == .pending)
        #expect(!store.isUnlocked)
        let pending = try #require(session.allTransactions().first { $0.pendingAskToBuyConfirmation })
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        try await eventually { store.access == .unlockedLifetime }
        #expect(store.message == nil)
    }

    @Test @MainActor func purchaseErrorRemainsLocked() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let store = store()
        await store.start()
        try await session.setSimulatedError(.generic(.unknown), forAPI: .purchase)
        await store.purchase()
        #expect(store.message == .purchaseFailed)
        #expect(!store.isUnlocked)
        #expect(!store.isBusy)
    }

    @Test @MainActor func simulatedUserCancellation() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let store = store()
        await store.start()
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        let product = try #require(store.product)
        do {
            let result = try await product.purchase()
            guard case .userCancelled = result else {
                Issue.record("Cancellation simulation returned an unexpected result"); return
            }
        } catch StoreKitError.unknown {
            // Xcode 27.2 with the iOS 27.0 runtime returns .unknown for this
            // injected cancellation. Keep this limitation visible; do not add
            // production error-code guesses to make a simulator test green.
            withKnownIssue("Local StoreKit cancellation injection returns .unknown; real system-sheet cancellation remains unverified") {
                Issue.record("Requested .userCancelled, received .unknown")
            }
            return
        }
        await store.purchase()
        #expect(store.message == nil)
        #expect(!store.isUnlocked)
        #expect(!store.isBusy)
    }

    @Test @MainActor func catalogFailureCanRetryAndRestoreWorksWithoutCatalog() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        try await session.buyProduct(identifier: PurchaseConfig.lifetimeProductID)
        let store = store()
        try await session.setSimulatedError(.generic(.unknown), forAPI: .loadProducts)
        await store.loadProduct()
        #expect(store.catalogMessage == .productLoadFailed)
        #expect(store.product == nil)
        await store.restore()
        #expect(store.access == .unlockedLifetime)
        #expect(store.message == .restored)
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await store.loadProduct()
        #expect(store.catalogMessage == nil)
        #expect(store.product != nil)
    }

    @Test @MainActor func restoreWithNoPurchaseAndSyncFailureHaveDifferentResults() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let store = store()
        await store.restore()
        #expect(store.message == .nothingToRestore)
        try await session.setSimulatedError(.generic(.unknown), forAPI: .appStoreSync)
        await store.restore()
        #expect(store.message == .restoreFailed)
        #expect(!store.isBusy)
    }
}
