import Foundation
import FuzzTest

// Simple vulnerable library for testing
public struct SimpleLibrary {
    
    // Buffer overflow vulnerability
    public static func processBuffer(_ data: Data) -> String? {
        guard data.count >= 2 else { return nil }
        
        let length = Int(data[0])
        var buffer = [UInt8](repeating: 0, count: 10)
        
        let payload = data.dropFirst(1)
        for (i, byte) in payload.enumerated() {
            if i < length {  // Bug: length not validated
                buffer[i] = byte  // Will crash when i >= 10
            }
        }
        
        return String(bytes: buffer.prefix(min(length, payload.count)), encoding: .utf8)
    }
    
    // Integer overflow vulnerability
    public static func calculateSum(_ data: Data) -> Int {
        guard !data.isEmpty else { return 0 }
        
        var sum: Int8 = 0  // Small integer type for easy overflow
        for byte in data {
            sum = sum &+ Int8(byte)  // Wrapping addition to prevent crashes
        }
        
        // Division by computed value can still cause crashes
        let divisor = Int(sum)
        if divisor == 0 {
            return Int.max / 1  // Safe operation
        }
        
        return Int.max / divisor  // Could cause issues with extreme values
    }
    
    // Null pointer access simulation
    public static func parseStructuredData(_ data: Data) -> [String] {
        guard data.count >= 1 else { return [] }
        
        let count = Int(data[0])
        guard count > 0 && count < 100 else { return [] }  // Basic bounds check
        
        var results: [String] = []
        var offset = 1
        
        for _ in 0..<count {
            guard offset < data.count else { break }
            
            let length = Int(data[offset])
            offset += 1
            
            guard offset + length <= data.count else {
                // Bug: accessing beyond bounds could cause issues
                let remaining = data.count - offset
                if remaining > 0 {
                    let truncated = data[offset..<data.count]
                    results.append(String(data: truncated, encoding: .utf8) ?? "")
                }
                break
            }
            
            let substring = data[offset..<offset + length]
            results.append(String(data: substring, encoding: .utf8) ?? "")
            offset += length
        }
        
        return results
    }
}

// Fuzz test functions using Data parameters (backwards compatibility)
@fuzzTest
public func fuzzProcessBuffer(_ data: Data) {
    _ = SimpleLibrary.processBuffer(data)
}

@fuzzTest
public func fuzzCalculateSum(_ data: Data) {
    _ = SimpleLibrary.calculateSum(data)
}

@fuzzTest
public func fuzzParseStructuredData(_ data: Data) {
    _ = SimpleLibrary.parseStructuredData(data)
}

// New typed fuzz test functions demonstrating Fuzzable protocol
@fuzzTest
public func fuzzStringProcessing(_ input: String) {
    // Test string processing with auto-generated strings
    let data = Data(input.utf8)
    _ = SimpleLibrary.processBuffer(data)
}

@fuzzTest
public func fuzzIntegerOperations(_ value: Int) {
    // Test integer operations with auto-generated integers
    let data = Data([UInt8(abs(value) % 256)])
    _ = SimpleLibrary.calculateSum(data)
}

@fuzzTest
public func fuzzBooleanLogic(_ flag: Bool) {
    // Test boolean-based logic
    let data = Data([flag ? 1 : 0])
    _ = SimpleLibrary.calculateSum(data)
}

@fuzzTest
public func fuzzMultipleParameters(_ text: String, _ count: Int, _ enabled: Bool) {
    // Test function with multiple typed parameters
    guard !text.isEmpty && count >= 0 else { return }
    
    if enabled {
        let repeatCount = min(count, 10) // Limit repetitions
        var combined = ""
        for _ in 0..<repeatCount {
            combined += text
        }
        let data = Data(combined.utf8)
        _ = SimpleLibrary.processBuffer(data)
    }
}

@fuzzTest
public func fuzzOptionalString(_ maybeText: String?) {
    // Test optional parameter handling
    guard let text = maybeText else { return }
    let data = Data(text.utf8)
    _ = SimpleLibrary.processBuffer(data)
}

@fuzzTest
public func fuzzStringArray(_ strings: [String]) {
    // Test array parameter handling
    for string in strings {
        let data = Data(string.utf8)
        _ = SimpleLibrary.processBuffer(data)
    }
}
