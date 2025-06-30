import Foundation

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
    
    public static func initialize() {
        guard !Self.singleton.initialized else { return }
        Self.singleton.initialized = true
        
        // Use objc_getClassList to find all classes
        var classCount = objc_getClassList(nil, 0)
        guard classCount > 0 else { return }
        
        let classes = UnsafeMutablePointer<AnyClass?>.allocate(capacity: Int(classCount))
        defer { classes.deallocate() }
        
        classCount = objc_getClassList(AutoreleasingUnsafeMutablePointer(classes), classCount)
        
        var counter = 0
        
        for i in 0..<Int(classCount) {
            guard let cls: AnyClass = classes[i] else { continue }
            let className = String(cString: class_getName(cls))
            // Look for classes with our prefix
            if className.contains("__FuzzTestRegistrator_") {
                // Call the register method on this class
                counter += 1
                if let objcCls = cls as? NSObject.Type {
                    if objcCls.responds(to: Selector(("register"))) {
                        objcCls.perform(Selector(("register")))
                    }
                }
            }
        }
        
        // Sort hashes for binary search
        Self.singleton.sortedHashes = Array(Self.singleton.hashToFunction.keys).sorted()
        
        print("Found \(counter) classes among \(classCount)")
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
        
        // Execute the selected function
        if let (_, adapter) = Self.singleton.hashToFunction[hash] {
            adapter.safeExecute(with: Data(functionData))
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