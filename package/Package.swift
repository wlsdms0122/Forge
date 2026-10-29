// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Forge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "Forge", targets: ["Forge"]),
        .executable(name: "ForgeCLI", targets: ["ForgeCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/wlsdms0122/warp-runtime-swift.git", exact: "0.1.0"),
        .package(url: "https://github.com/wlsdms0122/warp-frontend-yaml.git", exact: "0.1.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "Forge",
            dependencies: [
                .product(name: "Warp", package: "warp-runtime-swift"),
                .product(name: "WarpSyntax", package: "warp-runtime-swift"),
                .product(name: "WarpStandard", package: "warp-runtime-swift"),
                .product(name: "WarpYAML", package: "warp-frontend-yaml"),
                .product(name: "TOMLKit", package: "TOMLKit"),
                .product(name: "Yams", package: "Yams")
            ]
        ),
        .executableTarget(
            name: "ForgeCLI",
            dependencies: [
                "Forge",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "ForgeTests",
            dependencies: [
                "Forge",
                "ForgeCLI"
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
