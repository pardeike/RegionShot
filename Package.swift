// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RegionShot",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "regionshot",
            targets: ["RegionShot"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "RegionShot"
        ),
        .testTarget(
            name: "RegionShotTests",
            dependencies: ["RegionShot"]
        ),
    ]
)
