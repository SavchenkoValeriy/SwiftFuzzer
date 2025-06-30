import Foundation

/// Registry for fuzz test functions
public class FuzzTestRegistry: @unchecked Sendable {
    private static let singleton = FuzzTestRegistry()

    private var initialized = false
    private var adapters: [(String, FuzzerAdapter)] = []
    
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
        print("Found \(counter) classes among \(classCount)")
    }
    
    /// Register a function for fuzzing using an adapter
    public static func register(name: String, adapter: FuzzerAdapter) {
        Self.singleton.adapters.append((name, adapter))
    }
    
    /// Register a function for fuzzing (backwards compatibility)
    public static func register<T>(name: String, function: @escaping (Data) -> T) {
        let adapter = FuzzerAdapter { data in
            _ = function(data)
        }
        Self.singleton.adapters.append((name, adapter))
    }
    
    /// Get all registered adapters
    public static func getAllAdapters() -> [(String, FuzzerAdapter)] {
        return Self.singleton.adapters
    }
    
    /// Get all registered functions (backwards compatibility)
    public static func getAllFunctions() -> [(String, (Data) -> Void)] {
        return Self.singleton.adapters.map { (name, adapter) in
            (name, { data in
                adapter.safeExecute(with: data)
            })
        }
    }
    
    /// Run all registered functions with the given data
    public static func runAll(with data: Data) {
        for (_, adapter) in Self.singleton.adapters {
            adapter.safeExecute(with: data)
        }
    }
    
    /// Run a specific function by name
    public static func run(named: String, with data: Data) {
        if let (_, adapter) = Self.singleton.adapters.first(where: { $0.0 == named }) {
            adapter.safeExecute(with: data)
        }
    }
    
    /// Reset the registry state - for testing purposes only
    public static func _resetForTesting() {
        Self.singleton.initialized = false
        Self.singleton.adapters.removeAll()
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