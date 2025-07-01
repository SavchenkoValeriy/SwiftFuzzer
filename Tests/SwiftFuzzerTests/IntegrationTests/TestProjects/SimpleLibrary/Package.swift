// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimpleLibrary",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SimpleLibrary", targets: ["SimpleLibrary"])
    ],
    dependencies: [
        .package(path: "../../../../..")  // Reference to SwiftFuzzer for FuzzTest
    ],
    targets: [
        .target(
            name: "SimpleLibrary",
            dependencies: [
                .product(name: "FuzzTest", package: "SwiftFuzzer")
            ]
        )
    ]
)
