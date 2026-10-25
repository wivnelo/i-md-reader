// swift-tools-version: 6.0
import PackageDescription

// Run the app's actual state store on macOS without a simulator or UI session.
let package = Package(
    name: "ReaderStoreChecks",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "ReaderCore")],
    targets: [
        .target(name: "ReaderStoreChecks", dependencies: ["ReaderCore"], path: "ReaderApp",
                exclude: ["ReaderApp.swift", "ReaderScreen.swift", "ReaderWebView.swift", "Resources"],
                sources: ["ReaderStore.swift", "ReaderPalette.swift", "ReaderLanguage.swift"]),
        .testTarget(name: "ReaderStoreChecksTests", dependencies: ["ReaderStoreChecks"], path: "Tests/ReaderStoreChecksTests")
    ]
)
