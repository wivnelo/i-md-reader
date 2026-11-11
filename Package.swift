// swift-tools-version: 6.0
import PackageDescription

// Run the app's actual state store on macOS without a simulator or UI session.
let package = Package(
    name: "ReaderStoreChecks",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "ReaderCore")],
    targets: [
        .target(name: "ReaderStoreChecks", dependencies: ["ReaderCore"], path: "ReaderApp",
                exclude: ["ReaderApp.swift", "ReaderScreen.swift", "ReaderWebView.swift", "Resources", "Info.plist",
                          "PurchaseStore.swift", "PurchaseViews.swift", "PurchaseSheet.swift", "ReaderApp.entitlements", "ReaderShortcuts.swift", "StoreKit"],
                sources: ["ReaderStore.swift", "ReaderPalette.swift", "ReaderLanguage.swift", "ReaderSync.swift"]),
        .testTarget(name: "ReaderStoreChecksTests", dependencies: ["ReaderStoreChecks"], path: "Tests/ReaderStoreChecksTests"),
        // Exercise the real StoreKit controller with injected responses, without
        // launching the app or accessing an Apple account or production Keychain.
        .target(name: "PurchaseStoreChecks", dependencies: ["ReaderCore"], path: "ReaderApp",
                exclude: ["ReaderApp.swift", "ReaderScreen.swift", "ReaderWebView.swift", "Resources", "Info.plist",
                          "PurchaseViews.swift", "PurchaseSheet.swift", "ReaderApp.entitlements", "ReaderShortcuts.swift", "StoreKit",
                          "ReaderStore.swift", "ReaderPalette.swift", "ReaderLanguage.swift", "ReaderSync.swift"],
                sources: ["PurchaseStore.swift"], swiftSettings: [.define("IMD_PURCHASE_TESTS")]),
        .testTarget(name: "PurchaseStoreChecksTests", dependencies: ["PurchaseStoreChecks"], path: "Tests/PurchaseStoreChecksTests")
    ]
)
