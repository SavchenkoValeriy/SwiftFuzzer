// Sources/SwiftFuzzerLib/SwiftFuzzerLib.swift
import Foundation
import Basics
import PackageModel
import Workspace
import PackageGraph
import SPMBuildCore
import Build
import TSCBasic
import TSCLibc
import FuzzTest

public struct StringError: Error {
    public let message: String
    public init(_ message: String) {
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

public struct SwiftFuzzerOptions {
    public let packagePath: String
    public let configuration: String
    public let target: String
    public let buildOnly: Bool
    public let maxTotalTime: Int?
    public let runs: Int?
    public let corpus: String?
    
    public init(
        packagePath: String,
        configuration: String = "debug",
        target: String,
        buildOnly: Bool = false,
        maxTotalTime: Int? = nil,
        runs: Int? = nil,
        corpus: String? = nil
    ) {
        self.packagePath = packagePath
        self.configuration = configuration
        self.target = target
        self.buildOnly = buildOnly
        self.maxTotalTime = maxTotalTime
        self.runs = runs
        self.corpus = corpus
    }
}

public struct SwiftFuzzerCore {
    
    public static func run(options: SwiftFuzzerOptions) async throws {
        print("Building package at: \(options.packagePath)")
        
        let packagePath = try Basics.AbsolutePath(validating: options.packagePath)
        let buildConfig = options.configuration == "release" ? BuildConfiguration.release : BuildConfiguration.debug
        
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
        let targetExists = graph.allModules.contains { $0.name == options.target }
        guard targetExists else {
            print("\nError: Target '\(options.target)' not found in package.")
            print("Available targets:")
            for module in graph.allModules {
                print("  - \(module.name) (type: \(module.type))")
            }
            throw StringError("Target '\(options.target)' not found")
        }
        
        print("\nBuilding target: \(options.target) with fuzz instrumentation")
        
        // Always build dependencies in regular .build directory to ensure they're up-to-date
        // This is necessary because source files might have changed since last build
        print("\n🏗️  Step 1: Building dependencies in regular .build directory...")
        print("   This step ensures all dependencies are built before we create the fuzz target")
        print("   If this hangs, try running 'swift build' manually in your project first")
        
        do {
            try await buildDependencies(
                packagePath: packagePath,
                target: options.target,
                buildConfig: buildConfig,
                graph: graph,
                observability: observability,
                fileSystem: fileSystem
            )
        } catch {
            print("   ❌ Step 1 failed: \(error)")
            throw error
        }
        
        // Step 2: Link pre-built dependencies to fuzz directory
        print("\n🔗 Step 2: Linking dependencies to fuzz build...")
        try await linkDependenciesToFuzzBuild(
            packagePath: packagePath,
            target: options.target,
            buildConfig: buildConfig,
            graph: graph,
            fileSystem: fileSystem,
            fuzzBuildPath: fuzzBuildPath
        )
        
        // Step 3: Build only the specific target in .fuzz directory  
        print("\n🎯 Step 3: Building target '\(options.target)' with isolated build...")
        try await buildTargetWithFuzzInstrumentation(
            packagePath: packagePath,
            target: options.target,
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
        
        // Run the fuzzer if not build-only mode
        if !options.buildOnly {
            print("\n🚀 Running fuzzer...")
            let fuzzTargetBuildDir = fuzzBuildPath.appending(component: buildConfig.dirname)
            let fuzzerExecutable = fuzzTargetBuildDir.appending(component: options.target)
            
            try await runFuzzer(
                executablePath: fuzzerExecutable,
                packagePath: packagePath,
                buildConfig: buildConfig,
                options: options
            )
        }
    }
    
    // Build dependencies in regular .build directory using subprocess swift build
    static func buildDependencies(
        packagePath: Basics.AbsolutePath,
        target: String,
        buildConfig: BuildConfiguration,
        graph: ModulesGraph,
        observability: ObservabilitySystem,
        fileSystem: any FileSystem
    ) async throws {
        print("   Building all dependencies with regular swift build subprocess...")
        print("   Working directory: \(packagePath.pathString)")
        print("   Configuration: \(buildConfig.dirname)")
        
        // Use subprocess swift build which is more reliable than internal BuildOperation
        let buildProcess = Process()
        buildProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        buildProcess.arguments = [
            "swift", "build", 
            "-c", buildConfig.dirname
        ]
        buildProcess.currentDirectoryPath = packagePath.pathString
        
        print("   Command: swift build -c \(buildConfig.dirname)")
        print("   Starting build process...")
        
        // Use the simplest possible subprocess approach
        buildProcess.standardOutput = nil
        buildProcess.standardError = nil
        
        try buildProcess.run()
        buildProcess.waitUntilExit()
        
        let exitCode = buildProcess.terminationStatus
        print("   Build process completed with exit code: \(exitCode)")
        
        guard exitCode == 0 else {
            throw StringError("Dependencies build failed with exit code: \(exitCode)")
        }
        
        print("   Dependencies build completed successfully!")
    }
    
    // Link pre-built dependencies to fuzz build directory
    static func linkDependenciesToFuzzBuild(
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
    static func buildTargetWithFuzzInstrumentation(
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
        let regularHostBuildDir = regularTargetBuildDir  // Use target build dir since that's where macro tools are built
        
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
        
        // Set up output directory early for fuzzer entrypoint generation
        let fuzzTargetBuildDir = fuzzBuildPath.appending(component: buildConfig.dirname)
        let outputDir = fuzzTargetBuildDir.appending(component: "\(target).build")
        
        // Ensure output directory exists
        if !fileSystem.exists(outputDir) {
            try fileSystem.createDirectory(outputDir, recursive: true)
        }
        
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
        
        // Always generate fuzzer entrypoint file for automatic integration
        var allSourceFiles = sourceFiles
        let fuzzerEntrypointPath = outputDir.appending(component: "FuzzerEntrypoint.swift")
        let fuzzerEntrypointContent = """
import Foundation
import FuzzTest

// Signal handler for crash analysis
func crashSignalHandler(signal: Int32) {
    print("\\n🚨 FATAL ERROR DETECTED 🚨")
    print("Signal: \\(signal)")
    
    // Get crash analysis from the registry
    if let crashInfo = FuzzTestRegistry.getLastCrashInfo() {
        print("\\n📍 Crashed Function: \\(crashInfo.functionFQN)")
        print("🔢 Function Hash: 0x\\(String(crashInfo.functionHash, radix: 16, uppercase: true))")
        print("📊 Input: \\(crashInfo.rawInput.count) bytes")
        print("🔄 Reproduction Code:")
        print("```swift")
        print("\\(crashInfo.swiftReproductionCode)")
        print("```")
        print("📋 Arguments: \\(crashInfo.decodedArguments.joined(separator: ", "))")
        print("💾 Raw Input: \\(crashInfo.rawInput.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " "))")
    } else {
        print("❌ No crash analysis available")
    }
    
    print("\\n💡 To reproduce: Copy the Swift code above into a test function")
    exit(signal)
}

@_cdecl("LLVMFuzzerTestOneInput")
public func LLVMFuzzerTestOneInput(_ data: UnsafePointer<UInt8>, _ size: Int) -> Int32 {
    // Install signal handlers for crash analysis
    signal(SIGABRT, crashSignalHandler)
    signal(SIGSEGV, crashSignalHandler)
    signal(SIGBUS, crashSignalHandler)
    signal(SIGFPE, crashSignalHandler)
    signal(SIGILL, crashSignalHandler)
    
    let testData = Data(bytes: data, count: size)
    
    FuzzTestRegistry.initialize()
    
    // Use hash-based dispatch for corpus stability
    // First 4 bytes select function, remaining bytes are function input
    FuzzTestRegistry.runSelected(with: testData)
    
    return 0
}

@_cdecl("LLVMFuzzerCustomCrossOver")
public func LLVMFuzzerCustomCrossOver(
    _ data1: UnsafePointer<UInt8>, _ size1: Int,
    _ data2: UnsafePointer<UInt8>, _ size2: Int,
    _ out: UnsafeMutablePointer<UInt8>, _ maxOutSize: Int,
    _ seed: UInt32
) -> Int {
    // Simple crossover: interleave bytes from both inputs
    guard maxOutSize > 0 else { return 0 }
    
    var outOffset = 0
    let maxSize = min(maxOutSize, max(size1, size2))
    
    for i in 0..<maxSize {
        let useByte1 = ((seed + UInt32(i)) % 2) == 0
        if useByte1 && i < size1 {
            out[outOffset] = data1[i]
        } else if !useByte1 && i < size2 {
            out[outOffset] = data2[i]
        } else if i < size1 {
            out[outOffset] = data1[i]
        } else if i < size2 {
            out[outOffset] = data2[i]
        } else {
            break
        }
        outOffset += 1
    }
    
    return outOffset
}
"""
        try fileSystem.writeFileContents(fuzzerEntrypointPath, string: fuzzerEntrypointContent)
        allSourceFiles.append(fuzzerEntrypointPath.pathString)
        print("   Generated fuzzer entrypoint file: FuzzerEntrypoint.swift")
        
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
                        objectFiles.append(objPath)
                    }
                    break // Found object files for this dependency
                }
            }
        }
        
        // Build using direct Swift compiler invocation to completely bypass SwiftPM dependency logic
        
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
        
        // Add source files (including generated entrypoint if needed)
        compileArgs.append(contentsOf: allSourceFiles)
        
        print("   Step 1: Compiling target source files to object files")
        print("   Using compiler: \(compileArgs[0])")
        print("   Compile command: \(compileArgs.joined(separator: " "))")
        
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
    
    // Run the fuzzer executable with libFuzzer
    static func runFuzzer(
        executablePath: Basics.AbsolutePath,
        packagePath: Basics.AbsolutePath,
        buildConfig: BuildConfiguration,
        options: SwiftFuzzerOptions
    ) async throws {
        let fileSystem = Basics.localFileSystem
        
        // Ensure the executable exists
        guard fileSystem.exists(executablePath) else {
            throw StringError("Fuzzer executable not found at: \(executablePath.pathString)")
        }
        
        // Create corpus directory if specified or use default
        let corpusPath: Basics.AbsolutePath
        if let corpusDir = options.corpus {
            corpusPath = try Basics.AbsolutePath(validating: corpusDir)
        } else {
            corpusPath = packagePath.appending(component: "corpus")
        }
        
        if !fileSystem.exists(corpusPath) {
            try fileSystem.createDirectory(corpusPath, recursive: true)
            print("   Created corpus directory: \(corpusPath.pathString)")
        }
        
        // Create crash analysis directory
        let crashPath = packagePath.appending(component: "crash")
        if !fileSystem.exists(crashPath) {
            try fileSystem.createDirectory(crashPath, recursive: true)
        }
        
        // Build fuzzer arguments with crash artifact handling
        var fuzzerArgs: [String] = []
        
        // Add time limit if specified
        if let maxTime = options.maxTotalTime {
            fuzzerArgs.append(contentsOf: ["-max_total_time=\(maxTime)"])
        }
        
        // Add run count if specified
        if let runCount = options.runs {
            fuzzerArgs.append(contentsOf: ["-runs=\(runCount)"])
        }
        
        // Add crash artifact path
        fuzzerArgs.append(contentsOf: ["-artifact_prefix=\(crashPath.pathString)/"])
        
        // Add corpus directory
        fuzzerArgs.append(corpusPath.pathString)
        
        print("   Fuzzer executable: \(executablePath.pathString)")
        print("   Corpus directory: \(corpusPath.pathString)")
        print("   Crash artifacts: \(crashPath.pathString)")
        print("   Fuzzer arguments: \(fuzzerArgs.joined(separator: " "))")
        
        // Create pipes to capture output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        // Run the fuzzer
        let fuzzerProcess = Process()
        fuzzerProcess.executableURL = URL(fileURLWithPath: executablePath.pathString)
        fuzzerProcess.arguments = fuzzerArgs
        fuzzerProcess.currentDirectoryPath = packagePath.pathString
        fuzzerProcess.standardOutput = outputPipe
        fuzzerProcess.standardError = errorPipe
        
        print("\n🔍 Starting libFuzzer (Press Ctrl+C to stop)...")
        print("📊 Monitoring for crashes and providing instant analysis...")
        
        // Start monitoring output in background
        let outputData = outputPipe.fileHandleForReading
        let errorData = errorPipe.fileHandleForReading
        
        Task {
            do {
                for try await line in outputData.bytes.lines {
                    print(line)
                    // Forward output while monitoring for crashes
                    if line.contains("CRASHED") || line.contains("AddressSanitizer") || line.contains("ERROR") {
                        await handleCrashDetected(crashPath: crashPath, packagePath: packagePath)
                    }
                }
            } catch {
                print("Error reading fuzzer output: \(error)")
            }
        }
        
        Task {
            do {
                for try await line in errorData.bytes.lines {
                    fputs("\(line)\n", stderr)
                }
            } catch {
                print("Error reading fuzzer error output: \(error)")
            }
        }
        
        try fuzzerProcess.run()
        fuzzerProcess.waitUntilExit()
        
        let exitCode = fuzzerProcess.terminationStatus
        
        // Check for crash artifacts and analyze them
        if exitCode != 0 {
            print("\n🐛 Fuzzer detected issues (exit code: \(exitCode))")
            await analyzeCrashArtifacts(crashPath: crashPath, packagePath: packagePath)
        } else {
            print("\n✅ Fuzzer completed successfully - no crashes found!")
        }
    }
    
    // Handle real-time crash detection
    static func handleCrashDetected(crashPath: Basics.AbsolutePath, packagePath: Basics.AbsolutePath) async {
        print("\n🚨 CRASH DETECTED! Preparing analysis...")
    }
    
    // Analyze crash artifacts and provide user-friendly reports
    static func analyzeCrashArtifacts(crashPath: Basics.AbsolutePath, packagePath: Basics.AbsolutePath) async {
        let fileSystem = Basics.localFileSystem
        
        print("\n🔍 Analyzing crash artifacts...")
        
        // First check for our enhanced crash analysis file
        let crashAnalysisPath = "/tmp/swift_fuzzer_crash_analysis.txt"
        if let analysisAbsPath = try? Basics.AbsolutePath(validating: crashAnalysisPath),
           fileSystem.exists(analysisAbsPath) {
            do {
                let analysisContent = try String(contentsOfFile: crashAnalysisPath, encoding: .utf8)
                print(analysisContent)
                // Clean up the file after displaying
                try fileSystem.removeFileTree(analysisAbsPath)
                return
            } catch {
                print("   Error reading crash analysis file: \(error)")
            }
        }
        
        do {
            let crashFiles = try fileSystem.getDirectoryContents(crashPath)
                .filter { $0.hasPrefix("crash-") || $0.hasPrefix("leak-") || $0.hasPrefix("timeout-") }
                .sorted()
            
            if crashFiles.isEmpty {
                print("   No crash artifacts found in \(crashPath.pathString)")
                print("   ⚠️  This might be a Swift fatal error - check console output above for details")
                return
            }
            
            print("   Found \(crashFiles.count) crash artifact(s):")
            
            for (index, crashFile) in crashFiles.enumerated() {
                let crashFilePath = crashPath.appending(component: crashFile)
                print("   📄 \(crashFile)")
                
                // Analyze the crash file
                if let crashData = try? fileSystem.readFileContents(crashFilePath) {
                    await analyzeSingleCrash(
                        crashData: Data(crashData.contents),
                        crashFileName: crashFile,
                        index: index + 1,
                        packagePath: packagePath
                    )
                }
            }
            
            // Provide actionable next steps
            print("""
            
            💡 Next Steps:
            1. The crashes have been automatically analyzed above
            2. Look for the Swift reproduction code to understand what failed
            3. Add the reproduction code to your test suite to prevent regressions
            4. Fix the underlying issue and re-run the fuzzer
            
            🔧 To reproduce crashes manually:
               Add the shown Swift code to a test function and run your tests
            
            """)
            
        } catch {
            print("   Error analyzing crash artifacts: \(error)")
        }
    }
    
    // Analyze a single crash file and provide detailed report
    static func analyzeSingleCrash(
        crashData: Data,
        crashFileName: String,
        index: Int,
        packagePath: Basics.AbsolutePath
    ) async {
        print("\n" + String(repeating: "=", count: 60))
        print("   🚨 CRASH #\(index): \(crashFileName)")
        print(String(repeating: "=", count: 60))
        
        // Use the crash analysis system we built
        if let report = FuzzTestRegistry.analyzeCrash(fromData: crashData) {
            print(report)
        } else {
            // Fallback analysis for unrecognized crash data
            print("""
            ❌ Could not parse crash data format
            
            📊 Raw crash data:
            • Size: \(crashData.count) bytes
            • Hex: \(crashData.prefix(64).map { String(format: "%02X", $0) }.joined(separator: " "))\(crashData.count > 64 ? "..." : "")
            
            💡 This might be a crash format not yet supported by SwiftFuzzer's analysis.
            You can still use this data to reproduce the crash manually.
            """)
        }
        
        // Create reproduction test file automatically
        let reproductionPath = packagePath.appending(component: "crash").appending(component: "CrashReproduction\(index).swift")
        if FuzzTestRegistry.createReproductionTest(
            crashData: crashData,
            outputPath: reproductionPath.pathString,
            testFunctionName: "testCrash\(index)Reproduction"
        ) {
            print("""
            
            ✅ Auto-generated reproduction test at:
               \(reproductionPath.pathString)
            
            """)
        }
    }
}