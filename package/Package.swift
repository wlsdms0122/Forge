// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Forge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "Spec", targets: ["Spec"]),
        .library(name: "Forge", targets: ["Forge"]),
        .executable(name: "ForgeCLI", targets: ["ForgeCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "Spec",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ]
        ),
        .testTarget(
            name: "SpecTests",
            dependencies: [
                "Spec"
            ]
        ),
        .target(
            name: "Forge",
            dependencies: [
                "Spec",
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
