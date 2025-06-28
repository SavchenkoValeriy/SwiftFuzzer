// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MyBuilder",
    platforms: [.macOS(.v13)],
    products: [
      .executable(name: "swift-fuzz", targets: ["SwiftFuzzer"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-package-manager.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "SwiftFuzzer",
            dependencies: [
                .product(name: "SwiftPM-auto", package: "swift-package-manager")
            ]
        )
    ]
)
