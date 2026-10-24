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
        .package(path: "../../warp-runtime-swift"),
        .package(path: "../../warp-frontend-yaml"),
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
            ],
            resources: [
                .copy("Service/Workflow/Warp/Forge.yaml")
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
