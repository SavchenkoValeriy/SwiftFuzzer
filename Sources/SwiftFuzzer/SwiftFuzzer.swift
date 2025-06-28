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
    
    @Option(name: .long, help: "Specific target to build (builds all targets if not specified)")
    var target: String?
    
    func run() async throws {
        print("Building package at: \(packagePath)")
        
        let packagePath = try Basics.AbsolutePath(validating: self.packagePath)
        let buildConfig = configuration == "release" ? BuildConfiguration.release : BuildConfiguration.debug
        
        print("Configuration: \(buildConfig.dirname)")
        print("Package path: \(packagePath)")
        
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
        
        // Create completely separate .fuzz directory with its own .build structure
        // This prevents any interference with regular .build directory and symlinks
        let fuzzRootPath = packagePath.appending(component: ".fuzz")
        let fuzzBuildPath = fuzzRootPath.appending(component: ".build")
        
        // Set up fuzz build directories - SwiftPM will append configuration dirname automatically
        let targetBuildPath = fuzzBuildPath
        let hostBuildPath = fuzzBuildPath.appending(component: "host")
        let scratchPath = fuzzBuildPath.appending(component: "scratch")
        let pluginCachePath = fuzzBuildPath.appending(component: "plugin-cache")
        
        // Create the fuzz build directory structure
        if !fileSystem.exists(fuzzBuildPath) {
            try fileSystem.createDirectory(fuzzBuildPath, recursive: true)
        }
        
        // Let SwiftPM create the target directories - just ensure plugin and scratch dirs exist
        if !fileSystem.exists(scratchPath) {
            try fileSystem.createDirectory(scratchPath, recursive: true)
        }
        
        if !fileSystem.exists(pluginCachePath) {
            try fileSystem.createDirectory(pluginCachePath, recursive: true)
        }
        
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
        
        // Determine build subset based on target parameter
        let buildSubset: BuildSubset
        if let targetName = target {
            // Validate that the target exists
            let targetExists = graph.allModules.contains { $0.name == targetName }
            guard targetExists else {
                print("\nError: Target '\(targetName)' not found in package.")
                print("Available targets:")
                for module in graph.allModules {
                    print("  - \(module.name) (type: \(module.type))")
                }
                throw ExitCode.failure
            }
            
            buildSubset = .target(targetName)
            print("\nBuilding target: \(targetName)")
        } else {
            buildSubset = .allExcludingTests
            print("\nBuilding all targets (excluding tests)")
        }
        
        // Create build parameters
        let toolchain = try UserToolchain(swiftSDK: .hostSwiftSDK())
        let triple = toolchain.targetTriple
        
        // Target build parameters (for the final products)
        let targetBuildParameters = try BuildParameters(
            destination: .target,
            dataPath: targetBuildPath,
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
            dataPath: hostBuildPath,
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
        let outputStream = try! ThreadSafeOutputByteStream(LocalFileOutputByteStream(
            filePointer: TSCLibc.stderr,
            closeOnDeinit: false))
        
        print("Creating build operation...")
        
        // Create plugin configuration for packages with plugins
        let pluginConfiguration = PluginConfiguration(
            scriptRunner: DefaultPluginScriptRunner(
                fileSystem: fileSystem,
                cacheDir: pluginCachePath,
                toolchain: toolchain
            ),
            workDirectory: pluginCachePath,
            disableSandbox: false
        )
        
        let build = BuildOperation(
            productsBuildParameters: targetBuildParameters,
            toolsBuildParameters: hostBuildParameters,
            cacheBuildManifest: cacheBuildManifest,
            packageGraphLoader: { graph },
            pluginConfiguration: pluginConfiguration,
            scratchDirectory: scratchPath,
            additionalFileRules: [],
            pkgConfigDirectories: [],
            outputStream: outputStream,
            logLevel: .info,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        )
        
        print("Starting build...")
        
        do {
            try await build.build(subset: buildSubset)
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