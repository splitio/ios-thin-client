// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "SplitThin",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "SplitThin", targets: ["SplitThin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/splitio/ios-client.git", from: "3.8.0")
    ],
    targets: [
        .target(
            name: "SplitThin",
            dependencies: [
                .product(name: "SplitCommons", package: "ios-client"),
            ],
            path: "SplitThin"
        ),
        .testTarget(
            name: "SplitThinTests",
            dependencies: [
                "SplitThin",
                .product(name: "SplitCommons", package: "ios-client"),
            ],
            path: "SplitThinTests"
        ),
        // #INJECT_TARGET
    ]
)
