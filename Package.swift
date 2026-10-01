// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZECBuyingPrice",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AcquisitionCore", targets: ["AcquisitionCore"]),
               .executable(name: "ZECBuyingPrice", targets: ["ZECBuyingPrice"])],
    dependencies: [.package(url: "https://github.com/zcash/zcash-swift-wallet-sdk.git", exact: "3.0.0"),
                   .package(url: "https://github.com/stephencelis/SQLite.swift.git", exact: "0.16.0")],
    targets: [
        .target(name: "AcquisitionCore"),
        .executableTarget(name: "ZECBuyingPrice", dependencies: ["AcquisitionCore",
            .product(name: "ZcashLightClientKit", package: "zcash-swift-wallet-sdk"),
            .product(name: "SQLite", package: "SQLite.swift")],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AcquisitionCoreTests", dependencies: ["AcquisitionCore"]),
        .testTarget(name: "AppIntegrationTests", dependencies: ["ZECBuyingPrice",
            .product(name: "ZcashLightClientKit", package: "zcash-swift-wallet-sdk")],
            swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
