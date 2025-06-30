import XCTest
import Foundation
@testable import FuzzTest

final class FuzzableTests: XCTestCase {
    
    // MARK: - String Tests
    
    func testStringFuzzableBasic() throws {
        // Test basic string construction
        var data = Data([5]) // Length = 5
        data.append("Hello".data(using: .utf8)!)
        
        var offset = 0
        let result = try String.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, "Hello")
        XCTAssertEqual(offset, 6) // 1 byte length + 5 bytes content
    }
    
    func testStringFuzzableEmpty() throws {
        let data = Data([0]) // Length = 0
        
        var offset = 0
        let result = try String.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, "")
        XCTAssertEqual(offset, 1) // 1 byte length only
    }
    
    func testStringFuzzableTruncated() throws {
        // Request 10 bytes but only provide 3
        var data = Data([10]) // Length = 10
        data.append("Hi!".data(using: .utf8)!)
        
        var offset = 0
        let result = try String.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, "Hi!") // Should truncate to available data
        XCTAssertEqual(offset, 4) // 1 byte length + 3 bytes content
    }
    
    func testStringFuzzableInvalidUTF8() throws {
        var data = Data([3]) // Length = 3
        data.append(Data([0xFF, 0xFE, 0xFD])) // Invalid UTF-8
        
        var offset = 0
        let result = try String.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, "") // Should return empty string for invalid UTF-8
        XCTAssertEqual(offset, 4)
    }
    
    func testStringFuzzableInsufficientData() {
        let data = Data() // Empty data
        
        var offset = 0
        XCTAssertThrowsError(try String.fuzzableValue(from: data, offset: &offset)) { error in
            XCTAssertEqual(error as? FuzzError, FuzzError.insufficientData)
        }
    }
    
    func testStringFuzzableSizeHint() {
        XCTAssertNil(String.fuzzableSizeHint)
    }
    
    // MARK: - Bool Tests
    
    func testBoolFuzzableTrue() throws {
        let data = Data([1]) // Odd = true
        
        var offset = 0
        let result = try Bool.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertTrue(result)
        XCTAssertEqual(offset, 1)
    }
    
    func testBoolFuzzableFalse() throws {
        let data = Data([0]) // Even = false
        
        var offset = 0
        let result = try Bool.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertFalse(result)
        XCTAssertEqual(offset, 1)
    }
    
    func testBoolFuzzableOddValues() throws {
        for byte: UInt8 in [3, 5, 7, 9, 255] {
            let data = Data([byte])
            var offset = 0
            let result = try Bool.fuzzableValue(from: data, offset: &offset)
            XCTAssertTrue(result, "Byte \(byte) should produce true")
        }
    }
    
    func testBoolFuzzableEvenValues() throws {
        for byte: UInt8 in [2, 4, 6, 8, 254] {
            let data = Data([byte])
            var offset = 0
            let result = try Bool.fuzzableValue(from: data, offset: &offset)
            XCTAssertFalse(result, "Byte \(byte) should produce false")
        }
    }
    
    func testBoolFuzzableInsufficientData() {
        let data = Data()
        
        var offset = 0
        XCTAssertThrowsError(try Bool.fuzzableValue(from: data, offset: &offset)) { error in
            XCTAssertEqual(error as? FuzzError, FuzzError.insufficientData)
        }
    }
    
    func testBoolFuzzableSizeHint() {
        XCTAssertEqual(Bool.fuzzableSizeHint, 1)
    }
    
    // MARK: - Int Tests
    
    func testIntFuzzableBasic() throws {
        let value: Int = 1234567890
        var data = Data()
        withUnsafeBytes(of: value) { bytes in
            data.append(contentsOf: bytes)
        }
        
        var offset = 0
        let result = try Int.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, value)
        XCTAssertEqual(offset, MemoryLayout<Int>.size)
    }
    
    func testIntFuzzableZero() throws {
        let value: Int = 0
        var data = Data()
        withUnsafeBytes(of: value) { bytes in
            data.append(contentsOf: bytes)
        }
        
        var offset = 0
        let result = try Int.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, 0)
        XCTAssertEqual(offset, MemoryLayout<Int>.size)
    }
    
    func testIntFuzzableNegative() throws {
        let value: Int = -987654321
        var data = Data()
        withUnsafeBytes(of: value) { bytes in
            data.append(contentsOf: bytes)
        }
        
        var offset = 0
        let result = try Int.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, value)
        XCTAssertEqual(offset, MemoryLayout<Int>.size)
    }
    
    func testIntFuzzableInsufficientData() {
        let data = Data([1, 2, 3]) // Only 3 bytes, need 8
        
        var offset = 0
        XCTAssertThrowsError(try Int.fuzzableValue(from: data, offset: &offset)) { error in
            XCTAssertEqual(error as? FuzzError, FuzzError.insufficientData)
        }
    }
    
    func testIntFuzzableSizeHint() {
        XCTAssertEqual(Int.fuzzableSizeHint, MemoryLayout<Int>.size)
    }
    
    // MARK: - Array Tests
    
    func testArrayFuzzableBasic() throws {
        // Array of 3 bools: [true, false, true]
        let data = Data([3, 1, 0, 1]) // Count=3, then bool values
        
        var offset = 0
        let result = try Array<Bool>.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, [true, false, true])
        XCTAssertEqual(offset, 4)
    }
    
    func testArrayFuzzableEmpty() throws {
        let data = Data([0]) // Count=0
        
        var offset = 0
        let result = try Array<Bool>.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, [])
        XCTAssertEqual(offset, 1)
    }
    
    func testArrayFuzzableSizeLimit() throws {
        // Request 100 elements but we limit to 32
        let data = Data([100, 1, 1, 1, 1, 1]) // Count=100, but only 5 bool values available
        
        var offset = 0
        let result = try Array<Bool>.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result.count, 5) // Should stop when data runs out
        XCTAssertEqual(result, [true, true, true, true, true])
    }
    
    func testArrayFuzzablePartialData() throws {
        // Request 5 elements but only have data for 2
        let data = Data([5, 1, 0]) // Count=5, but only 2 bool values
        
        var offset = 0
        let result = try Array<Bool>.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, [true, false]) // Should truncate gracefully
        XCTAssertEqual(offset, 3)
    }
    
    func testArrayFuzzableInsufficientData() {
        let data = Data() // No data at all
        
        var offset = 0
        XCTAssertThrowsError(try Array<Bool>.fuzzableValue(from: data, offset: &offset)) { error in
            XCTAssertEqual(error as? FuzzError, FuzzError.insufficientData)
        }
    }
    
    func testArrayFuzzableSizeHint() {
        XCTAssertNil(Array<Bool>.fuzzableSizeHint)
    }
    
    // MARK: - Optional Tests
    
    func testOptionalFuzzableSome() throws {
        let data = Data([1, 42]) // HasValue=true, then Bool value (42 is even, so false)
        
        var offset = 0
        let result = try Optional<Bool>.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, false) // 42 & 1 == 0, so false
        XCTAssertEqual(offset, 2)
    }
    
    func testOptionalFuzzableNone() throws {
        let data = Data([0]) // HasValue=false
        
        var offset = 0
        let result = try Optional<Bool>.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertNil(result)
        XCTAssertEqual(offset, 1)
    }
    
    func testOptionalFuzzableWithOddFlag() throws {
        let data = Data([3, 1]) // HasValue=true (3 is odd), then Bool value
        
        var offset = 0
        let result = try Optional<Bool>.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, true)
        XCTAssertEqual(offset, 2)
    }
    
    func testOptionalFuzzableInsufficientData() {
        let data = Data() // No data
        
        var offset = 0
        XCTAssertThrowsError(try Optional<Bool>.fuzzableValue(from: data, offset: &offset)) { error in
            XCTAssertEqual(error as? FuzzError, FuzzError.insufficientData)
        }
    }
    
    func testOptionalFuzzableSizeHint() {
        XCTAssertNil(Optional<Bool>.fuzzableSizeHint)
    }
    
    // MARK: - Complex Integration Tests
    
    func testComplexNested() throws {
        // Array of optional strings: [Some("Hi"), None, Some("Bye")]
        var data = Data()
        data.append(3) // Array count = 3
        
        // First element: Some("Hi")
        data.append(1) // HasValue = true
        data.append(2) // String length = 2
        data.append("Hi".data(using: .utf8)!)
        
        // Second element: None
        data.append(0) // HasValue = false
        
        // Third element: Some("Bye")
        data.append(1) // HasValue = true
        data.append(3) // String length = 3
        data.append("Bye".data(using: .utf8)!)
        
        var offset = 0
        let result = try Array<Optional<String>>.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0], "Hi")
        XCTAssertNil(result[1])
        XCTAssertEqual(result[2], "Bye")
    }
    
    func testOffsetProgression() throws {
        // Test that offset is correctly updated through multiple operations
        var data = Data()
        
        // Bool: 1 byte
        data.append(1)
        
        // Int: 8 bytes
        let intValue: Int = 12345
        withUnsafeBytes(of: intValue) { bytes in
            data.append(contentsOf: bytes)
        }
        
        // String: 1 + 4 bytes
        data.append(4)
        data.append("Test".data(using: .utf8)!)
        
        var offset = 0
        
        let boolResult = try Bool.fuzzableValue(from: data, offset: &offset)
        XCTAssertTrue(boolResult)
        XCTAssertEqual(offset, 1)
        
        let intResult = try Int.fuzzableValue(from: data, offset: &offset)
        XCTAssertEqual(intResult, 12345)
        XCTAssertEqual(offset, 1 + MemoryLayout<Int>.size)
        
        let stringResult = try String.fuzzableValue(from: data, offset: &offset)
        XCTAssertEqual(stringResult, "Test")
        XCTAssertEqual(offset, 1 + MemoryLayout<Int>.size + 1 + 4)
    }
    
    // MARK: - Signed Integer Tests
    
    func testInt8Fuzzable() throws {
        let values: [Int8] = [-128, -1, 0, 1, 127]
        
        for value in values {
            let data = Data([UInt8(bitPattern: value)])
            var offset = 0
            let result = try Int8.fuzzableValue(from: data, offset: &offset)
            
            XCTAssertEqual(result, value)
            XCTAssertEqual(offset, 1)
        }
    }
    
    func testInt16Fuzzable() throws {
        let value: Int16 = -12345
        var data = Data()
        withUnsafeBytes(of: value) { bytes in
            data.append(contentsOf: bytes)
        }
        
        var offset = 0
        let result = try Int16.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, value)
        XCTAssertEqual(offset, MemoryLayout<Int16>.size)
    }
    
    func testInt32Fuzzable() throws {
        let value: Int32 = -1234567890
        var data = Data()
        withUnsafeBytes(of: value) { bytes in
            data.append(contentsOf: bytes)
        }
        
        var offset = 0
        let result = try Int32.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, value)
        XCTAssertEqual(offset, MemoryLayout<Int32>.size)
    }
    
    func testInt64Fuzzable() throws {
        let value: Int64 = -9223372036854775807
        var data = Data()
        withUnsafeBytes(of: value) { bytes in
            data.append(contentsOf: bytes)
        }
        
        var offset = 0
        let result = try Int64.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, value)
        XCTAssertEqual(offset, MemoryLayout<Int64>.size)
    }
    
    // MARK: - Unsigned Integer Tests
    
    func testUInt8Fuzzable() throws {
        let values: [UInt8] = [0, 1, 127, 255]
        
        for value in values {
            let data = Data([value])
            var offset = 0
            let result = try UInt8.fuzzableValue(from: data, offset: &offset)
            
            XCTAssertEqual(result, value)
            XCTAssertEqual(offset, 1)
        }
    }
    
    func testUInt16Fuzzable() throws {
        let value: UInt16 = 65535
        var data = Data()
        withUnsafeBytes(of: value) { bytes in
            data.append(contentsOf: bytes)
        }
        
        var offset = 0
        let result = try UInt16.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, value)
        XCTAssertEqual(offset, MemoryLayout<UInt16>.size)
    }
    
    func testUInt32Fuzzable() throws {
        let value: UInt32 = 4294967295
        var data = Data()
        withUnsafeBytes(of: value) { bytes in
            data.append(contentsOf: bytes)
        }
        
        var offset = 0
        let result = try UInt32.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, value)
        XCTAssertEqual(offset, MemoryLayout<UInt32>.size)
    }
    
    func testUInt64Fuzzable() throws {
        let value: UInt64 = 18446744073709551615
        var data = Data()
        withUnsafeBytes(of: value) { bytes in
            data.append(contentsOf: bytes)
        }
        
        var offset = 0
        let result = try UInt64.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, value)
        XCTAssertEqual(offset, MemoryLayout<UInt64>.size)
    }
    
    // MARK: - Floating Point Tests
    
    func testFloatFuzzable() throws {
        let value: Float = 3.14159
        var data = Data()
        withUnsafeBytes(of: value) { bytes in
            data.append(contentsOf: bytes)
        }
        
        var offset = 0
        let result = try Float.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, value, accuracy: 0.00001)
        XCTAssertEqual(offset, MemoryLayout<Float>.size)
    }
    
    func testFloatFuzzableSpecialValues() throws {
        // Test NaN handling
        let nanValue: Float = Float.nan
        var data = Data()
        withUnsafeBytes(of: nanValue) { bytes in
            data.append(contentsOf: bytes)
        }
        
        var offset = 0
        let result = try Float.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, 0.0) // NaN should be converted to 0.0
        
        // Test infinity handling
        offset = 0
        let infValue: Float = Float.infinity
        data = Data()
        withUnsafeBytes(of: infValue) { bytes in
            data.append(contentsOf: bytes)
        }
        
        let infResult = try Float.fuzzableValue(from: data, offset: &offset)
        XCTAssertEqual(infResult, 0.0) // Infinity should be converted to 0.0
    }
    
    func testDoubleFuzzable() throws {
        let value: Double = 2.718281828459045
        var data = Data()
        withUnsafeBytes(of: value) { bytes in
            data.append(contentsOf: bytes)
        }
        
        var offset = 0
        let result = try Double.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, value, accuracy: 0.0000000000001)
        XCTAssertEqual(offset, MemoryLayout<Double>.size)
    }
    
    func testDoubleFuzzableSpecialValues() throws {
        // Test NaN handling
        let nanValue: Double = Double.nan
        var data = Data()
        withUnsafeBytes(of: nanValue) { bytes in
            data.append(contentsOf: bytes)
        }
        
        var offset = 0
        let result = try Double.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, 0.0) // NaN should be converted to 0.0
    }
    
    // MARK: - Character Tests
    
    func testCharacterFuzzable() throws {
        // Test direct byte-to-character mapping: byte -> Character(Unicode.Scalar(byte))
        let testCases: [(UInt8, Character)] = [
            (0, Character(Unicode.Scalar(0))),    // NULL control character
            (9, Character(Unicode.Scalar(9))),    // TAB control character
            (10, Character(Unicode.Scalar(10))),  // LF newline control character
            (32, " "),                            // Space
            (65, "A"),                            // Letter A
            (126, "~"),                           // Tilde
            (127, Character(Unicode.Scalar(127))), // DEL control character
            (128, Character(Unicode.Scalar(128))), // Extended ASCII
            (255, Character(Unicode.Scalar(255)))  // Extended ASCII
        ]
        
        for (byte, expectedChar) in testCases {
            let data = Data([byte])
            var offset = 0
            let result = try Character.fuzzableValue(from: data, offset: &offset)
            
            XCTAssertEqual(result, expectedChar, "Byte \(byte) should map directly to Character(Unicode.Scalar(\(byte)))")
            XCTAssertEqual(offset, 1)
        }
    }
    
    func testCharacterFuzzableMapping() throws {
        // Test that all bytes map correctly to the full Latin-1 range (0-255)
        for byte: UInt8 in 0...255 {
            let data = Data([byte])
            var offset = 0
            let result = try Character.fuzzableValue(from: data, offset: &offset)
            
            // Result should be Character(Unicode.Scalar(byte))
            let scalar = result.unicodeScalars.first!
            XCTAssertEqual(scalar.value, UInt32(byte), "Byte \(byte) should map directly to Unicode scalar \(byte)")
            XCTAssertEqual(offset, 1)
        }
    }
    
    // MARK: - Unicode.Scalar Tests
    
    func testUnicodeScalarFuzzable() throws {
        let value: UInt32 = 65 // 'A'
        var data = Data()
        withUnsafeBytes(of: value) { bytes in
            data.append(contentsOf: bytes)
        }
        
        var offset = 0
        let result = try Unicode.Scalar.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, Unicode.Scalar(65)!) // 'A'
        XCTAssertEqual(offset, 4)
    }
    
    func testUnicodeScalarFuzzableInvalidValues() throws {
        // Test surrogate range (should fallback to 'A')
        let surrogateValue: UInt32 = 0xD800
        var data = Data()
        withUnsafeBytes(of: surrogateValue) { bytes in
            data.append(contentsOf: bytes)
        }
        
        var offset = 0
        let result = try Unicode.Scalar.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result, Unicode.Scalar(65)!) // Should fallback to 'A'
        XCTAssertEqual(offset, 4)
    }
    
    func testUnicodeScalarFuzzableHighValues() throws {
        // Test values that would exceed Unicode range (should be clamped)
        let highValue: UInt32 = 0xFFFFFFFF
        var data = Data()
        withUnsafeBytes(of: highValue) { bytes in
            data.append(contentsOf: bytes)
        }
        
        var offset = 0
        let result = try Unicode.Scalar.fuzzableValue(from: data, offset: &offset)
        
        // Should produce some valid Unicode scalar (clamped to 0x10FFFF range)
        XCTAssertNotNil(result)
        XCTAssertEqual(offset, 4)
    }
    
    // MARK: - Set Tests
    
    func testSetFuzzable() throws {
        // Set of 3 integers
        var data = Data([3]) // Count = 3
        
        // Add three different Int8 values
        let values: [Int8] = [1, 2, 3]
        for value in values {
            data.append(UInt8(bitPattern: value))
        }
        
        var offset = 0
        let result = try Set<Int8>.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.contains(1))
        XCTAssertTrue(result.contains(2))
        XCTAssertTrue(result.contains(3))
        XCTAssertEqual(offset, 4)
    }
    
    func testSetFuzzableDuplicates() throws {
        // Set with duplicate values should deduplicate
        var data = Data([3]) // Count = 3
        
        // Add same value three times
        for _ in 0..<3 {
            data.append(42) // Same Int8 value
        }
        
        var offset = 0
        let result = try Set<Int8>.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result.count, 1) // Should have only one unique element
        XCTAssertTrue(result.contains(42))
        XCTAssertEqual(offset, 4)
    }
    
    func testSetFuzzableEmpty() throws {
        let data = Data([0]) // Count = 0
        
        var offset = 0
        let result = try Set<Int8>.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(offset, 1)
    }
    
    // MARK: - Dictionary Tests
    
    func testDictionaryFuzzable() throws {
        // Dictionary with 2 key-value pairs
        var data = Data([2]) // Count = 2
        
        // First pair: key=1, value=10
        data.append(1) // Int8 key
        data.append(10) // Int8 value
        
        // Second pair: key=2, value=20
        data.append(2) // Int8 key
        data.append(20) // Int8 value
        
        var offset = 0
        let result = try Dictionary<Int8, Int8>.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[1], 10)
        XCTAssertEqual(result[2], 20)
        XCTAssertEqual(offset, 5)
    }
    
    func testDictionaryFuzzableDuplicateKeys() throws {
        // Dictionary with duplicate keys (later value should win)
        var data = Data([2]) // Count = 2
        
        // First pair: key=1, value=10
        data.append(1) // Int8 key
        data.append(10) // Int8 value
        
        // Second pair: key=1, value=20 (same key, different value)
        data.append(1) // Int8 key (duplicate)
        data.append(20) // Int8 value
        
        var offset = 0
        let result = try Dictionary<Int8, Int8>.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertEqual(result.count, 1) // Only one key should remain
        XCTAssertEqual(result[1], 20) // Later value should win
        XCTAssertEqual(offset, 5)
    }
    
    func testDictionaryFuzzableEmpty() throws {
        let data = Data([0]) // Count = 0
        
        var offset = 0
        let result = try Dictionary<Int8, Int8>.fuzzableValue(from: data, offset: &offset)
        
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(offset, 1)
    }
    
    // MARK: - Size Hint Tests
    
    func testSizeHints() {
        // Test that all fixed-size types return correct size hints
        XCTAssertEqual(Int8.fuzzableSizeHint, 1)
        XCTAssertEqual(Int16.fuzzableSizeHint, 2)
        XCTAssertEqual(Int32.fuzzableSizeHint, 4)
        XCTAssertEqual(Int64.fuzzableSizeHint, 8)
        XCTAssertEqual(UInt8.fuzzableSizeHint, 1)
        XCTAssertEqual(UInt16.fuzzableSizeHint, 2)
        XCTAssertEqual(UInt32.fuzzableSizeHint, 4)
        XCTAssertEqual(UInt64.fuzzableSizeHint, 8)
        XCTAssertEqual(Float.fuzzableSizeHint, 4)
        XCTAssertEqual(Double.fuzzableSizeHint, 8)
        XCTAssertEqual(Character.fuzzableSizeHint, 1)
        XCTAssertEqual(Unicode.Scalar.fuzzableSizeHint, 4)
        
        // Test that variable-size types return nil
        XCTAssertNil(String.fuzzableSizeHint)
        XCTAssertNil(Array<Int>.fuzzableSizeHint)
        XCTAssertNil(Set<Int>.fuzzableSizeHint)
        XCTAssertNil(Dictionary<Int, Int>.fuzzableSizeHint)
        XCTAssertNil(Optional<Int>.fuzzableSizeHint)
    }
    
    // MARK: - Insufficient Data Tests
    
    func testInsufficientDataForAllTypes() {
        let emptyData = Data()
        var offset = 0
        
        // Test all numeric types
        XCTAssertThrowsError(try Int8.fuzzableValue(from: emptyData, offset: &offset))
        XCTAssertThrowsError(try Int16.fuzzableValue(from: emptyData, offset: &offset))
        XCTAssertThrowsError(try Int32.fuzzableValue(from: emptyData, offset: &offset))
        XCTAssertThrowsError(try Int64.fuzzableValue(from: emptyData, offset: &offset))
        XCTAssertThrowsError(try UInt8.fuzzableValue(from: emptyData, offset: &offset))
        XCTAssertThrowsError(try UInt16.fuzzableValue(from: emptyData, offset: &offset))
        XCTAssertThrowsError(try UInt32.fuzzableValue(from: emptyData, offset: &offset))
        XCTAssertThrowsError(try UInt64.fuzzableValue(from: emptyData, offset: &offset))
        XCTAssertThrowsError(try Float.fuzzableValue(from: emptyData, offset: &offset))
        XCTAssertThrowsError(try Double.fuzzableValue(from: emptyData, offset: &offset))
        XCTAssertThrowsError(try Character.fuzzableValue(from: emptyData, offset: &offset))
        XCTAssertThrowsError(try Unicode.Scalar.fuzzableValue(from: emptyData, offset: &offset))
        
        // Test collection types
        XCTAssertThrowsError(try Set<Int8>.fuzzableValue(from: emptyData, offset: &offset))
        XCTAssertThrowsError(try Dictionary<Int8, Int8>.fuzzableValue(from: emptyData, offset: &offset))
    }
}