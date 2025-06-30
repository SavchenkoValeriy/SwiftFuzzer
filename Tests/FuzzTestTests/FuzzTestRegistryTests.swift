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
        XCTAssertTrue(functions.contains { $0.0 == "testFunction" })
        
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
}