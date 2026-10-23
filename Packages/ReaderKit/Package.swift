// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ReaderKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReaderKit", targets: ["ReaderKit"]),
    ],
    targets: [
        .target(name: "ReaderKit"),
        .testTarget(name: "ReaderKitTests", dependencies: ["ReaderKit"]),
    ]
)
