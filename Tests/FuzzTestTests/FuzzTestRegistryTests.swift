import XCTest
import Foundation
@testable import FuzzTest

final class FuzzTestRegistryTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Reset the registry before each test
        FuzzTestRegistry._resetForTesting()
    }
    
    override func tearDown() {
        // Reset the registry after each test to avoid interference
        FuzzTestRegistry._resetForTesting()
        super.tearDown()
    }
    
    func testRegistryRegistersFunction() {
        // Given
        let testData = Data([1, 2, 3, 4])
        var called = false
        
        let testFunction: (Data) -> Bool = { data in
            called = true
            XCTAssertEqual(Array(data), Array(testData))
            return true
        }
        
        // When
        FuzzTestRegistry.register(name: "testFunction", function: testFunction)
        
        // Then
        let functions = FuzzTestRegistry.getAllFunctions()
        XCTAssertTrue(functions.contains { $0.0 == "testFunction(Data)" })
        
        // Test that the function can be executed
        FuzzTestRegistry.run(named: "testFunction", with: testData)
        XCTAssertTrue(called)
    }
    
    func testRegistryRunsAllFunctions() {
        // Given
        let testData = Data([5, 6, 7, 8])
        var firstCalled = false
        var secondCalled = false
        
        let firstFunction: (Data) -> Void = { data in
            firstCalled = true
            XCTAssertEqual(Array(data), [5, 6, 7, 8])
        }
        
        let secondFunction: (Data) -> String = { data in
            secondCalled = true
            XCTAssertEqual(Array(data), [5, 6, 7, 8])
            return "test"
        }
        
        // When
        FuzzTestRegistry.register(name: "firstFunction", function: firstFunction)
        FuzzTestRegistry.register(name: "secondFunction", function: secondFunction)
        
        FuzzTestRegistry.runAll(with: testData)
        
        // Then
        XCTAssertTrue(firstCalled)
        XCTAssertTrue(secondCalled)
    }
    
    func testRegistryRunsSpecificFunction() {
        // Given
        let testData = Data([9, 10, 11, 12])
        var targetCalled = false
        var otherCalled = false
        
        let targetFunction: (Data) -> Void = { _ in
            targetCalled = true
        }
        
        let otherFunction: (Data) -> Void = { _ in
            otherCalled = true
        }
        
        // When
        FuzzTestRegistry.register(name: "targetFunction", function: targetFunction)
        FuzzTestRegistry.register(name: "otherFunction", function: otherFunction)
        
        FuzzTestRegistry.run(named: "targetFunction", with: testData)
        
        // Then
        XCTAssertTrue(targetCalled)
        XCTAssertFalse(otherCalled)
    }
    
    func testRegistryIgnoresNonExistentFunction() {
        // Given
        let testData = Data([13, 14, 15, 16])
        
        // When/Then - should not crash or throw
        FuzzTestRegistry.run(named: "nonExistentFunction", with: testData)
    }
    
    func testRegistryHandlesDifferentReturnTypes() {
        // Given
        let testData = Data([17, 18, 19, 20])
        
        let voidFunction: (Data) -> Void = { _ in }
        let intFunction: (Data) -> Int = { _ in 42 }
        let stringFunction: (Data) -> String = { _ in "hello" }
        let boolFunction: (Data) -> Bool = { _ in true }
        
        // When - should not crash
        FuzzTestRegistry.register(name: "voidFunction", function: voidFunction)
        FuzzTestRegistry.register(name: "intFunction", function: intFunction)
        FuzzTestRegistry.register(name: "stringFunction", function: stringFunction)
        FuzzTestRegistry.register(name: "boolFunction", function: boolFunction)
        
        // Then - should be able to run all without issues
        FuzzTestRegistry.runAll(with: testData)
        
        let functions = FuzzTestRegistry.getAllFunctions()
        XCTAssertTrue(functions.count >= 4) // At least the ones we registered
    }
    
    func testRegistryInitializeIsIdempotent() {
        // Given/When - call initialize multiple times
        FuzzTestRegistry.initialize()
        FuzzTestRegistry.initialize()
        FuzzTestRegistry.initialize()
        
        // Then - should not crash or cause issues
        // This is mainly a smoke test since we can't easily test the internal state
    }
    
    // MARK: - Hash-based dispatch tests
    
    func testHashBasedDispatch() {
        // Given - register functions with different signatures
        var function1Called = false
        var function2Called = false
        
        let function1: (Data) -> Void = { data in
            function1Called = true
            XCTAssertEqual(Array(data), [5, 6, 7, 8]) // Should receive data after selector
        }
        
        let function2: (Data) -> Void = { data in
            function2Called = true
            XCTAssertEqual(Array(data), [5, 6, 7, 8]) // Should receive data after selector
        }
        
        FuzzTestRegistry.register(fqn: "function1(Data)", adapter: FuzzerAdapter(function1))
        FuzzTestRegistry.register(fqn: "function2(String)", adapter: FuzzerAdapter(function2))
        
        // Get hash mappings to understand the dispatch
        let mappings = FuzzTestRegistry.getHashMappings()
        XCTAssertEqual(mappings.count, 2)
        
        // When - create data with specific selector (first 4 bytes) + function data
        let hash1 = mappings[0].0
        var testData = Data()
        withUnsafeBytes(of: hash1) { bytes in
            testData.append(contentsOf: bytes)
        }
        testData.append(contentsOf: [5, 6, 7, 8])
        
        FuzzTestRegistry.runSelected(with: testData)
        
        // Then - only the selected function should be called
        XCTAssertTrue(function1Called || function2Called) // One should be called
        XCTAssertFalse(function1Called && function2Called) // Not both
    }
    
    func testHashBasedDispatchWithGracefulDegradation() {
        // Given - register one function
        var functionCalled = false
        
        let testFunction: (Data) -> Void = { data in
            functionCalled = true
        }
        
        FuzzTestRegistry.register(name: "testFunction", adapter: FuzzerAdapter(testFunction))
        
        // When - use a selector that doesn't match any function hash
        let randomSelector: UInt32 = 0xDEADBEEF
        var testData = Data()
        withUnsafeBytes(of: randomSelector) { bytes in
            testData.append(contentsOf: bytes)
        }
        testData.append(contentsOf: [1, 2, 3, 4])
        
        FuzzTestRegistry.runSelected(with: testData)
        
        // Then - should gracefully degrade to nearest function
        XCTAssertTrue(functionCalled)
    }
    
    func testHashBasedDispatchWithInsufficientData() {
        // Given - register a function
        var functionCalled = false
        
        let testFunction: (Data) -> Void = { _ in
            functionCalled = true
        }
        
        FuzzTestRegistry.register(name: "testFunction", adapter: FuzzerAdapter(testFunction))
        
        // When - provide insufficient data (less than 4 bytes for selector)
        let testData = Data([1, 2, 3]) // Only 3 bytes
        
        FuzzTestRegistry.runSelected(with: testData)
        
        // Then - should not call any function
        XCTAssertFalse(functionCalled)
    }
    
    func testHashStability() {
        // Given - register functions with same FQN multiple times
        FuzzTestRegistry.register(fqn: "stableFunction(String,Int)", adapter: FuzzerAdapter { _ in })
        let mappings1 = FuzzTestRegistry.getHashMappings()
        
        FuzzTestRegistry._resetForTesting()
        
        FuzzTestRegistry.register(fqn: "stableFunction(String,Int)", adapter: FuzzerAdapter { _ in })
        let mappings2 = FuzzTestRegistry.getHashMappings()
        
        // Then - hash should be stable across registry resets
        XCTAssertEqual(mappings1.count, 1)
        XCTAssertEqual(mappings2.count, 1)
        XCTAssertEqual(mappings1[0].0, mappings2[0].0) // Same hash
        XCTAssertEqual(mappings1[0].1, mappings2[0].1) // Same FQN
    }
    
    func testFunctionCount() {
        // Given
        XCTAssertEqual(FuzzTestRegistry.getFunctionCount(), 0)
        
        // When
        FuzzTestRegistry.register(fqn: "func1(Data)", adapter: FuzzerAdapter { _ in })
        FuzzTestRegistry.register(fqn: "func2(Data)", adapter: FuzzerAdapter { _ in })
        
        // Then
        XCTAssertEqual(FuzzTestRegistry.getFunctionCount(), 2)
    }
    
    func testSwiftParameterLabelsInFQN() {
        // Given - functions with same parameter types but different labels
        var process1Called = false
        var process2Called = false
        
        let processFunction1: (Data) -> Void = { _ in process1Called = true }
        let processFunction2: (Data) -> Void = { _ in process2Called = true }
        
        // These functions would have signatures like:
        // func process(data: String, count: Int)    -> "process(data:count:)"  
        // func process(text: String, limit: Int)    -> "process(text:limit:)"
        // Even though both take (String,Int), they should have different FQNs due to parameter labels
        
        let fqn1 = "process(data:count:)"
        let fqn2 = "process(text:limit:)"
        
        // When
        FuzzTestRegistry.register(fqn: fqn1, adapter: FuzzerAdapter(processFunction1))
        FuzzTestRegistry.register(fqn: fqn2, adapter: FuzzerAdapter(processFunction2))
        
        // Then - both functions should be registered with different hashes
        let mappings = FuzzTestRegistry.getHashMappings()
        XCTAssertEqual(mappings.count, 2)
        
        let hash1 = mappings.first { $0.1 == fqn1 }?.0
        let hash2 = mappings.first { $0.1 == fqn2 }?.0
        
        XCTAssertNotNil(hash1)
        XCTAssertNotNil(hash2) 
        XCTAssertNotEqual(hash1, hash2, "Functions with same parameter types but different labels should have different hashes")
        
        // Verify that each function can be selected independently
        var testData1 = Data()
        withUnsafeBytes(of: hash1!) { bytes in
            testData1.append(contentsOf: bytes)
        }
        testData1.append(contentsOf: [1, 2, 3])
        
        var testData2 = Data()
        withUnsafeBytes(of: hash2!) { bytes in
            testData2.append(contentsOf: bytes)
        }
        testData2.append(contentsOf: [4, 5, 6])
        
        FuzzTestRegistry.runSelected(with: testData1)
        FuzzTestRegistry.runSelected(with: testData2)
        
        XCTAssertTrue(process1Called)
        XCTAssertTrue(process2Called)
    }
}