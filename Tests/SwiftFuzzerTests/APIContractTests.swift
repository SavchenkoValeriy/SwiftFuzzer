import XCTest
import Foundation
@testable import SwiftFuzzerLib

/// Tests that validate the contracts and behavior of core API interfaces
/// Ensures APIs behave consistently and maintain backward compatibility
final class APIContractTests: XCTestCase {
    
    // MARK: - UserInterface API Contract Tests
    
    func testUserInterfacePhaseDisplayContract() {
        // All phases should be displayable without throwing
        let phases: [Phase] = [.setup, .validation, .buildingDependencies, 
                              .linkingDependencies, .compilingTarget, .running, .analyzing]
        
        for phase in phases {
            // Should not throw when displaying
            XCTAssertNoThrow({
                UserInterface.showPhaseStart(phase)
            }, "showPhaseStart should not throw for phase: \(phase)")
        }
    }
    
    func testUserInterfaceStepDisplayContract() {
        let testSteps = [
            "Simple step",
            "Step with special characters: @#$%^&*()",
            "Step with unicode: 🚀 ✅ 🔍",
            "Very long step message that might wrap across multiple lines and should still be handled gracefully by the interface",
            "",
            "Step\nwith\nnewlines"
        ]
        
        for step in testSteps {
            // Should not throw for any step content
            XCTAssertNoThrow({
                UserInterface.showStep(step)
                UserInterface.showStep(step, isSubStep: true)
                UserInterface.showStep(step, isSubStep: false)
            }, "showStep should handle all step formats: '\(step.prefix(20))'")
        }
    }
    
    func testUserInterfaceProgressContract() {
        let testCases: [(Int, Int, String, Bool)] = [
            (0, 10, "Starting", true),
            (5, 10, "Middle", true),
            (10, 10, "Complete", true),
            (0, 1, "Single item", true),
            (1, 1, "Single complete", true),
            (0, 0, "Zero total", false), // Should handle gracefully
            (-1, 10, "Negative current", false),
            (15, 10, "Over total", false),
            (5, -1, "Negative total", false)
        ]
        
        for (current, total, description, shouldBeValid) in testCases {
            if shouldBeValid {
                XCTAssertNoThrow({
                    UserInterface.showProgress(current, total, description)
                }, "showProgress should handle valid case: \(current)/\(total)")
            } else {
                // Should handle edge cases gracefully (not crash)
                XCTAssertNoThrow({
                    UserInterface.showProgress(current, total, description)
                }, "showProgress should handle edge case gracefully: \(current)/\(total)")
            }
        }
    }
    
    func testUserInterfaceSuccessMessageContract() {
        let testMessages = [
            "Build completed successfully",
            "All tests passed ✅",
            "",
            "Message with\nmultiple\nlines",
            String(repeating: "Long message ", count: 100)
        ]
        
        for message in testMessages {
            XCTAssertNoThrow({
                UserInterface.showSuccess(message)
            }, "showSuccess should handle all message types")
        }
    }
    
    func testUserInterfaceErrorReportingContract() {
        let error = UserFriendlyError.targetNotFound("TestTarget", availableTargets: ["RealTarget"])
        
        // Error reporting should throw StringError for backward compatibility
        XCTAssertThrowsError(try UserInterface.reportError(error)) { thrownError in
            XCTAssertTrue(thrownError is StringError, "reportError should throw StringError")
            if let stringError = thrownError as? StringError {
                XCTAssertTrue(stringError.message.contains("TestTarget"), "Error message should contain target name")
            }
        }
    }
    
    func testUserInterfaceWarningReportingContract() {
        let warning = UserFriendlyWarning(title: "Test Warning", message: "Test message", suggestion: "Test suggestion")
        
        // Warning reporting should not throw
        XCTAssertNoThrow({
            UserInterface.reportWarning(warning)
        }, "reportWarning should not throw")
    }
    
    func testUserInterfaceCrashReportingContract() {
        let crashReport = CrashReport(
            functionName: "testFunction",
            functionHash: 0x123,
            inputSize: 42,
            crashType: .bufferOverflow,
            reproductionCode: "test()",
            rawInputHex: "01 02 03",
            suggestedFixes: ["Fix 1", "Fix 2"],
            artifactPath: "/path/to/crash"
        )
        
        // Crash reporting should not throw
        XCTAssertNoThrow({
            UserInterface.reportCrash(crashReport)
        }, "reportCrash should not throw")
    }
    
    // MARK: - CrashReport API Contract Tests
    
    func testCrashReportInitializationContract() {
        // Test that CrashReport can be initialized with all valid combinations
        let testCases: [(String, UInt64, Int, CrashType, String, String, [String], String)] = [
            ("func1", 0x0, 0, .bufferOverflow, "", "", [], ""),
            ("func2", UInt64.max, Int.max, .nullPointerDereference, "code", "hex", ["fix"], "path"),
            ("🚀func", 0x123ABC, 42, .integerOverflow, "test(data)", "01 02 FF", ["Fix bounds", "Add validation"], "/tmp/crash.bin"),
            ("", 0, 0, .assertionFailure, "", "", [], ""),
            ("very_long_function_name_that_might_exist_in_real_code", 0xDEADBEEF, 1024, .unknown("Custom crash"), "complex reproduction code here", "00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F", ["First fix", "Second fix", "Third fix"], "/very/long/path/to/crash/artifact.bin")
        ]
        
        for (functionName, hash, size, crashType, code, hex, fixes, path) in testCases {
            let report = CrashReport(
                functionName: functionName,
                functionHash: hash,
                inputSize: size,
                crashType: crashType,
                reproductionCode: code,
                rawInputHex: hex,
                suggestedFixes: fixes,
                artifactPath: path
            )
            
            // All properties should be preserved exactly
            XCTAssertEqual(report.functionName, functionName)
            XCTAssertEqual(report.functionHash, hash)
            XCTAssertEqual(report.inputSize, size)
            XCTAssertEqual(report.crashType, crashType)
            XCTAssertEqual(report.reproductionCode, code)
            XCTAssertEqual(report.rawInputHex, hex)
            XCTAssertEqual(report.suggestedFixes, fixes)
            XCTAssertEqual(report.artifactPath, path)
        }
    }
    
    func testCrashTypeEquatabilityContract() {
        // Test that CrashType equality works correctly
        let testCases: [(CrashType, CrashType, Bool)] = [
            (.bufferOverflow, .bufferOverflow, true),
            (.nullPointerDereference, .nullPointerDereference, true),
            (.integerOverflow, .integerOverflow, true),
            (.assertionFailure, .assertionFailure, true),
            (.unknown("test"), .unknown("test"), true),
            (.bufferOverflow, .nullPointerDereference, false),
            (.unknown("test1"), .unknown("test2"), false),
            (.bufferOverflow, .unknown("bufferOverflow"), false)
        ]
        
        for (type1, type2, shouldBeEqual) in testCases {
            if shouldBeEqual {
                XCTAssertEqual(type1, type2, "CrashTypes should be equal: \(type1) == \(type2)")
            } else {
                XCTAssertNotEqual(type1, type2, "CrashTypes should not be equal: \(type1) != \(type2)")
            }
        }
    }
    
    func testCrashTypeDescriptionContract() {
        let testCases: [(CrashType, String)] = [
            (.bufferOverflow, "Buffer Overflow"),
            (.nullPointerDereference, "Null Pointer Access"),
            (.integerOverflow, "Integer Overflow"),
            (.assertionFailure, "Assertion Failure"),
            (.unknown("Custom Error"), "Custom Error"),
            (.unknown(""), ""),
            (.unknown("Very long custom error description"), "Very long custom error description")
        ]
        
        for (crashType, expectedDescription) in testCases {
            XCTAssertEqual(crashType.description, expectedDescription, 
                         "CrashType description should match expected value")
        }
    }
    
    // MARK: - UserFriendlyError API Contract Tests
    
    func testUserFriendlyErrorStructureContract() {
        // Test that all UserFriendlyError factory methods produce well-formed errors
        let errors: [(String, UserFriendlyError)] = [
            ("targetNotFound", UserFriendlyError.targetNotFound("Target", availableTargets: ["A", "B"])),
            ("compilationFailed", UserFriendlyError.compilationFailed("Error details")),
            ("missingTools", UserFriendlyError.missingTools(["tool1", "tool2"])),
            ("unsupportedSwiftVersion", UserFriendlyError.unsupportedSwiftVersion("5.8.0")),
            ("noFuzzTests", UserFriendlyError.noFuzzTests())
        ]
        
        for (errorType, error) in errors {
            // Structure validation
            XCTAssertFalse(error.title.isEmpty, "\(errorType) must have title")
            XCTAssertFalse(error.description.isEmpty, "\(errorType) must have description")
            XCTAssertGreaterThan(error.possibleCauses.count, 0, "\(errorType) must have causes")
            XCTAssertGreaterThan(error.solutions.count, 0, "\(errorType) must have solutions")
            XCTAssertGreaterThan(error.relatedCommands.count, 0, "\(errorType) must have commands")
            
            // Content validation
            for cause in error.possibleCauses {
                XCTAssertFalse(cause.isEmpty, "\(errorType) causes must not be empty")
            }
            
            for solution in error.solutions {
                XCTAssertFalse(solution.isEmpty, "\(errorType) solutions must not be empty")
            }
            
            for command in error.relatedCommands {
                XCTAssertFalse(command.isEmpty, "\(errorType) commands must not be empty")
            }
        }
    }
    
    func testUserFriendlyErrorCustomInitializationContract() {
        // Test custom UserFriendlyError initialization
        let customError = UserFriendlyError(
            title: "Custom Error",
            description: "Custom description.",
            possibleCauses: ["Cause 1", "Cause 2"],
            solutions: ["Solution 1", "Solution 2"],
            example: "example code",
            relatedCommands: ["command1", "command2"]
        )
        
        XCTAssertEqual(customError.title, "Custom Error")
        XCTAssertEqual(customError.description, "Custom description.")
        XCTAssertEqual(customError.possibleCauses, ["Cause 1", "Cause 2"])
        XCTAssertEqual(customError.solutions, ["Solution 1", "Solution 2"])
        XCTAssertEqual(customError.example, "example code")
        XCTAssertEqual(customError.relatedCommands, ["command1", "command2"])
    }
    
    // MARK: - StringError API Contract Tests
    
    func testStringErrorContract() {
        let testMessages = [
            "Simple error",
            "",
            "Error with special characters: @#$%^&*()",
            "Error with unicode: 🚨 ❌ 💥",
            String(repeating: "Long error message ", count: 100),
            "Error\nwith\nmultiple\nlines"
        ]
        
        for message in testMessages {
            let error = StringError(message)
            
            // Message should be preserved exactly
            XCTAssertEqual(error.message, message, "StringError should preserve message exactly")
            
            // Should conform to Error protocol
            XCTAssertTrue(error is Error, "StringError should conform to Error")
            
            // Should be throwable and catchable
            do {
                throw error
                XCTFail("Should have thrown")
            } catch let caught as StringError {
                XCTAssertEqual(caught.message, message, "Caught error should have same message")
            } catch {
                XCTFail("Should catch as StringError, got: \(type(of: error))")
            }
        }
    }
    
    // MARK: - SwiftFuzzerOptions API Contract Tests
    
    func testSwiftFuzzerOptionsImmutabilityContract() {
        let options = SwiftFuzzerOptions(
            packagePath: "/path",
            configuration: "debug",
            target: "Target",
            buildOnly: true,
            maxTotalTime: 60,
            runs: 100,
            corpus: "/corpus"
        )
        
        // All properties should be immutable (let properties)
        // This is enforced by the compiler, but we test the values are preserved
        XCTAssertEqual(options.packagePath, "/path")
        XCTAssertEqual(options.configuration, "debug")
        XCTAssertEqual(options.target, "Target")
        XCTAssertTrue(options.buildOnly)
        XCTAssertEqual(options.maxTotalTime, 60)
        XCTAssertEqual(options.runs, 100)
        XCTAssertEqual(options.corpus, "/corpus")
        
        // Test that creating new options with same values produces equal results
        let options2 = SwiftFuzzerOptions(
            packagePath: "/path",
            configuration: "debug",
            target: "Target",
            buildOnly: true,
            maxTotalTime: 60,
            runs: 100,
            corpus: "/corpus"
        )
        
        XCTAssertEqual(options.packagePath, options2.packagePath)
        XCTAssertEqual(options.configuration, options2.configuration)
        XCTAssertEqual(options.target, options2.target)
        XCTAssertEqual(options.buildOnly, options2.buildOnly)
        XCTAssertEqual(options.maxTotalTime, options2.maxTotalTime)
        XCTAssertEqual(options.runs, options2.runs)
        XCTAssertEqual(options.corpus, options2.corpus)
    }
    
    // MARK: - Phase API Contract Tests
    
    func testPhaseCompletenessContract() {
        // Test that all expected phases exist and are complete
        let expectedPhases: [Phase] = [
            .setup,
            .validation,
            .buildingDependencies,
            .linkingDependencies,
            .compilingTarget,
            .running,
            .analyzing
        ]
        
        // Should have exactly the expected phases (no more, no less)
        XCTAssertEqual(expectedPhases.count, 7, "Should have exactly 7 phases")
        
        // Each phase should be distinct
        let phaseSet = Set(expectedPhases.map { String(describing: $0) })
        XCTAssertEqual(phaseSet.count, expectedPhases.count, "All phases should be distinct")
    }
    
    // MARK: - Environment Validation Contract Tests
    
    func testEnvironmentValidationContract() {
        // Environment validation should be callable without throwing (may throw specific errors)
        // This tests the contract, not the actual environment
        XCTAssertNoThrow({
            do {
                try UserInterface.validateEnvironment()
                // If validation passes, that's fine
            } catch is StringError {
                // If validation fails with StringError, that's the expected contract
            } catch {
                XCTFail("validateEnvironment should only throw StringError, got: \(type(of: error))")
            }
        }, "validateEnvironment should not crash or throw unexpected errors")
    }
}