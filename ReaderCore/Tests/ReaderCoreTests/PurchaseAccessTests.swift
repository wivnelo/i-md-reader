import Foundation
import Testing
@testable import ReaderCore

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let day: TimeInterval = 86400
private let enabled = PurchaseConfig(isEnabled: true)
private func record(_ id: String = PurchaseConfig.trialProductID, verified: Bool = true,
                    revoked: Bool = false, family: Bool = false) -> EntitlementRecord {
    EntitlementRecord(productID: id, isVerified: verified, revocationDate: revoked ? start : nil,
                      originalPurchaseDate: start, isFamilyShared: family)
}
private func resolve(_ records: [EntitlementRecord]? = nil, cache: PurchaseAccessCache? = nil,
                     snapshot: AppTransactionSnapshot? = nil, now: Date = start,
                     authoritative: Bool = false) -> (state: PurchaseAccess, cache: PurchaseAccessCache) {
    PurchaseAccess.resolve(config: enabled, records: records, appTransaction: snapshot,
                           cache: cache, now: now, transactionsAreAuthoritative: authoritative)
}

@Test func purchasePlatformAndDisabled() {
    #if !os(iOS)
    #expect(!PurchaseConfig.current.isEnabled)
    #endif
    #expect(PurchaseConfig.current.gatedFeatures.isEmpty)
    let config = PurchaseConfig(isEnabled: false, gatedFeatures: Set(PremiumFeature.allCases))
    #expect(PurchaseAccess.resolve(config: config, records: [], now: start).state == .disabled)
    #expect(!PremiumAccess.showsPurchaseEntry(config: config))
    for feature in PremiumFeature.allCases {
        #expect(PremiumAccess.isAvailable(feature, config: config, isUnlocked: false))
        #expect(!PremiumAccess.isAvailable(feature, config: enabled, isUnlocked: false))
        #expect(PremiumAccess.isAvailable(feature, config: enabled, isUnlocked: true))
        #expect(PremiumAccess.isAvailable(feature, config: PurchaseConfig(isEnabled: true, gatedFeatures: [feature]), isUnlocked: true))
    }
}

@Test func purchaseFiveStatesAndExactBoundary() {
    #expect(resolve().state == .lockedNotStarted)
    #expect(resolve([record()]).state == .trial(start: start, end: start.addingTimeInterval(14 * day), remainingDays: 14))
    #expect(resolve([record()], now: start.addingTimeInterval(day + 1)).state.remainingDays == 13)
    #expect(resolve([record()], now: start.addingTimeInterval(14 * day - 1)).state.remainingDays == 1)
    #expect(resolve([record()], now: start.addingTimeInterval(14 * day)).state == .lockedExpired)
    #expect(resolve([record(PurchaseConfig.lifetimeProductID)]).state == .unlockedLifetime)
}

@Test func purchaseVerificationRefundAndFamilySharing() {
    let lifetime = PurchaseConfig.lifetimeProductID
    #expect(resolve([record(lifetime, family: true)]).state == .unlockedLifetime)
    #expect(resolve([record(lifetime, verified: false)]).state == .lockedNotStarted)
    #expect(!resolve([record(lifetime, verified: false)]).cache.hasLifetime)
    #expect(resolve([record(lifetime, revoked: true, family: true)]).state == .lockedNotStarted)
    #expect(resolve([record(lifetime, revoked: true), record()]).state.remainingDays == 14)
    #expect(resolve([record(lifetime, revoked: true), record()], now: start.addingTimeInterval(15 * day)).state == .lockedExpired)
    #expect(resolve([record(revoked: true)]).cache.trialStart == nil)
    #expect(resolve([record(verified: false)]).cache.trialStart == nil)
    #expect(resolve([record(family: true)]).state == .lockedNotStarted)
    #expect(resolve([record("other")]).state == .lockedNotStarted)
    var shared = record(lifetime, family: true)
    shared.transactionID = "shared"
    var revokedShared = shared
    revokedShared.revocationDate = start
    #expect(resolve([shared, revokedShared]).state == .lockedNotStarted)
    #expect(resolve([revokedShared, record(lifetime)]).state == .unlockedLifetime)
}

@Test func purchaseOfflineCacheAndAuthoritativeCorrection() {
    let paid = PurchaseAccessCache(hasLifetime: true, maxObservedNow: start)
    #expect(resolve(cache: paid).state == .unlockedLifetime)
    #expect(resolve([], cache: paid).state == .unlockedLifetime)
    #expect(resolve([], cache: paid, authoritative: true).state == .lockedNotStarted)
    #expect(resolve([record()], cache: paid, authoritative: true).state.remainingDays == 14)
    #expect(resolve([record(PurchaseConfig.lifetimeProductID, verified: false)], authoritative: true).state == .lockedNotStarted)
    #expect(resolve([record(PurchaseConfig.lifetimeProductID, revoked: true)], cache: paid).state == .lockedNotStarted)
    #expect(resolve().state == .lockedNotStarted)
    let legacyCache = PurchaseAccessCache(productionLegacyUser: true, maxObservedNow: start)
    #expect(resolve(cache: legacyCache).state == .lockedNotStarted)
    #expect(resolve(cache: PurchaseAccessCache(productionLegacyUser: false, maxObservedNow: start)).state == .lockedNotStarted)
    let trial = PurchaseAccessCache(trialStart: start, maxObservedNow: start)
    #expect(resolve(cache: trial, now: start.addingTimeInterval(2 * day)).state.remainingDays == 12)
    #expect(resolve(cache: trial, now: start.addingTimeInterval(14 * day)).state == .lockedExpired)
}

@Test func purchaseWatermarkStopsRollbackButNeverPaidOrLegacy() {
    let cache = resolve([record()], now: start.addingTimeInterval(14 * day)).cache
    #expect(resolve(cache: cache, now: start).state == .lockedExpired)
    #expect(resolve(cache: cache, now: start).cache.maxObservedNow == start.addingTimeInterval(14 * day))
    #expect(resolve([record(PurchaseConfig.lifetimeProductID)], cache: cache).state == .unlockedLifetime)
    #expect(resolve(cache: PurchaseAccessCache(productionLegacyUser: true, maxObservedNow: start.addingTimeInterval(100 * day))).state == .lockedNotStarted)
    let liveLegacy = AppTransactionSnapshot(originalAppVersion: "53", environment: .production)
    #expect(resolve(cache: PurchaseAccessCache(productionLegacyUser: true, maxObservedNow: start.addingTimeInterval(100 * day)), snapshot: liveLegacy).state == .unlockedLifetime)
}

@Test func purchaseLegacyNumericComparisonAndEnvironment() {
    for version in ["1", "9", "53", "00053"] {
        let snapshot = AppTransactionSnapshot(originalAppVersion: version, environment: .production)
        #expect(resolve(snapshot: snapshot).state == .unlockedLifetime)
        #expect(resolve(snapshot: snapshot).cache.productionLegacyUser == nil)
    }
    for version in ["54", "100", "1.0", "", "unknown", "-1", " 53", "53.0", "99999999999999999999999"] {
        let snapshot = AppTransactionSnapshot(originalAppVersion: version, environment: .production)
        #expect(resolve(snapshot: snapshot).state == .lockedNotStarted)
        #expect(resolve(snapshot: snapshot).cache.productionLegacyUser == nil)
    }
    for environment in [AppTransactionSnapshot.Environment.sandbox, .xcode, .unknown] {
        for version in ["1.0", "53"] {
            let result = resolve(snapshot: AppTransactionSnapshot(originalAppVersion: version, environment: environment))
            #expect(result.state == .lockedNotStarted)
            #expect(result.cache.productionLegacyUser == nil)
        }
    }
    let old = PurchaseAccessCache(productionLegacyUser: true, maxObservedNow: start)
    #expect(resolve(cache: old, snapshot: AppTransactionSnapshot(originalAppVersion: "100", environment: .production)).state == .lockedNotStarted)
    #expect(resolve(cache: old, snapshot: AppTransactionSnapshot(originalAppVersion: "1.0", environment: .sandbox)).state == .lockedNotStarted)
    #expect(resolve(cache: old).state == .lockedNotStarted)
}

@Test func purchaseLaunchGateDefersWhileLockedAndRestoresAfterUnlock() {
    var gate = PurchaseLaunchGate()
    #expect(gate.receive(.openKey("doc-1"), isLocked: true) == nil)
    #expect(gate.pending == .openKey("doc-1"))
    #expect(gate.takePendingIfUnlocked(true) == nil)
    #expect(gate.takePendingIfUnlocked(false) == .openKey("doc-1"))
    #expect(gate.pending == nil)
    #expect(gate.receive(.continueReading, isLocked: false) == .continueReading)
    #expect(gate.pending == nil)
    let file = URL(fileURLWithPath: "/tmp/demo.md")
    #expect(gate.receive(.openFile(file), isLocked: true) == nil)
    #expect(gate.receive(.openKey("doc-2"), isLocked: true) == nil)
    #expect(gate.takePendingIfUnlocked(false) == .openKey("doc-2"))
}

@Test func purchaseReinstallUsesOriginalTransactionWithoutLocalState() {
    let first = resolve([record()], now: start.addingTimeInterval(2 * day))
    let reinstalled = resolve([record()], cache: nil, now: start.addingTimeInterval(3 * day))
    #expect(first.cache.trialStart == reinstalled.cache.trialStart)
    #expect(reinstalled.state.remainingDays == 11)
    #expect(reinstalled.cache.trialStart == start)
}

@MainActor private final class MemoryPurchaseStorage: PurchaseAccessStorage {
    var value: PurchaseAccessCache?
    func read() throws -> PurchaseAccessCache? { value }
    func write(_ cache: PurchaseAccessCache) throws { value = cache }
}

@Test @MainActor func purchaseStorageRoundTrip() throws {
    let storage = MemoryPurchaseStorage()
    #expect(try storage.read() == nil)
    try storage.write(resolve([record()]).cache)
    let stored = try storage.read()
    let value = try #require(stored)
    #expect(resolve(cache: value).state.remainingDays == 14)
    let encoded = try JSONEncoder().encode(value)
    #expect(try JSONDecoder().decode(PurchaseAccessCache.self, from: encoded) == value)
}
