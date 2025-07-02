// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftFuzzer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "swift-fuzz", targets: ["SwiftFuzzer"]),
        .library(name: "FuzzTest", targets: ["FuzzTest"]),
        .library(name: "SwiftFuzzerLib", targets: ["SwiftFuzzerLib"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-package-manager.git", revision: "swift-6.1.1-RELEASE"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "509.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-macro-testing.git", from: "0.2.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "SwiftFuzzerLib",
            dependencies: [
                .product(name: "SwiftPM-auto", package: "swift-package-manager"),
                "FuzzTest"
            ]
        ),
        .executableTarget(
            name: "SwiftFuzzer",
            dependencies: [
                "SwiftFuzzerLib",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "FuzzTest",
            dependencies: [
                "FuzzTestMacros"
            ]
        ),
        .macro(
            name: "FuzzTestMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "FuzzTestTests",
            dependencies: ["FuzzTest"]
        ),
        .testTarget(
            name: "FuzzTestMacrosTests",
            dependencies: [
                "FuzzTestMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                .product(name: "MacroTesting", package: "swift-macro-testing")
            ]
        ),
        .testTarget(
            name: "SwiftFuzzerTests",
            dependencies: ["SwiftFuzzerLib"],
            exclude: ["IntegrationTests/TestProjects"]
        )
    ]
)
