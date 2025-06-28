// Sources/SwiftFuzzer/SwiftFuzzer.swift
import ArgumentParser
import Foundation
import Basics
import PackageModel
import Workspace
import PackageGraph
@_spi(SwiftBuild) import Build
import SPMBuildCore
import TSCBasic

@main
struct SwiftFuzzer: AsyncParsableCommand {
    @Argument(help: "Path to the Swift package to build")
    var packagePath: String
    
    @Option(name: .shortAndLong, help: "Build configuration (debug/release)")
    var configuration: String = "debug"
    
    func run() async throws {
        let observability = ObservabilitySystem { _, _ in }
        let fileSystem = Basics.localFileSystem
        let packagePath = try Basics.AbsolutePath(validating: self.packagePath)
        
        print("Loading package at: \(packagePath)")
        
        // Create workspace
        let workspace = try Workspace(
            forRootPackage: packagePath
        )
        
        // Load package graph
        let graph = try await workspace.loadPackageGraph(
            rootInput: PackageGraphRootInput(packages: [packagePath]),
            observabilityScope: observability.topScope
        )
        
        print("Package loaded with \(graph.allModules.count) modules")
        
        // Build parameters
        let buildPath = packagePath.appending(component: ".build")
        let toolchain = try UserToolchain(swiftSDK: .hostSwiftSDK())
        
        let buildParameters = try BuildParameters(
            destination: .target,
            dataPath: buildPath,
            configuration: configuration == "release" ? .release : .debug,
            toolchain: toolchain,
            triple: toolchain.targetTriple,
            flags: BuildFlags(),
            buildSystemKind: .native
        )
        
        // Create build operation
        let outputStream = BufferedOutputByteStream()
        let stream = ThreadSafeOutputByteStream(outputStream)
        
        let buildOp = BuildOperation(
            productsBuildParameters: buildParameters,
            toolsBuildParameters: buildParameters,
            cacheBuildManifest: false,
            packageGraphLoader: { graph },
            pluginConfiguration: nil,
            scratchDirectory: buildPath.appending(component: "plugins"),
            additionalFileRules: [],
            pkgConfigDirectories: [],
            outputStream: stream,
            logLevel: .info,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        )
        
        // Build!
        try await buildOp.build(subset: BuildSubset.allIncludingTests)
        
        print("Build completed successfully!")
        
        // Print build output
        print("\nBuild output:")
        print(outputStream.bytes.validDescription ?? "")
    }
}
