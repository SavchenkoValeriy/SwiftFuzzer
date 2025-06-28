// Sources/SwiftFuzzer/SwiftFuzzer.swift
import ArgumentParser
import Foundation
import Basics
import PackageModel
import Workspace
import PackageGraph
import SPMBuildCore
import Build
import TSCBasic
import TSCLibc

@main
struct SwiftFuzzer: AsyncParsableCommand {
    @Argument(help: "Path to the Swift package to build")
    var packagePath: String
    
    @Option(name: .shortAndLong, help: "Build configuration (debug/release)")
    var configuration: String = "debug"
    
    func run() async throws {
        print("Building package at: \(packagePath)")
        
        let packagePath = try Basics.AbsolutePath(validating: self.packagePath)
        let buildConfig = configuration == "release" ? BuildConfiguration.release : BuildConfiguration.debug
        
        // Create observability system that prints diagnostics
        let observability = ObservabilitySystem { scope, diagnostic in
            let diagnosticLevel = diagnostic.severity == .error ? "ERROR" : 
                                 diagnostic.severity == .warning ? "WARNING" : "INFO"
            print("[\(diagnosticLevel)] \(diagnostic.description)")
            if let metadata = diagnostic.metadata {
                print("  Metadata: \(String(describing: metadata))")
            }
        }
        let fileSystem = Basics.localFileSystem
        let buildPath = packagePath.appending(component: ".build")
        
        // Ensure build directories exist
        try fileSystem.createDirectory(buildPath, recursive: true)
        try fileSystem.createDirectory(buildPath.appending(component: buildConfig.dirname), recursive: true)
        try fileSystem.createDirectory(buildPath.appending(component: "host"), recursive: true)
        try fileSystem.createDirectory(buildPath.appending(component: "scratch"), recursive: true)
        try fileSystem.createDirectory(buildPath.appending(component: "plugin-cache"), recursive: true)
        
        // Create workspace
        let workspace = try Workspace(
            fileSystem: fileSystem,
            forRootPackage: packagePath,
            authorizationProvider: nil,
            registryAuthorizationProvider: nil,
            configuration: .default,
            cancellator: nil,
            customManifestLoader: nil,
            delegate: nil
        )
        
        // Load package graph
        let graph = try await workspace.loadPackageGraph(
            rootInput: PackageGraphRootInput(packages: [packagePath]),
            observabilityScope: observability.topScope
        )
        
        print("Package loaded with \(graph.allModules.count) modules")
        for module in graph.allModules {
            print("Module: \(module.name) (type: \(module.type))")
        }
        
        // Create build parameters
        let toolchain = try UserToolchain(swiftSDK: .hostSwiftSDK())
        let triple = toolchain.targetTriple
        
        // Target build parameters (for the final products)
        let targetBuildParameters = try BuildParameters(
            destination: .target,
            dataPath: buildPath.appending(component: buildConfig.dirname),
            configuration: buildConfig,
            toolchain: toolchain,
            triple: triple,
            flags: BuildFlags(),
            buildSystemKind: .native,
            workers: UInt32(ProcessInfo.processInfo.activeProcessorCount),
            sanitizers: EnabledSanitizers()
        )
        
        // Host build parameters (for build tools like macros)
        let hostBuildParameters = try BuildParameters(
            destination: .host,
            dataPath: buildPath.appending(component: "host"),
            configuration: buildConfig,
            toolchain: toolchain,
            triple: triple,
            flags: BuildFlags(),
            buildSystemKind: .native,
            workers: UInt32(ProcessInfo.processInfo.activeProcessorCount),
            sanitizers: EnabledSanitizers()
        )
        
        // Create BuildOperation
        let cacheBuildManifest = false
        let scratchDirectory = buildPath.appending(component: "scratch")
        let outputStream = try! ThreadSafeOutputByteStream(LocalFileOutputByteStream(
            filePointer: TSCLibc.stderr,
            closeOnDeinit: false))
        
        print("Creating build operation...")
        
        // Create plugin configuration for packages with plugins
        let pluginConfiguration = PluginConfiguration(
            scriptRunner: DefaultPluginScriptRunner(
                fileSystem: fileSystem,
                cacheDir: buildPath.appending(component: "plugin-cache"),
                toolchain: toolchain
            ),
            workDirectory: buildPath.appending(component: "plugin-cache"),
            disableSandbox: false
        )
        
        let build = BuildOperation(
            productsBuildParameters: targetBuildParameters,
            toolsBuildParameters: hostBuildParameters,
            cacheBuildManifest: cacheBuildManifest,
            packageGraphLoader: { graph },
            pluginConfiguration: pluginConfiguration,
            scratchDirectory: scratchDirectory,
            additionalFileRules: [],
            pkgConfigDirectories: [],
            outputStream: outputStream,
            logLevel: .info,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        )
        
        print("Starting build...")
        
        do {
            try await build.build(subset: BuildSubset.allExcludingTests)
            print("\nBuild completed successfully!")
        } catch {
            print("Build failed with error: \(error)")
            // Print more detailed error information
            print("Error details: \(String(describing: error))")
            if let nsError = error as NSError? {
                print("Error domain: \(nsError.domain)")
                print("Error code: \(nsError.code)")
                print("Error userInfo: \(nsError.userInfo)")
            }
            throw error
        }
    }
}