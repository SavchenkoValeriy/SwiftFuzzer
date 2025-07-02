// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExecutableApp",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ExecutableApp", targets: ["ExecutableApp"])
    ],
    dependencies: [
        .package(path: "../../../../..")  // Reference to SwiftFuzzer for FuzzTest
    ],
    targets: [
        .executableTarget(
            name: "ExecutableApp",
            dependencies: [
                .product(name: "FuzzTest", package: "SwiftFuzzer")
            ]
        )
    ]
)