// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReaderCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ReaderCore", targets: ["ReaderCore"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git",
                 revision: "392b73b858efe3dacec0e8a91c6e7fd19af0bb98")
    ],
    targets: [
        .target(name: "ReaderCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .testTarget(name: "ReaderCoreTests", dependencies: ["ReaderCore"])
    ]
)
