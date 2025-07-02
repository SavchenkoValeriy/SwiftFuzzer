import Foundation

/// Crash information for debugging and reproduction
public struct CrashInfo {
    public let functionFQN: String
    public let functionHash: UInt32
    public let rawInput: Data
    public let decodedArguments: [String]
    public let swiftReproductionCode: String
    public let timestamp: Date
    
    public init(functionFQN: String, functionHash: UInt32, rawInput: Data, decodedArguments: [String], swiftReproductionCode: String) {
        self.functionFQN = functionFQN
        self.functionHash = functionHash
        self.rawInput = rawInput
        self.decodedArguments = decodedArguments
        self.swiftReproductionCode = swiftReproductionCode
        self.timestamp = Date()
    }
}

/// Hash function for stable function selection across corpus evolution
private func hashFQN(_ fqn: String) -> UInt32 {
    // Use djb2 hash algorithm for stable, deterministic hashing
    var hash: UInt32 = 5381
    
    for byte in fqn.utf8 {
        hash = ((hash << 5) &+ hash) &+ UInt32(byte)
    }
    
    return hash
}

/// Registry for fuzz test functions with hash-based dispatch for corpus stability
public class FuzzTestRegistry: @unchecked Sendable {
    private static let singleton = FuzzTestRegistry()

    private var initialized = false
    // Hash-based storage: hash -> (fqn, adapter)
    private var hashToFunction: [UInt32: (String, FuzzerAdapter)] = [:]
    private var sortedHashes: [UInt32] = []
    
    // Crash reporting and analysis
    private var lastCrashInfo: CrashInfo?
    @MainActor private static var crashAnalysisEnabled = true
    
    public static func initialize() {
        guard !Self.singleton.initialized else { return }
        Self.singleton.initialized = true
        
        // Use objc_getClassList to find all classes
        var classCount = objc_getClassList(nil, 0)
        guard classCount > 0 else { return }
        
        let classes = UnsafeMutablePointer<AnyClass?>.allocate(capacity: Int(classCount))
        defer { classes.deallocate() }
        
        classCount = objc_getClassList(AutoreleasingUnsafeMutablePointer(classes), classCount)
        
        for i in 0..<Int(classCount) {
            guard let cls: AnyClass = classes[i] else { continue }
            let className = String(cString: class_getName(cls))
            // Look for classes with our prefix
            if className.contains("__FuzzTestRegistrator_") {
                // Call the register method on this class
                if let objcCls = cls as? NSObject.Type {
                    if objcCls.responds(to: Selector(("register"))) {
                        objcCls.perform(Selector(("register")))
                    }
                }
            }
        }
        
        // Sort hashes for binary search
        Self.singleton.sortedHashes = Array(Self.singleton.hashToFunction.keys).sorted()
    }
    
    /// Register a function for fuzzing using FQN (Fully Qualified Name) for proper overload handling
    public static func register(fqn: String, adapter: FuzzerAdapter) {
        let hash = hashFQN(fqn)
        Self.singleton.hashToFunction[hash] = (fqn, adapter)
        // Keep sorted hashes updated for efficient lookup
        if !Self.singleton.sortedHashes.contains(hash) {
            Self.singleton.sortedHashes.append(hash)
            Self.singleton.sortedHashes.sort()
        }
    }
    
    /// Register a function for fuzzing using an adapter (backwards compatibility)
    public static func register(name: String, adapter: FuzzerAdapter) {
        register(fqn: "\(name)(Data)", adapter: adapter)
    }
    
    /// Register a function for fuzzing (backwards compatibility)
    public static func register<T>(name: String, function: @escaping (Data) -> T) {
        let adapter = FuzzerAdapter { data in
            _ = function(data)
        }
        register(fqn: "\(name)(Data)", adapter: adapter)
    }
    
    /// Hash-based function selection - the core of corpus stability
    /// Uses first 4 bytes of data as selector, remaining bytes as function input
    public static func runSelected(with data: Data) {
        guard data.count >= 4 else { return }
        
        // Extract selector from first 4 bytes
        let selector = data.withUnsafeBytes { bytes in
            bytes.load(as: UInt32.self)
        }
        
        // Find function via hash-based lookup with graceful degradation
        let functionData = data.dropFirst(4)
        
        guard !Self.singleton.sortedHashes.isEmpty else { return }
        
        // Binary search for lower_bound equivalent
        let hash: UInt32
        if let _ = Self.singleton.hashToFunction[selector] {
            hash = selector
        } else {
            // Find nearest hash (graceful degradation) using manual binary search
            var left = 0
            var right = Self.singleton.sortedHashes.count
            
            while left < right {
                let mid = left + (right - left) / 2
                if Self.singleton.sortedHashes[mid] < selector {
                    left = mid + 1
                } else {
                    right = mid
                }
            }
            
            if left >= Self.singleton.sortedHashes.count {
                // Wrap around to beginning if selector is larger than all hashes
                hash = Self.singleton.sortedHashes[0]
            } else {
                hash = Self.singleton.sortedHashes[left]
            }
        }
        
        // Execute the selected function with crash analysis
        if let (fqn, adapter) = Self.singleton.hashToFunction[hash] {
            // Prepare crash analysis before execution (for signal handler access)
            prepareCrashAnalysis(fqn: fqn, hash: hash, originalData: data, functionData: Data(functionData), adapter: adapter)
            adapter.safeExecute(with: Data(functionData))
        }
    }
    
    /// Prepare crash analysis information before function execution
    private static func prepareCrashAnalysis(fqn: String, hash: UInt32, originalData: Data, functionData: Data, adapter: FuzzerAdapter) {
        // Always prepare crash analysis for debugging
        
        // Decode arguments to human-readable format
        let decodedArguments = adapter.decodeArguments(from: functionData)
        
        // Generate Swift reproduction code
        let reproductionCode = generateSwiftReproductionCode(fqn: fqn, arguments: decodedArguments)
        
        // Store crash info in case of crash
        Self.singleton.lastCrashInfo = CrashInfo(
            functionFQN: fqn,
            functionHash: hash,
            rawInput: originalData,
            decodedArguments: decodedArguments,
            swiftReproductionCode: reproductionCode
        )
        
        // Write crash analysis to file immediately for fatal error recovery
        writeCrashAnalysisToFile()
    }
    
    /// Write crash analysis to file for fatal error recovery
    private static func writeCrashAnalysisToFile() {
        guard let crashInfo = Self.singleton.lastCrashInfo else { return }
        
        let report = """
        
        🚨 SWIFT FUZZER CRASH ANALYSIS 🚨
        =====================================
        
        📍 Crashed Function: \(crashInfo.functionFQN)
        🔢 Function Hash: 0x\(String(crashInfo.functionHash, radix: 16, uppercase: true))
        📊 Input: \(crashInfo.rawInput.count) bytes
        
        🔄 Reproduction Code:
        ```swift
        \(crashInfo.swiftReproductionCode)
        ```
        
        📋 Arguments: \(crashInfo.decodedArguments.joined(separator: ", "))
        💾 Raw Input: \(crashInfo.rawInput.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " "))\(crashInfo.rawInput.count > 32 ? "..." : "")
        
        💡 To reproduce: Copy the Swift code above into a test function
        
        """
        
        do {
            let crashAnalysisPath = "/tmp/swift_fuzzer_crash_analysis.txt"
            try report.write(toFile: crashAnalysisPath, atomically: true, encoding: .utf8)
            print("💾 Crash analysis saved to: \(crashAnalysisPath)")
        } catch {
            print("❌ Failed to save crash analysis: \(error)")
        }
    }
    
    /// Generate human-readable Swift code to reproduce the crash
    private static func generateSwiftReproductionCode(fqn: String, arguments: [String]) -> String {
        // Extract function name from FQN (everything before the parentheses)
        let functionName = String(fqn.prefix(while: { $0 != "(" }))
        
        // Generate the function call with decoded arguments
        if arguments.isEmpty {
            return "\(functionName)()"
        } else {
            return "\(functionName)(\(arguments.joined(separator: ", ")))"
        }
    }
    
    /// Get all registered adapters (for testing/debugging)
    public static func getAllAdapters() -> [(String, FuzzerAdapter)] {
        return Self.singleton.hashToFunction.values.map { (fqn, adapter) in
            (fqn, adapter)
        }
    }
    
    /// Get all registered functions (backwards compatibility)
    public static func getAllFunctions() -> [(String, (Data) -> Void)] {
        return Self.singleton.hashToFunction.values.map { (fqn, adapter) in
            (fqn, { data in
                adapter.safeExecute(with: data)
            })
        }
    }
    
    /// Get function count (for testing/debugging)
    public static func getFunctionCount() -> Int {
        return Self.singleton.hashToFunction.count
    }
    
    /// Get all hash mappings (for testing/debugging)
    public static func getHashMappings() -> [(UInt32, String)] {
        return Self.singleton.hashToFunction.map { (hash, tuple) in
            (hash, tuple.0)
        }.sorted { $0.0 < $1.0 }
    }
    
    /// Run all registered functions with the given data (legacy - for testing only)
    public static func runAll(with data: Data) {
        for (_, adapter) in Self.singleton.hashToFunction.values {
            adapter.safeExecute(with: data)
        }
    }
    
    /// Run a specific function by FQN (for testing)
    public static func run(fqn: String, with data: Data) {
        for (registeredFqn, adapter) in Self.singleton.hashToFunction.values {
            if registeredFqn == fqn {
                adapter.safeExecute(with: data)
                return
            }
        }
    }
    
    /// Run a specific function by name (for testing - backwards compatibility)
    public static func run(named: String, with data: Data) {
        run(fqn: "\(named)(Data)", with: data)
    }
    
    /// Reset the registry state - for testing purposes only
    public static func _resetForTesting() {
        Self.singleton.initialized = false
        Self.singleton.hashToFunction.removeAll()
        Self.singleton.sortedHashes.removeAll()
        Self.singleton.lastCrashInfo = nil
    }
    
    // MARK: - Crash Analysis and Reporting
    
    /// Enable or disable crash analysis (enabled by default)
    @MainActor public static func setCrashAnalysisEnabled(_ enabled: Bool) {
        crashAnalysisEnabled = enabled
    }
    
    /// Get the last crash information (if any)
    public static func getLastCrashInfo() -> CrashInfo? {
        return Self.singleton.lastCrashInfo
    }
    
    /// Analyze a crash file and generate human-readable report
    public static func analyzeCrash(fromFile crashFilePath: String) -> String? {
        guard let crashData = try? Data(contentsOf: URL(fileURLWithPath: crashFilePath)) else {
            return nil
        }
        return analyzeCrash(fromData: crashData)
    }
    
    /// Analyze crash data and generate human-readable report
    public static func analyzeCrash(fromData crashData: Data) -> String? {
        guard crashData.count >= 4 else {
            return "❌ Invalid crash file: insufficient data (need at least 4 bytes for function selector)"
        }
        
        // Extract selector from first 4 bytes
        let selector = crashData.withUnsafeBytes { bytes in
            bytes.load(as: UInt32.self)
        }
        
        let functionData = crashData.dropFirst(4)
        
        // Find the function that was being executed
        if let (fqn, adapter) = Self.singleton.hashToFunction[selector] {
            // Exact match found
            return generateCrashReport(
                fqn: fqn, 
                hash: selector, 
                originalData: crashData, 
                functionData: Data(functionData), 
                adapter: adapter,
                isExactMatch: true
            )
        } else {
            // Find nearest function (graceful degradation case)
            guard !Self.singleton.sortedHashes.isEmpty else {
                return "❌ No fuzz test functions registered"
            }
            
            // Binary search for nearest hash
            var left = 0
            var right = Self.singleton.sortedHashes.count
            
            while left < right {
                let mid = left + (right - left) / 2
                if Self.singleton.sortedHashes[mid] < selector {
                    left = mid + 1
                } else {
                    right = mid
                }
            }
            
            let nearestHash: UInt32
            if left >= Self.singleton.sortedHashes.count {
                nearestHash = Self.singleton.sortedHashes[0]
            } else {
                nearestHash = Self.singleton.sortedHashes[left]
            }
            
            if let (fqn, adapter) = Self.singleton.hashToFunction[nearestHash] {
                return generateCrashReport(
                    fqn: fqn, 
                    hash: nearestHash, 
                    originalData: crashData, 
                    functionData: Data(functionData), 
                    adapter: adapter,
                    isExactMatch: false,
                    originalSelector: selector
                )
            }
        }
        
        return "❌ Could not identify the crashed function"
    }
    
    /// Generate a comprehensive crash report
    private static func generateCrashReport(
        fqn: String, 
        hash: UInt32, 
        originalData: Data, 
        functionData: Data, 
        adapter: FuzzerAdapter, 
        isExactMatch: Bool,
        originalSelector: UInt32? = nil
    ) -> String {
        let decodedArguments = adapter.decodeArguments(from: functionData)
        let reproductionCode = generateSwiftReproductionCode(fqn: fqn, arguments: decodedArguments)
        
        var report = """
        
        🚨 CRASH ANALYSIS REPORT 🚨
        ============================
        
        📍 Crashed Function: \(fqn)
        🔢 Function Hash: 0x\(String(hash, radix: 16, uppercase: true))
        """
        
        if !isExactMatch, let originalSelector = originalSelector {
            report += """
            
            ⚠️  Note: Exact function not found (graceful degradation)
            🎯 Original Selector: 0x\(String(originalSelector, radix: 16, uppercase: true))
            🔄 Mapped to Nearest: 0x\(String(hash, radix: 16, uppercase: true))
            """
        }
        
        report += """
        
        📝 Arguments:
        \(decodedArguments.isEmpty ? "   (no arguments)" : decodedArguments.enumerated().map { "   [\($0.offset)] \($0.element)" }.joined(separator: "\n"))
        
        🔄 Swift Reproduction Code:
        ```swift
        \(reproductionCode)
        ```
        
        📊 Raw Data Analysis:
        • Total size: \(originalData.count) bytes
        • Function selector: \(originalData.prefix(4).map { String(format: "%02X", $0) }.joined(separator: " "))
        • Function data: \(functionData.count) bytes
        • Hex dump: \(functionData.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " "))\(functionData.count > 32 ? "..." : "")
        
        💡 To reproduce this crash:
        1. Add the following code to your test file:
        ```swift
        func testCrashReproduction() {
            \(reproductionCode)
        }
        ```
        2. Run your tests to reproduce the exact crash
        
        """
        
        return report
    }
    
    /// Create a minimal crash reproduction test file
    public static func createReproductionTest(
        crashData: Data, 
        outputPath: String, 
        testFunctionName: String = "testCrashReproduction"
    ) -> Bool {
        guard analyzeCrash(fromData: crashData) != nil else { return false }
        guard crashData.count >= 4 else { return false }
        
        let selector = crashData.withUnsafeBytes { bytes in
            bytes.load(as: UInt32.self)
        }
        let functionData = crashData.dropFirst(4)
        
        guard let (fqn, adapter) = Self.singleton.hashToFunction[selector] else { return false }
        
        let decodedArguments = adapter.decodeArguments(from: Data(functionData))
        let reproductionCode = generateSwiftReproductionCode(fqn: fqn, arguments: decodedArguments)
        
        let testFileContent = """
        // Auto-generated crash reproduction test
        // Generated from crash data on \(Date())
        
        import XCTest
        @testable import YourModule // Replace with your actual module name
        
        final class CrashReproductionTests: XCTestCase {
            
            func \(testFunctionName)() {
                // This test reproduces the exact crash found by the fuzzer
                // Function: \(fqn)
                // Hash: 0x\(String(selector, radix: 16, uppercase: true))
                
                \(reproductionCode)
            }
        }
        """
        
        do {
            try testFileContent.write(toFile: outputPath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}

/// Marks a function for automatic fuzzing
/// The function can take Data or 1-5 parameters of types conforming to Fuzzable
/// 
/// Examples:
/// ```swift
/// @fuzzTest
/// func parseJSON(_ data: Data) -> Bool {
///     // Your vulnerable parsing code here
///     return true
/// }
/// 
/// @fuzzTest
/// func processString(_ input: String, _ count: Int) {
///     // Fuzzer will generate String and Int from raw bytes
/// }
/// ```
@attached(peer, names: prefixed(__FuzzTestRegistrator_))
public macro fuzzTest() = #externalMacro(module: "FuzzTestMacros", type: "FuzzTestMacro")
