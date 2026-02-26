// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "SplitThin",
    platforms: [.iOS(.v12)],
    products: [
        .library(name: "SplitThin", targets: ["SplitThin"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SplitThin",
            dependencies: [],
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
