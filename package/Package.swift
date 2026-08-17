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
        // SwiftPM derives a path dependency's identity from its last path
        // component, and both repos keep their manifest in `package/` — so
        // pointing at that directory makes the dependency collide with Forge
        // itself. `Warp` is a symlink to it, and goes away the moment this
        // becomes a URL dependency.
        .package(path: "../../Warp/Warp"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "Forge",
            dependencies: [
                .product(name: "Warp", package: "Warp"),
                .product(name: "WarpIR", package: "Warp"),
                .product(name: "WarpYAML", package: "Warp"),
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
