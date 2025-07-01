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
    
    /// Generate a human-readable debug description for crash reporting
    /// - Parameter value: The value to describe
    /// - Returns: A Swift-syntax string representation of the value
    static func debugDescription(for value: Self) -> String
}

// MARK: - Default Implementation

extension Fuzzable {
    /// Default debug description implementation using String interpolation
    public static func debugDescription(for value: Self) -> String {
        return "\(value)"
    }
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
    
    public static func debugDescription(for value: String) -> String {
        // Escape quotes and represent as string literal
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
                          .replacingOccurrences(of: "\"", with: "\\\"")
                          .replacingOccurrences(of: "\n", with: "\\n")
                          .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
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

// MARK: - Signed Integer Extensions

extension Int8: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> Int8 {
        guard offset < data.count else {
            throw FuzzError.insufficientData
        }
        
        let value = Int8(bitPattern: data[offset])
        offset += 1
        return value
    }
    
    public static var fuzzableSizeHint: Int? { 1 }
    
}

extension Int16: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> Int16 {
        guard offset + MemoryLayout<Int16>.size <= data.count else {
            throw FuzzError.insufficientData
        }
        
        let bytes = data.subdata(in: offset..<offset + MemoryLayout<Int16>.size)
        var value: Int16 = 0
        _ = bytes.withUnsafeBytes { bytesPtr in
            memcpy(&value, bytesPtr.baseAddress!, MemoryLayout<Int16>.size)
        }
        
        offset += MemoryLayout<Int16>.size
        return value
    }
    
    public static var fuzzableSizeHint: Int? { MemoryLayout<Int16>.size }
}

extension Int32: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> Int32 {
        guard offset + MemoryLayout<Int32>.size <= data.count else {
            throw FuzzError.insufficientData
        }
        
        let bytes = data.subdata(in: offset..<offset + MemoryLayout<Int32>.size)
        var value: Int32 = 0
        _ = bytes.withUnsafeBytes { bytesPtr in
            memcpy(&value, bytesPtr.baseAddress!, MemoryLayout<Int32>.size)
        }
        
        offset += MemoryLayout<Int32>.size
        return value
    }
    
    public static var fuzzableSizeHint: Int? { MemoryLayout<Int32>.size }
}

extension Int64: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> Int64 {
        guard offset + MemoryLayout<Int64>.size <= data.count else {
            throw FuzzError.insufficientData
        }
        
        let bytes = data.subdata(in: offset..<offset + MemoryLayout<Int64>.size)
        var value: Int64 = 0
        _ = bytes.withUnsafeBytes { bytesPtr in
            memcpy(&value, bytesPtr.baseAddress!, MemoryLayout<Int64>.size)
        }
        
        offset += MemoryLayout<Int64>.size
        return value
    }
    
    public static var fuzzableSizeHint: Int? { MemoryLayout<Int64>.size }
}

// MARK: - Unsigned Integer Extensions

extension UInt8: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> UInt8 {
        guard offset < data.count else {
            throw FuzzError.insufficientData
        }
        
        let value = data[offset]
        offset += 1
        return value
    }
    
    public static var fuzzableSizeHint: Int? { 1 }
}

extension UInt16: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> UInt16 {
        guard offset + MemoryLayout<UInt16>.size <= data.count else {
            throw FuzzError.insufficientData
        }
        
        let bytes = data.subdata(in: offset..<offset + MemoryLayout<UInt16>.size)
        var value: UInt16 = 0
        _ = bytes.withUnsafeBytes { bytesPtr in
            memcpy(&value, bytesPtr.baseAddress!, MemoryLayout<UInt16>.size)
        }
        
        offset += MemoryLayout<UInt16>.size
        return value
    }
    
    public static var fuzzableSizeHint: Int? { MemoryLayout<UInt16>.size }
}

extension UInt32: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> UInt32 {
        guard offset + MemoryLayout<UInt32>.size <= data.count else {
            throw FuzzError.insufficientData
        }
        
        let bytes = data.subdata(in: offset..<offset + MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        _ = bytes.withUnsafeBytes { bytesPtr in
            memcpy(&value, bytesPtr.baseAddress!, MemoryLayout<UInt32>.size)
        }
        
        offset += MemoryLayout<UInt32>.size
        return value
    }
    
    public static var fuzzableSizeHint: Int? { MemoryLayout<UInt32>.size }
}

extension UInt64: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> UInt64 {
        guard offset + MemoryLayout<UInt64>.size <= data.count else {
            throw FuzzError.insufficientData
        }
        
        let bytes = data.subdata(in: offset..<offset + MemoryLayout<UInt64>.size)
        var value: UInt64 = 0
        _ = bytes.withUnsafeBytes { bytesPtr in
            memcpy(&value, bytesPtr.baseAddress!, MemoryLayout<UInt64>.size)
        }
        
        offset += MemoryLayout<UInt64>.size
        return value
    }
    
    public static var fuzzableSizeHint: Int? { MemoryLayout<UInt64>.size }
}

// MARK: - Floating Point Extensions

extension Float: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> Float {
        guard offset + MemoryLayout<Float>.size <= data.count else {
            throw FuzzError.insufficientData
        }
        
        let bytes = data.subdata(in: offset..<offset + MemoryLayout<Float>.size)
        var value: Float = 0
        _ = bytes.withUnsafeBytes { bytesPtr in
            memcpy(&value, bytesPtr.baseAddress!, MemoryLayout<Float>.size)
        }
        
        offset += MemoryLayout<Float>.size
        
        // Handle special float values for fuzzing safety
        if value.isNaN || value.isInfinite {
            return 0.0
        }
        
        return value
    }
    
    public static var fuzzableSizeHint: Int? { MemoryLayout<Float>.size }
}

extension Double: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> Double {
        guard offset + MemoryLayout<Double>.size <= data.count else {
            throw FuzzError.insufficientData
        }
        
        let bytes = data.subdata(in: offset..<offset + MemoryLayout<Double>.size)
        var value: Double = 0
        _ = bytes.withUnsafeBytes { bytesPtr in
            memcpy(&value, bytesPtr.baseAddress!, MemoryLayout<Double>.size)
        }
        
        offset += MemoryLayout<Double>.size
        
        // Handle special double values for fuzzing safety
        if value.isNaN || value.isInfinite {
            return 0.0
        }
        
        return value
    }
    
    public static var fuzzableSizeHint: Int? { MemoryLayout<Double>.size }
}

// MARK: - Character and Unicode Extensions

extension Character: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> Character {
        guard offset < data.count else {
            throw FuzzError.insufficientData
        }
        
        // Use the full byte range (0-255) directly for maximum fuzzing coverage
        // This includes control characters, extended ASCII, and all edge cases
        let byte = data[offset]
        offset += 1
        
        // Convert byte directly to Unicode.Scalar - covers full Latin-1 range
        // This includes control characters (0-31), printable ASCII (32-126), 
        // and extended ASCII (128-255) which are exactly the interesting edge cases
        let scalar = Unicode.Scalar(byte)
        return Character(scalar)
    }
    
    public static var fuzzableSizeHint: Int? { 1 }
}

extension Unicode.Scalar: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> Unicode.Scalar {
        guard offset + 4 <= data.count else {
            throw FuzzError.insufficientData
        }
        
        // Read 4 bytes to construct a Unicode scalar
        let bytes = data.subdata(in: offset..<offset + 4)
        var rawValue: UInt32 = 0
        _ = bytes.withUnsafeBytes { bytesPtr in
            memcpy(&rawValue, bytesPtr.baseAddress!, 4)
        }
        
        offset += 4
        
        // Ensure the value is a valid Unicode scalar
        // Unicode scalars are 0x0 to 0x10FFFF, excluding surrogate pairs (0xD800-0xDFFF)
        let clampedValue = rawValue % 0x110000 // Limit to valid Unicode range
        
        if let scalar = Unicode.Scalar(clampedValue), !scalar.isSurrogate {
            return scalar
        } else {
            // Fallback to a safe character if invalid
            return Unicode.Scalar(65)! // 'A'
        }
    }
    
    public static var fuzzableSizeHint: Int? { 4 }
}

extension Unicode.Scalar {
    /// Check if this scalar is a surrogate (which are invalid for Unicode.Scalar)
    fileprivate var isSurrogate: Bool {
        return (0xD800...0xDFFF).contains(value)
    }
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

extension Set: Fuzzable where Element: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> Set<Element> {
        guard offset < data.count else {
            throw FuzzError.insufficientData
        }
        
        // Read count byte (0-255) but limit to reasonable size
        let rawCount = Int(data[offset])
        let maxCount = 32 // Reasonable limit to prevent memory issues
        let count = Swift.min(rawCount, maxCount)
        offset += 1
        
        var result: Set<Element> = []
        result.reserveCapacity(count)
        
        for _ in 0..<count {
            guard offset < data.count else {
                break // Not enough data for more elements
            }
            
            do {
                let element = try Element.fuzzableValue(from: data, offset: &offset)
                result.insert(element)
            } catch {
                break // Stop if we can't construct more elements
            }
        }
        
        return result
    }
    
    public static var fuzzableSizeHint: Int? { nil } // Variable size
}

extension Dictionary: Fuzzable where Key: Fuzzable & Hashable, Value: Fuzzable {
    public static func fuzzableValue(from data: Data, offset: inout Int) throws -> [Key: Value] {
        guard offset < data.count else {
            throw FuzzError.insufficientData
        }
        
        // Read count byte (0-255) but limit to reasonable size
        let rawCount = Int(data[offset])
        let maxCount = 32 // Reasonable limit to prevent memory issues
        let count = Swift.min(rawCount, maxCount)
        offset += 1
        
        var result: [Key: Value] = [:]
        result.reserveCapacity(count)
        
        for _ in 0..<count {
            guard offset < data.count else {
                break // Not enough data for more elements
            }
            
            do {
                let key = try Key.fuzzableValue(from: data, offset: &offset)
                let value = try Value.fuzzableValue(from: data, offset: &offset)
                result[key] = value
            } catch {
                break // Stop if we can't construct more key-value pairs
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