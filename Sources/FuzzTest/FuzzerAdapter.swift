import Foundation

/// A wrapper that adapts typed functions to work with raw fuzzer data
public final class FuzzerAdapter {
    /// The adapted function that takes raw Data and executes the original typed function
    public let function: (Data) throws -> Void
    
    /// Create an adapter for a function with Data parameter (backwards compatibility)
    public init(_ original: @escaping (Data) throws -> Void) {
        self.function = original
    }
    
    /// Create an adapter for a function with Fuzzable parameters using variadic generics
    public init<each T: Fuzzable>(_ original: @escaping (repeat each T) throws -> Void) {
        self.function = { data in
            var offset = 0
            try original(repeat (each T).fuzzableValue(from: data, offset: &offset))
        }
    }
}

// MARK: - FuzzerAdapter Extensions for convenience

extension FuzzerAdapter {
    /// Execute the adapted function with given data, catching and logging errors
    public func safeExecute(with data: Data) {
        do {
            try function(data)
        } catch {
            // Log error but don't crash - this is expected in fuzzing
            print("Fuzz test execution failed: \(error)")
        }
    }
}