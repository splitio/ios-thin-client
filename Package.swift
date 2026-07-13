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
            revision: "e256f22a7c98af2643ffd03cc60a2b24cf90524f"
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
