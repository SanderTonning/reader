// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ReaderKit",
    defaultLocalization: "nb",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReaderKit", targets: ["ReaderKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "ReaderKit",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            resources: [
                .copy("Resources/Readability.js"),
                .copy("Resources/Readability-LICENSE.md"),
            ]
        ),
        .testTarget(name: "ReaderKitTests", dependencies: ["ReaderKit"]),
    ]
)
