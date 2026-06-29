// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "SplitThin",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(name: "SplitThin", targets: ["SplitThin"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/splitio/ios-client.git",
            revision: "4c6b1034f7044a3bf272fea4f607a6f51182d1b8"
        )
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
