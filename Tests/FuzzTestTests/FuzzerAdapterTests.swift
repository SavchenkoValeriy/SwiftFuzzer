import XCTest
import Foundation
@testable import FuzzTest

final class FuzzerAdapterTests: XCTestCase {
    
    func testAdapterWithSingleParameter() throws {
        var capturedString: String?
        
        let adapter = FuzzerAdapter { (text: String) in
            capturedString = text
        }
        
        // Create test data with a string
        var data = Data()
        data.append(5) // String length
        data.append("Hello".data(using: .utf8)!)
        
        try adapter.function(data)
        
        XCTAssertEqual(capturedString, "Hello")
    }
    
    func testAdapterWithMultipleParameters() throws {
        var capturedString: String?
        var capturedInt: Int?
        var capturedBool: Bool?
        
        let adapter = FuzzerAdapter { (text: String, number: Int, flag: Bool) in
            capturedString = text
            capturedInt = number
            capturedBool = flag
        }
        
        // Create test data
        var data = Data()
        
        // String: length + content
        data.append(3) // String length
        data.append("Hi!".data(using: .utf8)!)
        
        // Int: 8 bytes
        let intValue: Int = 42
        withUnsafeBytes(of: intValue) { bytes in
            data.append(contentsOf: bytes)
        }
        
        // Bool: 1 byte (odd = true)
        data.append(1) // Odd = true
        
        try adapter.function(data)
        
        XCTAssertEqual(capturedString, "Hi!")
        XCTAssertEqual(capturedInt, 42)
        XCTAssertEqual(capturedBool, true)
    }
    
    func testAdapterWithDataParameter() throws {
        var capturedData: Data?
        
        let adapter = FuzzerAdapter { (data: Data) in
            capturedData = data
        }
        
        let testData = Data([1, 2, 3, 4, 5])
        try adapter.function(testData)
        
        XCTAssertEqual(capturedData, testData)
    }
    
    func testAdapterSafeExecuteHandlesErrors() {
        let adapter = FuzzerAdapter { (text: String) in
            throw NSError(domain: "test", code: 1, userInfo: nil)
        }
        
        let data = Data([5, 72, 101, 108, 108, 111]) // "Hello"
        
        // Should not crash even when function throws
        adapter.safeExecute(with: data)
    }
    
    func testAdapterWithInsufficientData() {
        var functionCalled = false
        
        let adapter = FuzzerAdapter { (text: String, number: Int) in
            functionCalled = true
        }
        
        // Only provide data for string, not for int
        let data = Data([5, 72, 101, 108, 108, 111]) // Just "Hello", no int data
        
        adapter.safeExecute(with: data)
        
        // Function should not be called due to insufficient data
        XCTAssertFalse(functionCalled)
    }
    
    func testAdapterCreation() {
        // Test that we can create adapters without issues
        let dataAdapter = FuzzerAdapter { (data: Data) in }
        XCTAssertNotNil(dataAdapter.function)
        
        let variadicAdapter = FuzzerAdapter { (text: String, number: Int) in }
        XCTAssertNotNil(variadicAdapter.function)
    }
}