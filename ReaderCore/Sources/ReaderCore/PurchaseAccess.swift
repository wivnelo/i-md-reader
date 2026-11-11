import Foundation

/// 仅为 KB 中的候选付费功能；Boss 未定，不代表已确认的解锁内容。
public enum PremiumFeature: String, CaseIterable, Sendable {
    case codeFileViewing, imageZoom, mermaidMath, fullTextSearch, iPadMultiWindow
}

public struct PurchaseConfig: Equatable, Sendable {
    public var isEnabled: Bool
    public var productID: String
    public var gatedFeatures: Set<PremiumFeature>

    public init(isEnabled: Bool, productID: String, gatedFeatures: Set<PremiumFeature>) {
        self.isEnabled = isEnabled
        self.productID = productID
        self.gatedFeatures = gatedFeatures
    }

    // TODO: Boss 未定，最终值见 KB PR#20；商品 ID 创建后不可改、不可重用。
    public static let placeholderProductID = "com.placeholder.imdreader.pro"

    /// 唯一总开关位置。正式版默认关闭；DEBUG 才允许启动参数覆盖。
    /// gatedFeatures 保持空集合，不锁任何现有功能。
    public static var current: PurchaseConfig {
        var enabled = false
        #if DEBUG
        enabled = ProcessInfo.processInfo.arguments.contains("-IMDPurchaseEnabled")
        #endif
        return PurchaseConfig(isEnabled: enabled, productID: placeholderProductID, gatedFeatures: [])
    }
}

public struct EntitlementRecord: Equatable, Sendable {
    public var productID: String
    public var isVerified: Bool
    public var revocationDate: Date?

    public init(productID: String, isVerified: Bool, revocationDate: Date?) {
        self.productID = productID
        self.isVerified = isVerified
        self.revocationDate = revocationDate
    }
}

public enum PremiumAccess: Sendable {
    public static func isUnlocked(_ records: [EntitlementRecord], config: PurchaseConfig) -> Bool {
        config.isEnabled && records.contains {
            $0.productID == config.productID && $0.isVerified && $0.revocationDate == nil
        }
    }

    public static func isAvailable(_ feature: PremiumFeature, config: PurchaseConfig, isUnlocked: Bool) -> Bool {
        !config.isEnabled || !config.gatedFeatures.contains(feature) || isUnlocked
    }

    public static func showsPurchaseEntry(config: PurchaseConfig) -> Bool {
        config.isEnabled
    }
}
