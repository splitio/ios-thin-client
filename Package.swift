// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "SplitThin",
    platforms: [.iOS(.v12)],
    products: [
        .library(name: "SplitThin", targets: ["SplitThin"]),
        .library(name: "Api", targets: ["Api"]),
    ],
    dependencies: [],
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
            dependencies: ["Api"],
            path: "SplitThin"
        ),
        .testTarget(
            name: "SplitThinTests",
            dependencies: [
                "SplitThin",
            ],
            path: "SplitThinTests"
        ),
        // #INJECT_TARGET
    ]
)
