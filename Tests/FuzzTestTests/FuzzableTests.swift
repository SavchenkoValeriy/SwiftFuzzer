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
}