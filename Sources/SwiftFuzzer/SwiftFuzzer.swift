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

struct StringError: Error {
    let message: String
    init(_ message: String) {
        self.message = message
    }
}

// Simple topological sort for modules based on dependencies
func topologicalSort(_ modules: [ResolvedModule]) throws -> [ResolvedModule] {
    var sorted: [ResolvedModule] = []
    var visited = Set<String>()
    var visiting = Set<String>()
    
    func visit(_ module: ResolvedModule) throws {
        if visiting.contains(module.name) {
            throw StringError("Circular dependency detected involving module: \(module.name)")
        }
        if visited.contains(module.name) {
            return
        }
        
        visiting.insert(module.name)
        
        // Visit dependencies first (only those within the same set of modules)
        for dependency in module.dependencies {
            switch dependency {
            case .module(let depModule, _):
                if modules.contains(where: { $0.name == depModule.name }) {
                    try visit(depModule)
                }
            case .product(_, _):
                // Skip products as they are external dependencies
                break
            }
        }
        
        visiting.remove(module.name)
        visited.insert(module.name)
        sorted.append(module)
    }
    
    for module in modules {
        try visit(module)
    }
    
    return sorted
}

@main
struct SwiftFuzzer: AsyncParsableCommand {
    @Argument(help: "Path to the Swift package to build")
    var packagePath: String
    
    @Option(name: .shortAndLong, help: "Build configuration (debug/release)")
    var configuration: String = "debug"
    
    @Option(name: .long, help: "Target to build with fuzz instrumentation (required)")
    var target: String
    
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
        
        // Validate that the target exists
        let targetExists = graph.allModules.contains { $0.name == target }
        guard targetExists else {
            print("\nError: Target '\(target)' not found in package.")
            print("Available targets:")
            for module in graph.allModules {
                print("  - \(module.name) (type: \(module.type))")
            }
            throw ExitCode.failure
        }
        
        print("\nBuilding target: \(target) with fuzz instrumentation")
        
        // Check if dependencies are already built
        let regularBuildPath = packagePath.appending(component: ".build")
        let regularTargetBuildDir = regularBuildPath.appending(components: "arm64-apple-macosx", buildConfig.dirname)
        
        let targetModule = graph.allModules.first { $0.name == target }!
        let dependenciesExist = targetModule.dependencies.allSatisfy { dep in
            let depName = switch dep {
            case .module(let module, _): module.name
            case .product(let product, _): product.name
            }
            let modulePath = regularTargetBuildDir.appending(component: "Modules").appending(component: "\(depName).swiftmodule")
            return fileSystem.exists(modulePath)
        }
        
        if !dependenciesExist {
            // Step 1: Build dependencies in regular .build directory
            print("\n🏗️  Step 1: Building dependencies in regular .build directory...")
            try await buildDependencies(
                packagePath: packagePath,
                target: target,
                buildConfig: buildConfig,
                graph: graph,
                observability: observability,
                fileSystem: fileSystem
            )
        } else {
            print("\n🏗️  Step 1: Dependencies already built, skipping...")
        }
        
        // Step 2: Link pre-built dependencies to fuzz directory
        print("\n🔗 Step 2: Linking dependencies to fuzz build...")
        try await linkDependenciesToFuzzBuild(
            packagePath: packagePath,
            target: target,
            buildConfig: buildConfig,
            graph: graph,
            fileSystem: fileSystem,
            fuzzBuildPath: fuzzBuildPath
        )
        
        // Step 3: Build only the specific target in .fuzz directory  
        print("\n🎯 Step 3: Building target '\(target)' with isolated build...")
        try await buildTargetWithFuzzInstrumentation(
            packagePath: packagePath,
            target: target,
            buildConfig: buildConfig,
            graph: graph,
            observability: observability,
            fileSystem: fileSystem,
            fuzzRootPath: fuzzRootPath,
            fuzzBuildPath: fuzzBuildPath,
            hostBuildPath: hostBuildPath,
            scratchPath: scratchPath,
            pluginCachePath: pluginCachePath
        )
        
        print("\n✅ Hybrid build completed successfully!")
    }
    
    // Build dependencies in regular .build directory
    func buildDependencies(
        packagePath: Basics.AbsolutePath,
        target: String,
        buildConfig: BuildConfiguration,
        graph: ModulesGraph,
        observability: ObservabilitySystem,
        fileSystem: any FileSystem
    ) async throws {
        let regularBuildPath = packagePath.appending(component: ".build")
        
        // Create workspace for regular build  
        let _ = try Workspace(
            fileSystem: fileSystem,
            forRootPackage: packagePath,
            authorizationProvider: nil,
            registryAuthorizationProvider: nil,
            configuration: .default,
            cancellator: nil,
            customManifestLoader: nil,
            delegate: nil
        )
        
        // Get all dependencies for the target (including same-package dependencies)
        let targetModule = graph.allModules.first { $0.name == target }!
        let dependencies = targetModule.dependencies.compactMap { dep in
            switch dep {
            case .module(let module, _):
                // Include all module dependencies, even from same package
                return module.name != target ? module.name : nil
            case .product(let product, _):
                return product.name
            }
        }
        
        if dependencies.isEmpty {
            print("   No dependencies to build for target '\(target)'")
            return
        }
        
        print("   Building dependencies: \(dependencies.joined(separator: ", "))")
        
        // Build each dependency
        for dependencyName in dependencies {
            print("   Building dependency: \(dependencyName)")
            
            let toolchain = try UserToolchain(swiftSDK: .hostSwiftSDK())
            let triple = toolchain.targetTriple
            
            let targetBuildParameters = try BuildParameters(
                destination: .target,
                dataPath: regularBuildPath,
                configuration: buildConfig,
                toolchain: toolchain,
                triple: triple,
                flags: BuildFlags(),
                buildSystemKind: .native,
                workers: UInt32(ProcessInfo.processInfo.activeProcessorCount),
                sanitizers: EnabledSanitizers()
            )
            
            let hostBuildParameters = try BuildParameters(
                destination: .host,
                dataPath: regularBuildPath.appending(component: "host"),
                configuration: buildConfig,
                toolchain: toolchain,
                triple: triple,
                flags: BuildFlags(),
                buildSystemKind: .native,
                workers: UInt32(ProcessInfo.processInfo.activeProcessorCount),
                sanitizers: EnabledSanitizers()
            )
            
            let outputStream = try! ThreadSafeOutputByteStream(LocalFileOutputByteStream(
                filePointer: TSCLibc.stderr,
                closeOnDeinit: false))
            
            let pluginConfiguration = PluginConfiguration(
                scriptRunner: DefaultPluginScriptRunner(
                    fileSystem: fileSystem,
                    cacheDir: regularBuildPath.appending(component: "plugin-cache"),
                    toolchain: toolchain
                ),
                workDirectory: regularBuildPath.appending(component: "plugin-cache"),
                disableSandbox: false
            )
            
            let build = BuildOperation(
                productsBuildParameters: targetBuildParameters,
                toolsBuildParameters: hostBuildParameters,
                cacheBuildManifest: false,
                packageGraphLoader: { graph },
                pluginConfiguration: pluginConfiguration,
                scratchDirectory: regularBuildPath.appending(component: "scratch"),
                additionalFileRules: [],
                pkgConfigDirectories: [],
                outputStream: outputStream,
                logLevel: .info,
                fileSystem: fileSystem,
                observabilityScope: observability.topScope
            )
            
            try await build.build(subset: BuildSubset.target(dependencyName))
        }
        
        print("   Dependencies build completed!")
    }
    
    // Link pre-built dependencies to fuzz build directory
    func linkDependenciesToFuzzBuild(
        packagePath: Basics.AbsolutePath,
        target: String,
        buildConfig: BuildConfiguration,
        graph: ModulesGraph,
        fileSystem: any FileSystem,
        fuzzBuildPath: Basics.AbsolutePath
    ) async throws {
        let regularBuildPath = packagePath.appending(component: ".build")
        let fuzzBuildDir = fuzzBuildPath.appending(component: buildConfig.dirname)
        
        // Ensure fuzz build directories exist
        let fuzzModulesDir = fuzzBuildDir.appending(component: "Modules")
        if !fileSystem.exists(fuzzModulesDir) {
            try fileSystem.createDirectory(fuzzModulesDir, recursive: true)
        }
        
        // Get dependencies for the target
        let targetModule = graph.allModules.first { $0.name == target }!
        let dependencies = targetModule.dependencies.compactMap { dep in
            switch dep {
            case .module(let module, _):
                return module.name
            case .product(let product, _):
                return product.name
            }
        }
        
        // Get all transitive dependencies recursively
        var allDependencies = Set<String>()
        var toProcess = dependencies
        
        while !toProcess.isEmpty {
            let dep = toProcess.removeFirst()
            if allDependencies.contains(dep) { continue }
            allDependencies.insert(dep)
            
            // Find this dependency's dependencies
            if let depModule = graph.allModules.first(where: { $0.name == dep }) {
                let subDeps = depModule.dependencies.compactMap { subDep in
                    switch subDep {
                    case .module(let module, _):
                        return module.name
                    case .product(let product, _):
                        return product.name
                    }
                }
                toProcess.append(contentsOf: subDeps)
            }
        }
        
        print("   Linking \(allDependencies.count) dependencies: \(allDependencies.sorted().joined(separator: ", "))")
        
        // Link/copy dependency modules from regular build to fuzz build
        // SwiftPM uses different paths for target vs tool modules
        // For release builds, modules might be in the top-level .build/release/Modules directory
        let regularModulesDir = regularBuildPath.appending(components: buildConfig.dirname, "Modules")
        let regularPlatformModulesDir = regularBuildPath.appending(components: "arm64-apple-macosx", buildConfig.dirname, "Modules")
        let regularToolModulesDir = regularBuildPath.appending(components: "host", buildConfig.dirname, "Modules-tool")
        
        for dependency in allDependencies {
            // Try all possible module locations
            let modulesLocations = [regularModulesDir, regularPlatformModulesDir, regularToolModulesDir]
            
            for modulesDir in modulesLocations {
                // Link .swiftmodule files
                let swiftModuleName = "\(dependency).swiftmodule"
                let sourceModule = modulesDir.appending(component: swiftModuleName)
                let targetModule = fuzzModulesDir.appending(component: swiftModuleName)
                
                if fileSystem.exists(sourceModule) && !fileSystem.exists(targetModule) {
                    do {
                        try fileSystem.createSymbolicLink(targetModule, pointingAt: sourceModule, relative: false)
                        print("   Linked module: \(swiftModuleName)")
                    } catch {
                        // If symlink fails, try copying
                        try fileSystem.copy(from: sourceModule, to: targetModule)
                        print("   Copied module: \(swiftModuleName)")
                    }
                    break // Found and linked, move to next dependency
                }
                
                // Also link other related files (.swiftdoc, .swiftsourceinfo, .abi.json)
                for ext in [".swiftdoc", ".swiftsourceinfo", ".abi.json"] {
                    let fileName = "\(dependency)\(ext)"
                    let sourceFile = modulesDir.appending(component: fileName)
                    let targetFile = fuzzModulesDir.appending(component: fileName)
                    
                    if fileSystem.exists(sourceFile) && !fileSystem.exists(targetFile) {
                        do {
                            try fileSystem.createSymbolicLink(targetFile, pointingAt: sourceFile, relative: false)
                        } catch {
                            try? fileSystem.copy(from: sourceFile, to: targetFile)
                        }
                    }
                }
            }
            
            // Link library files (.a, .dylib) from both regular and tool build dirs
            let libLocations = [
                regularBuildPath.appending(components: "arm64-apple-macosx", buildConfig.dirname),
                regularBuildPath.appending(components: "host", buildConfig.dirname)
            ]
            
            for libDir in libLocations {
                for ext in [".a", ".dylib"] {
                    let libName = "lib\(dependency)\(ext)"
                    let sourceLib = libDir.appending(component: libName)
                    let targetLib = fuzzBuildDir.appending(component: libName)
                    
                    if fileSystem.exists(sourceLib) && !fileSystem.exists(targetLib) {
                        do {
                            try fileSystem.createSymbolicLink(targetLib, pointingAt: sourceLib, relative: false)
                            print("   Linked library: \(libName)")
                        } catch {
                            try? fileSystem.copy(from: sourceLib, to: targetLib)
                            print("   Copied library: \(libName)")
                        }
                        break
                    }
                }
            }
        }
        
        print("   Dependency linking completed!")
    }
    
    // Build target with fuzz instrumentation in .fuzz directory
    func buildTargetWithFuzzInstrumentation(
        packagePath: Basics.AbsolutePath,
        target: String,
        buildConfig: BuildConfiguration,
        graph: ModulesGraph,
        observability: ObservabilitySystem,
        fileSystem: any FileSystem,
        fuzzRootPath: Basics.AbsolutePath,
        fuzzBuildPath: Basics.AbsolutePath,
        hostBuildPath: Basics.AbsolutePath,
        scratchPath: Basics.AbsolutePath,
        pluginCachePath: Basics.AbsolutePath
    ) async throws {
        let toolchain = try UserToolchain(swiftSDK: .hostSwiftSDK())
        let triple = toolchain.targetTriple
        let regularBuildPath = packagePath.appending(component: ".build")
        
        // Create a minimal package graph containing only the target module
        // This prevents SwiftPM from seeing and rebuilding dependencies
        let targetModule = graph.allModules.first { $0.name == target }!
        
        // Create build parameters that link to regular build dependencies
        let regularBuildDir = regularBuildPath.appending(component: buildConfig.dirname)
        let regularTargetBuildDir = regularBuildPath.appending(components: "arm64-apple-macosx", buildConfig.dirname)
        let regularHostBuildDir = regularBuildPath.appending(components: "host", buildConfig.dirname)
        
        // Get all dependency module search paths
        var moduleSearchPaths: [String] = []
        
        // Add paths for pre-built dependency modules - check all possible locations
        moduleSearchPaths.append(contentsOf: [
            "-I", regularBuildDir.appending(component: "Modules").pathString,
            "-I", regularTargetBuildDir.appending(component: "Modules").pathString,
            "-I", regularHostBuildDir.appending(component: "Modules-tool").pathString,
            "-I", fuzzBuildPath.appending(component: buildConfig.dirname).appending(component: "Modules").pathString
        ])
        
        // Get object files from pre-built dependencies
        var objectFiles: [String] = []
        
        // Collect all dependency object files that were pre-built 
        let allLinkedDeps = Set(targetModule.dependencies.compactMap { dep in
            switch dep {
            case .module(let module, _):
                return module.name
            case .product(let product, _):
                return product.name
            }
        })
        
        // Also add transitive dependencies for comprehensive linking
        var allDependencies = Set<String>()
        var toProcess = Array(allLinkedDeps)
        
        while !toProcess.isEmpty {
            let dep = toProcess.removeFirst()
            if allDependencies.contains(dep) { continue }
            allDependencies.insert(dep)
            
            // Find this dependency's dependencies
            if let depModule = graph.allModules.first(where: { $0.name == dep }) {
                let subDeps = depModule.dependencies.compactMap { subDep in
                    switch subDep {
                    case .module(let module, _):
                        return module.name
                    case .product(let product, _):
                        return product.name
                    }
                }
                toProcess.append(contentsOf: subDeps)
            }
        }
        
        
        let dependencies = allDependencies
        
        print("   Building target '\(target)' in isolation, linking to dependencies: \(dependencies.sorted().joined(separator: ", "))")
        
        let targetBuildParameters = try BuildParameters(
            destination: .target,
            dataPath: fuzzBuildPath,
            configuration: buildConfig,
            toolchain: toolchain,
            triple: triple,
            flags: BuildFlags(
                swiftCompilerFlags: moduleSearchPaths
            ),
            buildSystemKind: .native,
            workers: UInt32(ProcessInfo.processInfo.activeProcessorCount),
            sanitizers: EnabledSanitizers()
        )
        
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
        
        let outputStream = try! ThreadSafeOutputByteStream(LocalFileOutputByteStream(
            filePointer: TSCLibc.stderr,
            closeOnDeinit: false))
        
        let pluginConfiguration = PluginConfiguration(
            scriptRunner: DefaultPluginScriptRunner(
                fileSystem: fileSystem,
                cacheDir: pluginCachePath,
                toolchain: toolchain
            ),
            workDirectory: pluginCachePath,
            disableSandbox: false
        )
        
        print("   Building isolated target using direct Swift compiler invocation")
        
        // Get target's source files
        let sourceTargetModule = graph.allModules.first { $0.name == target }!
        let sourceFiles = sourceTargetModule.sources.paths.map { $0.pathString }
        
        print("   Found \(sourceFiles.count) source files for target '\(target)'")
        
        // Check if target source contains LLVMFuzzerTestOneInput 
        let targetDefinesLLVMFuzzer = sourceFiles.contains { sourceFile in
            guard let sourcePath = try? Basics.AbsolutePath(validating: sourceFile),
                  fileSystem.exists(sourcePath) else { return false }
            do {
                let content = try fileSystem.readFileContents(sourcePath).description
                return content.contains("LLVMFuzzerTestOneInput")
            } catch {
                return false
            }
        }
        
        // Find object files for all dependencies after checking if target defines LLVMFuzzer
        for depName in allDependencies {
            
            // Look for object files in regular build directories
            let objectLocations = [
                regularTargetBuildDir.appending(component: "\(depName).build"),
                regularBuildDir.appending(component: "\(depName).build"),
                regularHostBuildDir.appending(component: "\(depName).build")
            ]
            
            for objectDir in objectLocations {
                if fileSystem.exists(objectDir) {
                    // Find all .o files in this directory
                    let contents = try fileSystem.getDirectoryContents(objectDir)
                    let objFiles = contents.filter { $0.hasSuffix(".o") }
                    for objFile in objFiles {
                        let objPath = objectDir.appending(component: objFile).pathString
                        
                        // If this is FuzzTest and target defines LLVMFuzzer, create a modified object file
                        if targetDefinesLLVMFuzzer && depName == "FuzzTest" && objFile.contains("FuzzTest") {
                            let modifiedObjPath = fuzzBuildPath.appending(components: buildConfig.dirname, "modified_\(objFile)").pathString
                            
                            // Copy the object file and remove the conflicting symbol using ld
                            let tempProcess = Process()
                            tempProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ld")
                            tempProcess.arguments = [
                                "-r", objPath,
                                "-unexported_symbol", "_LLVMFuzzerTestOneInput",
                                "-o", modifiedObjPath
                            ]
                            
                            do {
                                try tempProcess.run()
                                tempProcess.waitUntilExit()
                                if tempProcess.terminationStatus == 0 {
                                    objectFiles.append(modifiedObjPath)
                                    print("   Created modified FuzzTest object file without LLVMFuzzerTestOneInput")
                                } else {
                                    // Fallback to original if modification fails
                                    objectFiles.append(objPath)
                                }
                            } catch {
                                // Fallback to original if modification fails
                                objectFiles.append(objPath)
                            }
                        } else {
                            objectFiles.append(objPath)
                        }
                    }
                    break // Found object files for this dependency
                }
            }
        }
        
        // Build using direct Swift compiler invocation to completely bypass SwiftPM dependency logic
        let fuzzTargetBuildDir = fuzzBuildPath.appending(component: buildConfig.dirname)
        let outputDir = fuzzTargetBuildDir.appending(component: "\(target).build")
        
        // Ensure output directory exists
        if !fileSystem.exists(outputDir) {
            try fileSystem.createDirectory(outputDir, recursive: true)
        }
        
        let modulesDir = fuzzTargetBuildDir.appending(component: "Modules")
        if !fileSystem.exists(modulesDir) {
            try fileSystem.createDirectory(modulesDir, recursive: true)
        }
        
        // Find all macro dependencies using SwiftPM's dependency resolution
        var macroPluginArgs: [String] = []
        
        // Discover macro dependencies from the target's dependency graph
        let targetDependencies = try targetModule.recursiveDependencies()
        for dependency in targetDependencies {
            if case .module(let depModule, _) = dependency {
                if depModule.type == .macro {
                    let macroPluginPath = regularHostBuildDir.appending(component: "\(depModule.name)-tool")
                    if fileSystem.exists(macroPluginPath) {
                        macroPluginArgs.append(contentsOf: [
                            "-load-plugin-executable", "\(macroPluginPath.pathString)#\(depModule.name)"
                        ])
                        print("   Loading macro plugin: \(depModule.name) at \(macroPluginPath.pathString)")
                    }
                }
            }
        }
        
        print("   Found \(objectFiles.count) dependency object files to link")
        
        // Step 1: Compile target source files to object files
        // Use swiftc from PATH (swiftly-managed) instead of Xcode toolchain to get fuzzer support
        var compileArgs = [
            "swiftc",
            "-module-name", target,
            "-emit-module",
            "-emit-module-path", modulesDir.appending(component: "\(target).swiftmodule").pathString,
            "-c", // Compile only, don't link
            "-target", triple.tripleString,
            "-swift-version", "6",
            "-sdk", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
        ]
        
        // Add discovered macro plugins
        compileArgs.append(contentsOf: macroPluginArgs)
        
        // Add configuration flags
        if buildConfig == .release {
            compileArgs.append("-O")
        } else {
            compileArgs.append(contentsOf: ["-Onone", "-g"])
        }
        
        // Add fuzzer instrumentation flags
        compileArgs.append(contentsOf: ["-sanitize=fuzzer", "-parse-as-library"])
        
        // Add module search paths for dependencies
        compileArgs.append(contentsOf: moduleSearchPaths)
        
        // Add source files
        compileArgs.append(contentsOf: sourceFiles)
        
        print("   Step 1: Compiling target source files to object files")
        print("   Using compiler: \(compileArgs[0])")
        
        // Execute the compiler
        let compileProcess = Process()
        compileProcess.launchPath = "/usr/bin/env"
        compileProcess.arguments = compileArgs
        compileProcess.currentDirectoryPath = outputDir.pathString
        
        try compileProcess.run()
        compileProcess.waitUntilExit()
        
        guard compileProcess.terminationStatus == 0 else {
            throw StringError("Swift compilation failed with exit code: \(compileProcess.terminationStatus)")
        }
        
        // Step 2: Find the generated object files for the target
        let targetObjectFiles = try fileSystem.getDirectoryContents(outputDir)
            .filter { $0.hasSuffix(".o") }
            .map { outputDir.appending(component: $0).pathString }
        
        print("   Step 2: Linking \(targetObjectFiles.count) target object files with \(objectFiles.count) dependency object files")
        
        // Step 3: Link all object files together
        var linkArgs = [
            "swiftc",
            "-target", triple.tripleString,
            "-sdk", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk",
            "-sanitize=fuzzer",  // Link with fuzzer runtime
            "-o", fuzzTargetBuildDir.appending(component: target).pathString
        ]
        
        // Add target object files first (they take precedence over dependency symbols)
        linkArgs.append(contentsOf: targetObjectFiles)
        
        // Add dependency object files
        linkArgs.append(contentsOf: objectFiles)
        
        let linkProcess = Process()
        linkProcess.launchPath = "/usr/bin/env"
        linkProcess.arguments = linkArgs
        
        try linkProcess.run()
        linkProcess.waitUntilExit()
        
        guard linkProcess.terminationStatus == 0 else {
            throw StringError("Swift linking failed with exit code: \(linkProcess.terminationStatus)")
        }
        
        print("   Direct Swift compilation completed successfully")
    }
}