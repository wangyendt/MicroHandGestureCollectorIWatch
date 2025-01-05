// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MicroHandGestureCollectorIWatch",
    platforms: [
        .iOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(
            name: "MicroHandGestureCollectorIWatch",
            targets: ["MicroHandGestureCollectorIWatch"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "MicroHandGestureCollectorIWatch",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ]),
        .testTarget(
            name: "MicroHandGestureCollectorIWatchTests",
            dependencies: ["MicroHandGestureCollectorIWatch"]),
    ]
) 