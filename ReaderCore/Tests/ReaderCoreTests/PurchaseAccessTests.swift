import Foundation
import Testing
@testable import ReaderCore

private func purchaseConfig(enabled: Bool = true, gated: Set<PremiumFeature> = []) -> PurchaseConfig {
    PurchaseConfig(isEnabled: enabled, productID: PurchaseConfig.placeholderProductID, gatedFeatures: gated)
}

private func entitlement(verified: Bool = true, revoked: Date? = nil, id: String = PurchaseConfig.placeholderProductID) -> EntitlementRecord {
    EntitlementRecord(productID: id, isVerified: verified, revocationDate: revoked)
}

@Test func purchaseDefaultIsDisabledAndEmpty() {
    #expect(!PurchaseConfig.current.isEnabled)
    #expect(PurchaseConfig.current.gatedFeatures.isEmpty)
    #expect(PurchaseConfig.current.productID == "com.placeholder.imdreader.pro")
}

@Test func purchaseDisabledNeverLocksOrUnlocks() {
    let config = purchaseConfig(enabled: false, gated: Set(PremiumFeature.allCases))
    #expect(!PremiumAccess.isUnlocked([entitlement()], config: config))
    for feature in PremiumFeature.allCases {
        #expect(PremiumAccess.isAvailable(feature, config: config, isUnlocked: false))
    }
}

@Test func purchaseEnabledWithNoGatesKeepsAllFeaturesAvailable() {
    for feature in PremiumFeature.allCases {
        #expect(PremiumAccess.isAvailable(feature, config: purchaseConfig(), isUnlocked: false))
    }
}

@Test func purchaseGatesOnlyConfiguredFeatures() {
    let config = purchaseConfig(gated: [.imageZoom])
    #expect(!PremiumAccess.isAvailable(.imageZoom, config: config, isUnlocked: false))
    #expect(PremiumAccess.isAvailable(.imageZoom, config: config, isUnlocked: true))
    for feature in PremiumFeature.allCases where feature != .imageZoom {
        #expect(PremiumAccess.isAvailable(feature, config: config, isUnlocked: false))
        #expect(PremiumAccess.isAvailable(feature, config: config, isUnlocked: true))
    }
}

@Test func purchaseRequiresMatchingVerifiedUnrevokedEntitlement() {
    let config = purchaseConfig()
    #expect(PremiumAccess.isUnlocked([entitlement()], config: config))
    #expect(!PremiumAccess.isUnlocked([], config: config))
    #expect(!PremiumAccess.isUnlocked([entitlement(verified: false)], config: config))
    #expect(!PremiumAccess.isUnlocked([entitlement(revoked: Date())], config: config))
    #expect(!PremiumAccess.isUnlocked([entitlement(id: "other")], config: config))
    #expect(PremiumAccess.isUnlocked([entitlement(verified: false), entitlement()], config: config))
}

@Test func purchaseRevocationLocksAgain() {
    let config = purchaseConfig(gated: [.imageZoom])
    let before = PremiumAccess.isUnlocked([entitlement()], config: config)
    let after = PremiumAccess.isUnlocked([entitlement(revoked: Date())], config: config)
    #expect(PremiumAccess.isAvailable(.imageZoom, config: config, isUnlocked: before))
    #expect(!PremiumAccess.isAvailable(.imageZoom, config: config, isUnlocked: after))
}

@Test func purchaseEntryFollowsSwitch() {
    #expect(!PremiumAccess.showsPurchaseEntry(config: purchaseConfig(enabled: false)))
    #expect(PremiumAccess.showsPurchaseEntry(config: purchaseConfig()))
}
