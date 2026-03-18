// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "SplitThin",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(name: "SplitThin", targets: ["SplitThin"]),
        .library(name: "Api", targets: ["Api"]),
    ],
    dependencies: [
        .package(path: "ios-client"),
    ],
    targets: [
        .target(
            name: "Api",
            dependencies: [],
            path: "Sources/Api",
            exclude: ["Tests", "README.md"]
        ),
        .testTarget(
            name: "ApiTests",
            dependencies: ["Api"],
            path: "Sources/Api/Tests"
        ),
        .target(
            name: "SplitThin",
            dependencies: [
                "Api",
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
