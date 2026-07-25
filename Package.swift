// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SafeMediaKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .macCatalyst(.v17)
    ],
    products: [
        .library(name: "SafeMediaKit", targets: ["SafeMediaKit"]),
        .library(name: "SafeMediaKitTesting", targets: ["SafeMediaKitTesting"])
    ],
    targets: [
        .target(name: "SafeMediaKit"),
        .target(
            name: "SafeMediaKitTesting",
            dependencies: ["SafeMediaKit"]
        ),
        .testTarget(
            name: "SafeMediaKitTests",
            dependencies: ["SafeMediaKit", "SafeMediaKitTesting"]
        ),
        .testTarget(
            name: "SafeMediaKitTestingTests",
            dependencies: ["SafeMediaKit", "SafeMediaKitTesting"]
        )
    ]
)
