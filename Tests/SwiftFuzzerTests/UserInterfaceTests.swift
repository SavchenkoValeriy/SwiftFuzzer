// Tests/SwiftFuzzerTests/UserInterfaceTests.swift
import XCTest
import Foundation
@testable import SwiftFuzzerLib

final class UserInterfaceTests: XCTestCase {
    
    func testProgressIndicators() {
        // Test that progress indicators don't crash and produce expected output
        UserInterface.showPhaseStart(.setup)
        UserInterface.showStep("Test step")
        UserInterface.showStep("Sub step", isSubStep: true)
        UserInterface.showSuccess("Test success")
        UserInterface.showProgress(3, 5, "Testing progress")
    }
    
    func testUserFriendlyErrors() {
        // Test error creation and formatting
        let availableTargets = ["LibraryTarget", "TestTarget"]
        let targetNotFoundError = UserFriendlyError.targetNotFound("WrongTarget", availableTargets: availableTargets)
        
        XCTAssertEqual(targetNotFoundError.title, "Target 'WrongTarget' not found")
        XCTAssertTrue(targetNotFoundError.description.contains("doesn't exist"))
        XCTAssertTrue(targetNotFoundError.possibleCauses.count > 0)
        XCTAssertTrue(targetNotFoundError.solutions.count > 0)
        XCTAssertTrue(targetNotFoundError.relatedCommands.contains { $0.contains("LibraryTarget") })
    }
    
    func testCompilationErrorHandling() {
        let compilationError = UserFriendlyError.compilationFailed("Swift compiler exited with code 1")
        
        XCTAssertEqual(compilationError.title, "Swift compilation failed")
        XCTAssertTrue(compilationError.description.contains("couldn't be compiled"))
        XCTAssertTrue(compilationError.solutions.contains { $0.contains("Fix compilation errors") })
        XCTAssertNotNil(compilationError.example)
    }
    
    func testMissingToolsError() {
        let missingToolsError = UserFriendlyError.missingTools(["swift", "clang"])
        
        XCTAssertEqual(missingToolsError.title, "Required development tools missing")
        XCTAssertTrue(missingToolsError.description.contains("aren't available"))
        XCTAssertTrue(missingToolsError.solutions.first?.contains("swift, clang") == true)
    }
    
    func testUnsupportedSwiftVersionError() {
        let versionError = UserFriendlyError.unsupportedSwiftVersion("5.8.0")
        
        XCTAssertTrue(versionError.title.contains("5.8.0"))
        XCTAssertTrue(versionError.description.contains("5.9 or later"))
        XCTAssertTrue(versionError.solutions.contains { $0.contains("Swift 5.9+") })
    }
    
    func testNoFuzzTestsError() {
        let noFuzzTestsError = UserFriendlyError.noFuzzTests()
        
        XCTAssertEqual(noFuzzTestsError.title, "No fuzz tests found in target")
        XCTAssertTrue(noFuzzTestsError.description.contains("@fuzzTest"))
        XCTAssertNotNil(noFuzzTestsError.example)
        XCTAssertTrue(noFuzzTestsError.example?.contains("@fuzzTest") == true)
    }
    
    func testWarningReporting() {
        let warning = UserFriendlyWarning(
            title: "Test Warning",
            message: "This is a test warning",
            suggestion: "Consider this suggestion"
        )
        
        // This test just ensures the warning structure is valid
        XCTAssertEqual(warning.title, "Test Warning")
        XCTAssertEqual(warning.message, "This is a test warning")
        XCTAssertEqual(warning.suggestion, "Consider this suggestion")
    }
    
    func testCrashReportGeneration() {
        let crashReport = CrashReport(
            functionName: "testFunction",
            functionHash: 0x1234ABCD,
            inputSize: 42,
            crashType: .bufferOverflow,
            reproductionCode: "let data = Data([1, 2, 3])\ntestFunction(data)",
            rawInputHex: "01 02 03 FF",
            suggestedFixes: [
                "Add bounds checking",
                "Validate input size"
            ],
            artifactPath: "crash-test.bin"
        )
        
        XCTAssertEqual(crashReport.functionName, "testFunction")
        XCTAssertEqual(crashReport.functionHash, 0x1234ABCD)
        XCTAssertEqual(crashReport.inputSize, 42)
        XCTAssertEqual(crashReport.crashType.description, "Buffer Overflow")
        XCTAssertTrue(crashReport.reproductionCode.contains("testFunction"))
        XCTAssertEqual(crashReport.suggestedFixes.count, 2)
    }
    
    func testCrashTypeDescriptions() {
        XCTAssertEqual(CrashType.bufferOverflow.description, "Buffer Overflow")
        XCTAssertEqual(CrashType.nullPointerDereference.description, "Null Pointer Access")
        XCTAssertEqual(CrashType.integerOverflow.description, "Integer Overflow")
        XCTAssertEqual(CrashType.assertionFailure.description, "Assertion Failure")
        XCTAssertEqual(CrashType.unknown("Custom").description, "Custom")
    }
    
    func testPhaseConfigurationComplete() {
        // Ensure all phases have proper configuration
        let phases: [Phase] = [.setup, .validation, .buildingDependencies, .linkingDependencies, .compilingTarget, .running, .analyzing]
        
        for phase in phases {
            XCTAssertFalse(phase.emoji.isEmpty, "Phase \(phase) should have an emoji")
            XCTAssertFalse(phase.title.isEmpty, "Phase \(phase) should have a title")
            XCTAssertTrue(phase.title.count > 5, "Phase \(phase) title should be descriptive")
        }
    }
    
    func testEnvironmentValidationComponents() {
        // Test individual components of environment validation without actually running them
        // This ensures the validation logic is structured correctly
        
        // We can't easily test the actual validation without mocking the environment,
        // but we can ensure the error types are properly configured
        let missingTools = ["nonexistent-tool"]
        let toolError = UserFriendlyError.missingTools(missingTools)
        
        XCTAssertTrue(toolError.relatedCommands.contains { $0.contains("xcode-select") })
        XCTAssertTrue(toolError.solutions.contains { $0.contains("nonexistent-tool") })
    }
}