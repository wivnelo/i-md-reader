import Foundation

public enum PremiumFeature: String, CaseIterable, Sendable {
    case codeFileViewing, imageZoom, mermaidMath, fullTextSearch, iPadMultiWindow
}

public struct PurchaseConfig: Equatable, Sendable {
    public static let lifetimeProductID = "com.readerprototype.3z4gd8c2jp.ipadmarkdownreader.lifetime"
    public static let trialProductID = "com.readerprototype.3z4gd8c2jp.ipadmarkdownreader.trial14d"
    public var isEnabled: Bool
    public var productID: String
    public var gatedFeatures: Set<PremiumFeature>

    public init(isEnabled: Bool, productID: String = lifetimeProductID, gatedFeatures: Set<PremiumFeature> = []) {
        self.isEnabled = isEnabled
        self.productID = productID
        self.gatedFeatures = gatedFeatures
    }

    public static var current: PurchaseConfig {
        var enabled = false
        #if os(iOS)
        #if DEBUG
        enabled = ProcessInfo.processInfo.arguments.contains("-IMDPurchaseEnabled")
        #else
        enabled = true
        #endif
        #endif
        return PurchaseConfig(isEnabled: enabled)
    }
}

public struct EntitlementRecord: Equatable, Sendable {
    public var transactionID: String?
    public var productID: String
    public var isVerified: Bool
    public var revocationDate: Date?
    public var originalPurchaseDate: Date
    public var isFamilyShared: Bool

    public init(productID: String, isVerified: Bool, revocationDate: Date? = nil,
                originalPurchaseDate: Date, isFamilyShared: Bool = false, transactionID: String? = nil) {
        self.transactionID = transactionID
        self.productID = productID
        self.isVerified = isVerified
        self.revocationDate = revocationDate
        self.originalPurchaseDate = originalPurchaseDate
        self.isFamilyShared = isFamilyShared
    }
}

public struct AppTransactionSnapshot: Equatable, Sendable {
    public enum Environment: Sendable { case production, sandbox, xcode, unknown }
    public var originalAppVersion: String
    public var environment: Environment
    public init(originalAppVersion: String, environment: Environment) {
        self.originalAppVersion = originalAppVersion
        self.environment = environment
    }
    public var isLegacyUser: Bool {
        guard environment == .production, !originalAppVersion.isEmpty,
              originalAppVersion.utf8.allSatisfy({ (48...57).contains($0) }),
              let build = Int(originalAppVersion) else { return false }
        return build <= 53
    }
}

public struct PurchaseAccessCache: Codable, Equatable, Sendable {
    public var trialStart: Date?
    public var hasLifetime: Bool
    /// Ignored leftover field kept so older Keychain payloads still decode. Never used to grant access.
    public var productionLegacyUser: Bool?
    public var maxObservedNow: Date
    public init(trialStart: Date? = nil, hasLifetime: Bool = false,
                productionLegacyUser: Bool? = nil, maxObservedNow: Date) {
        self.trialStart = trialStart
        self.hasLifetime = hasLifetime
        self.productionLegacyUser = productionLegacyUser
        self.maxObservedNow = maxObservedNow
    }
}

@MainActor public protocol PurchaseAccessStorage {
    func read() throws -> PurchaseAccessCache?
    func write(_ cache: PurchaseAccessCache) throws
}

public enum PurchaseAccess: Equatable, Sendable {
    case disabled, lockedNotStarted, trial(start: Date, end: Date, remainingDays: Int), lockedExpired, unlockedLifetime

    public var isUnlocked: Bool {
        switch self { case .disabled, .trial, .unlockedLifetime: true; default: false }
    }
    public var remainingDays: Int? {
        if case .trial(_, _, let days) = self { return days }
        return nil
    }

    /// nil records means unavailable. An empty authoritative snapshot clears transaction grants.
    /// Otherwise only products with verified records replace their cached grants.
    public static func resolve(config: PurchaseConfig, records: [EntitlementRecord]?,
                               appTransaction: AppTransactionSnapshot? = nil,
                               cache: PurchaseAccessCache? = nil, now: Date,
                               transactionsAreAuthoritative: Bool = false) -> (state: PurchaseAccess, cache: PurchaseAccessCache) {
        var updated = cache ?? PurchaseAccessCache(maxObservedNow: now)
        guard config.isEnabled else { return (.disabled, updated) }
        updated.maxObservedNow = max(now, updated.maxObservedNow)
        // 4.3：不另存老用户标记，也不用缓存中的历史值授予。
        updated.productionLegacyUser = nil
        if let records {
            let revokedIDs = Set(records.filter { $0.isVerified && $0.revocationDate != nil }.compactMap(\.transactionID))
            let verified = records.filter {
                $0.isVerified && ($0.revocationDate != nil || $0.transactionID.map { !revokedIDs.contains($0) } != false)
            }
            let lifetime = verified.filter { $0.productID == config.productID }
            let trial = verified.filter { $0.productID == PurchaseConfig.trialProductID }
            if transactionsAreAuthoritative || !lifetime.isEmpty {
                updated.hasLifetime = lifetime.contains { $0.revocationDate == nil }
            }
            if transactionsAreAuthoritative || !trial.isEmpty {
                updated.trialStart = trial.filter { $0.revocationDate == nil && !$0.isFamilyShared }
                    .map(\.originalPurchaseDate).min()
            }
            // An unverified result never grants or persists an entitlement.
        }
        // 4.3 / 11：只有当场拿到的生产 AppTransaction 才能授予老用户；取不到快照按新用户，不使用缓存标记。
        let legacy = appTransaction?.isLegacyUser == true
        if updated.hasLifetime || legacy { return (.unlockedLifetime, updated) }
        guard let start = updated.trialStart else { return (.lockedNotStarted, updated) }
        let end = start.addingTimeInterval(14 * 24 * 60 * 60)
        let remaining = end.timeIntervalSince(updated.maxObservedNow)
        guard remaining > 0 else { return (.lockedExpired, updated) }
        return (.trial(start: start, end: end, remainingDays: Int(ceil(remaining / 86400))), updated)
    }
}

public enum PremiumAccess: Sendable {
    public static func isAvailable(_ feature: PremiumFeature, config: PurchaseConfig, isUnlocked: Bool) -> Bool {
        guard config.isEnabled else { return true }
        guard isUnlocked else { return false }
        return !config.gatedFeatures.contains(feature) || isUnlocked
    }
    public static func showsPurchaseEntry(config: PurchaseConfig) -> Bool { config.isEnabled }

    /// Guideline 3.1.1 / KB 9.1: the localized lifetime price must be on screen before a trial can start.
    public static func canStartTrial(hasTrialProduct: Bool, hasLifetimeProduct: Bool, isBusy: Bool) -> Bool {
        hasTrialProduct && hasLifetimeProduct && !isBusy
    }
}

/// Defers Spotlight, App Intent, widget and deep-link opens until the iOS purchase lock lifts.
public struct PurchaseLaunchGate: Equatable, Sendable {
    public enum Intent: Equatable, Sendable {
        case openKey(String)
        case continueReading
        case openFile(URL)
    }

    public private(set) var pending: Intent?

    public init(pending: Intent? = nil) {
        self.pending = pending
    }

    /// When locked, stores the intent and returns nil so the caller shows the purchase page instead.
    public mutating func receive(_ intent: Intent, isLocked: Bool) -> Intent? {
        if isLocked {
            pending = intent
            return nil
        }
        pending = nil
        return intent
    }

    public mutating func takePendingIfUnlocked(_ isLocked: Bool) -> Intent? {
        guard !isLocked, let intent = pending else { return nil }
        pending = nil
        return intent
    }
}
