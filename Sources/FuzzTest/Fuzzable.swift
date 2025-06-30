import Foundation

/// Protocol for types that can be constructed from fuzzer-provided raw bytes
public protocol Fuzzable {
    /// Create an instance from fuzzer-provided raw bytes
    /// - Parameters:
    ///   - data: The raw bytes provided by the fuzzer
    ///   - offset: Current read position in data, updated after reading
    /// - Returns: An instance of this type constructed from the bytes
    /// - Throws: FuzzError if the data is insufficient or invalid
    static func fuzzableValue(from data: Data, offset: inout Int) throws -> Self
    
    /// Optional hint for the expected size in bytes for better fuzzing efficiency
    /// Return nil for variable-size types
    static var fuzzableSizeHint: Int? { get }
}

/// Errors that can occur during fuzzable value construction
public enum FuzzError: Error, LocalizedError {
    case insufficientData
    case invalidData
    case oversizedCollection
    
    public var errorDescription: String? {
        switch self {
        case .insufficientData:
            return "Not enough data to construct fuzzable value"
        case .invalidData:
            return "Invalid data format for fuzzable value"
        case .oversizedCollection:
            return "Collection size exceeds maximum allowed limit"
        }
    }
}

// MARK: - Basic Type Extensions

extension String: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> String {
        guard offset < data.count else {
            throw FuzzError.insufficientData
        }
        
        // Read length byte (0-255)
        let length = Int(data[offset])
        offset += 1
        
        // Ensure we don't read beyond data bounds
        let availableBytes = data.count - offset
        let actualLength = Swift.min(length, availableBytes)
        
        guard actualLength >= 0 else {
            throw FuzzError.insufficientData
        }
        
        // Extract substring and try to decode as UTF-8
        let substring = data.subdata(in: offset..<offset + actualLength)
        let result = String(data: substring, encoding: .utf8) ?? ""
        
        offset += actualLength
        return result
    }
    
    public static var fuzzableSizeHint: Int? { nil } // Variable size
}

extension Bool: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> Bool {
        guard offset < data.count else {
            throw FuzzError.insufficientData
        }
        
        let value = data[offset] & 1 == 1 // True if odd
        offset += 1
        return value
    }
    
    public static var fuzzableSizeHint: Int? { 1 }
}

extension Int: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> Int {
        guard offset + MemoryLayout<Int>.size <= data.count else {
            throw FuzzError.insufficientData
        }
        
        // Extract 8 bytes and convert to Int using little-endian format
        let bytes = data.subdata(in: offset..<offset + MemoryLayout<Int>.size)
        var value: Int = 0
        _ = bytes.withUnsafeBytes { bytesPtr in
            memcpy(&value, bytesPtr.baseAddress!, MemoryLayout<Int>.size)
        }
        
        offset += MemoryLayout<Int>.size
        return value
    }
    
    public static var fuzzableSizeHint: Int? { MemoryLayout<Int>.size }
}

// MARK: - Collection Extensions

extension Array: Fuzzable where Element: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> [Element] {
        guard offset < data.count else {
            throw FuzzError.insufficientData
        }
        
        // Read count byte (0-255) but limit to reasonable size
        let rawCount = Int(data[offset])
        let maxCount = 32 // Reasonable limit to prevent memory issues
        let count = Swift.min(rawCount, maxCount)
        offset += 1
        
        var result: [Element] = []
        result.reserveCapacity(count)
        
        for _ in 0..<count {
            guard offset < data.count else {
                break // Not enough data for more elements
            }
            
            do {
                let element = try Element.fuzzableValue(from: data, offset: &offset)
                result.append(element)
            } catch {
                break // Stop if we can't construct more elements
            }
        }
        
        return result
    }
    
    public static var fuzzableSizeHint: Int? { nil } // Variable size
}

extension Optional: Fuzzable where Wrapped: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> Wrapped? {
        guard offset < data.count else {
            throw FuzzError.insufficientData
        }
        
        // Read presence flag
        let hasValue = data[offset] & 1 == 1
        offset += 1
        
        if hasValue {
            return try Wrapped.fuzzableValue(from: data, offset: &offset)
        } else {
            return nil
        }
    }
    
    public static var fuzzableSizeHint: Int? { nil } // Variable size
}