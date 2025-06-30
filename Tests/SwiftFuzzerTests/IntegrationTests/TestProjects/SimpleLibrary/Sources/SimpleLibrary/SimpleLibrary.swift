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

// Fuzz test functions
@fuzzTest  // Macro not available during subprocess swift build
public func fuzzProcessBuffer(_ data: Data) {
    _ = SimpleLibrary.processBuffer(data)
}

@fuzzTest  // Macro not available during subprocess swift build
public func fuzzCalculateSum(_ data: Data) {
    _ = SimpleLibrary.calculateSum(data)
}

@fuzzTest  // Macro not available during subprocess swift build  
public func fuzzParseStructuredData(_ data: Data) {
    _ = SimpleLibrary.parseStructuredData(data)
}
