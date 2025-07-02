import Foundation
import TSCBasic

/// User-friendly error reporting and progress tracking system for SwiftFuzzer
public struct UserInterface {
    
    // MARK: - Progress Tracking
    
    public static func showPhaseStart(_ phase: Phase) {
        let emoji = phase.emoji
        let title = phase.title
        print("\n\(emoji) \(title)")
        print(String(repeating: "─", count: title.count + 3))
    }
    
    public static func showStep(_ step: String, isSubStep: Bool = false) {
        let prefix = isSubStep ? "  →" : "•"
        print("\(prefix) \(step)")
    }
    
    public static func showSuccess(_ message: String) {
        print("✅ \(message)")
    }
    
    public static func showProgress(_ current: Int, _ total: Int, _ description: String) {
        let percentage = Int((Double(current) / Double(total)) * 100)
        let progressBar = generateProgressBar(current: current, total: total)
        print("  \(progressBar) \(percentage)% - \(description)")
    }
    
    private static func generateProgressBar(current: Int, total: Int, width: Int = 20) -> String {
        let filled = Int((Double(current) / Double(total)) * Double(width))
        let empty = width - filled
        return "[\(String(repeating: "█", count: filled))\(String(repeating: "░", count: empty))]"
    }
    
    // MARK: - Error Reporting
    
    public static func reportError(_ error: DiagnosticError) throws {
        print("\n❌ \(error.title)")
        print(String(repeating: "═", count: error.title.count + 3))
        
        print("\n💡 What happened:")
        print("   \(error.description)")
        
        if !error.possibleCauses.isEmpty {
            print("\n🔍 Possible causes:")
            for (index, cause) in error.possibleCauses.enumerated() {
                print("   \(index + 1). \(cause)")
            }
        }
        
        if !error.solutions.isEmpty {
            print("\n🛠️  How to fix:")
            for (index, solution) in error.solutions.enumerated() {
                print("   \(index + 1). \(solution)")
            }
        }
        
        if let example = error.example {
            print("\n📝 Example:")
            print("   \(example)")
        }
        
        if !error.relatedCommands.isEmpty {
            print("\n🔧 Try these commands:")
            for command in error.relatedCommands {
                print("   \(command)")
            }
        }
        
        print("")
        
        // Create a StringError for backwards compatibility with tests
        throw StringError(error.title)
    }
    
    public static func reportWarning(_ warning: DiagnosticWarning) {
        print("\n⚠️  \(warning.title)")
        print("   \(warning.message)")
        if let suggestion = warning.suggestion {
            print("   💡 \(suggestion)")
        }
    }
    
    // MARK: - Crash Analysis
    
    public static func reportCrash(_ crash: CrashReport) {
        print("\n" + String(repeating: "🚨", count: 10))
        print("   CRASH DETECTED")  
        print(String(repeating: "🚨", count: 10))
        
        print("\n📍 Function: \(crash.functionName)")
        print("📊 Input size: \(crash.inputSize) bytes")
        print("⚡ Crash type: \(crash.crashType.description)")
        
        print("\n🔄 Reproduce this crash:")
        print("```swift")
        print(crash.reproductionCode)
        print("```")
        
        print("\n💾 Raw input (first 32 bytes):")
        print("   \(crash.rawInputHex)")
        
        if !crash.suggestedFixes.isEmpty {
            print("\n🛠️  Suggested fixes:")
            for (index, fix) in crash.suggestedFixes.enumerated() {
                print("   \(index + 1). \(fix)")
            }
        }
        
        print("\n📁 Crash saved to: \(crash.artifactPath)")
    }
    
    // MARK: - Validation Messages
    
    public static func validateEnvironment() throws {
        // Check for required tools and dependencies
        let requiredTools = ["swift", "clang"]
        var missingTools: [String] = []
        
        for tool in requiredTools {
            if !isCommandAvailable(tool) {
                missingTools.append(tool)
            }
        }
        
        if !missingTools.isEmpty {
            let error = DiagnosticError.missingTools(missingTools)
            try reportError(error)
        }
        
        // Check Swift version
        if let version = getSwiftVersion(), !isSwiftVersionSupported(version) {
            let error = DiagnosticError.unsupportedSwiftVersion(version)
            try reportError(error)
        }
    }
    
    private static func isCommandAvailable(_ command: String) -> Bool {
        let process = Process()
        process.launchPath = "/usr/bin/which"
        process.arguments = [command]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private static func getSwiftVersion() -> String? {
        let process = Process()
        process.launchPath = "/usr/bin/swift"
        process.arguments = ["--version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Extract version from output like "Swift version 5.9.0"
            let regex = try NSRegularExpression(pattern: "Swift version ([0-9.]+)")
            let range = NSRange(output.startIndex..., in: output)
            if let match = regex.firstMatch(in: output, options: [], range: range) {
                let versionRange = Range(match.range(at: 1), in: output)!
                return String(output[versionRange])
            }
        } catch {
            return nil
        }
        
        return nil
    }
    
    private static func isSwiftVersionSupported(_ version: String) -> Bool {
        // Support Swift 5.9+ (minimum for libFuzzer support)
        let components = version.split(separator: ".").compactMap { Int($0) }
        guard components.count >= 2 else { return false }
        
        let major = components[0]
        let minor = components[1]
        
        return (major > 5) || (major == 5 && minor >= 9)
    }
}

// MARK: - Data Structures

public enum Phase {
    case setup
    case validation
    case buildingDependencies
    case linkingDependencies
    case compilingTarget
    case running
    case analyzing
    
    var emoji: String {
        switch self {
        case .setup: return "🚀"
        case .validation: return "🔍"
        case .buildingDependencies: return "🏗️"
        case .linkingDependencies: return "🔗"
        case .compilingTarget: return "⚡"
        case .running: return "🎯"
        case .analyzing: return "📊"
        }
    }
    
    var title: String {
        switch self {
        case .setup: return "Setting up fuzzer environment"
        case .validation: return "Validating project and dependencies"
        case .buildingDependencies: return "Building project dependencies"
        case .linkingDependencies: return "Linking pre-built dependencies"
        case .compilingTarget: return "Compiling target with fuzzer instrumentation"
        case .running: return "Running fuzzer"
        case .analyzing: return "Analyzing results"
        }
    }
}

public struct DiagnosticError {
    public let title: String
    public let description: String
    public let possibleCauses: [String]
    public let solutions: [String]
    public let example: String?
    public let relatedCommands: [String]
    
    public init(
        title: String,
        description: String,
        possibleCauses: [String],
        solutions: [String],
        example: String?,
        relatedCommands: [String]
    ) {
        self.title = title
        self.description = description
        self.possibleCauses = possibleCauses
        self.solutions = solutions
        self.example = example
        self.relatedCommands = relatedCommands
    }
    
    // Common error factories
    public static func targetNotFound(_ target: String, availableTargets: [String]) -> DiagnosticError {
        return DiagnosticError(
            title: "Target '\(target)' not found",
            description: "The specified target doesn't exist in your Swift package.",
            possibleCauses: [
                "Target name was misspelled",
                "Target is not defined in Package.swift",
                "You're running from wrong directory"
            ],
            solutions: [
                "Check available targets below and use exact name",
                "Verify Package.swift includes your target",
                "Run from your package root directory"
            ],
            example: "swift-fuzz --target \(availableTargets.first ?? "YourTarget")",
            relatedCommands: [
                "swift package describe --type json | jq '.targets[].name'",
                "Available targets: \(availableTargets.joined(separator: ", "))"
            ]
        )
    }
    
    public static func compilationFailed(_ details: String) -> DiagnosticError {
        return DiagnosticError(
            title: "Swift compilation failed",
            description: "Your Swift code couldn't be compiled with fuzzer instrumentation.",
            possibleCauses: [
                "Syntax errors in your Swift code",
                "Missing import statements for FuzzTest",
                "Incompatible Swift language features",
                "Macro dependencies not available"
            ],
            solutions: [
                "Fix compilation errors shown above",
                "Add 'import FuzzTest' to files with @fuzzTest",
                "Ensure Swift 5.9+ features are used correctly",
                "Check macro dependencies are properly configured"
            ],
            example: "@fuzzTest\nfunc testMyFunction(_ data: Data) {\n    // Your test code\n}",
            relatedCommands: [
                "swift build  # Test regular compilation first",
                "swift-fuzz --build-only --target YourTarget  # Debug compilation issues"
            ]
        )
    }
    
    public static func missingTools(_ tools: [String]) -> DiagnosticError {
        return DiagnosticError(
            title: "Required development tools missing",
            description: "SwiftFuzzer needs additional tools that aren't available on your system.",
            possibleCauses: [
                "Development tools not installed",
                "Tools not in your PATH",
                "Using incompatible Swift toolchain"
            ],
            solutions: [
                "Install missing tools: \(tools.joined(separator: ", "))",
                "Use swiftly-managed toolchain with fuzzer support",
                "Add tools to your PATH environment variable"
            ],
            example: "swiftly install main-snapshot",
            relatedCommands: [
                "xcode-select --install  # Install Xcode command line tools",
                "swiftly install main-snapshot  # Install fuzzer-enabled Swift"
            ]
        )
    }
    
    public static func unsupportedSwiftVersion(_ version: String) -> DiagnosticError {
        return DiagnosticError(
            title: "Swift version \(version) is not supported",
            description: "SwiftFuzzer requires Swift 5.9 or later for libFuzzer support.",
            possibleCauses: [
                "Using older Swift version that lacks libFuzzer support",
                "Using Xcode toolchain instead of swiftly",
                "Swift installation missing required fuzzer components"
            ],
            solutions: [
                "Install Swift 5.9+ using swiftly",
                "Use supported Swift toolchain with fuzzer capabilities"
            ],
            example: "swiftly install 5.9-release",
            relatedCommands: [
                "swift --version  # Check current version",
                "swiftly install main-snapshot  # Install latest with fuzzer support"
            ]
        )
    }
    
    public static func noFuzzTests() -> DiagnosticError {
        return DiagnosticError(
            title: "No fuzz tests found in target",
            description: "Your target doesn't contain any functions marked with @fuzzTest.",
            possibleCauses: [
                "No @fuzzTest annotations in your code",
                "Missing FuzzTest import",
                "Functions not public"
            ],
            solutions: [
                "Add @fuzzTest to functions you want to test",
                "Add FuzzTest import in files with fuzz tests",
                "Make fuzz test functions public"
            ],
            example: "import FuzzTest\n\n@fuzzTest\npublic func testMyCode(_ data: Data) {\n    // Test implementation\n}",
            relatedCommands: [
                "grep -r '@fuzzTest' Sources/  # Find existing fuzz tests"
            ]
        )
    }
}

public struct DiagnosticWarning {
    let title: String
    let message: String
    let suggestion: String?
}

public struct CrashReport {
    public let functionName: String
    public let inputSize: Int
    public let crashType: CrashType
    public let reproductionCode: String
    public let rawInputHex: String
    public let suggestedFixes: [String]
    public let artifactPath: String
    
    public init(
        functionName: String,
        inputSize: Int,
        crashType: CrashType,
        reproductionCode: String,
        rawInputHex: String,
        suggestedFixes: [String],
        artifactPath: String
    ) {
        self.functionName = functionName
        self.inputSize = inputSize
        self.crashType = crashType
        self.reproductionCode = reproductionCode
        self.rawInputHex = rawInputHex
        self.suggestedFixes = suggestedFixes
        self.artifactPath = artifactPath
    }
}

public enum CrashType: CustomStringConvertible, Equatable {
    case bufferOverflow
    case nullPointerDereference
    case integerOverflow
    case assertionFailure
    case unknown(String)
    
    public var description: String {
        switch self {
        case .bufferOverflow: return "Buffer Overflow"
        case .nullPointerDereference: return "Null Pointer Access"
        case .integerOverflow: return "Integer Overflow"
        case .assertionFailure: return "Assertion Failure"
        case .unknown(let desc): return desc
        }
    }
}
