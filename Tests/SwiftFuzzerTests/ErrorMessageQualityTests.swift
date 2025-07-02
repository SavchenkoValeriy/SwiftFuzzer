import XCTest
import Foundation
@testable import SwiftFuzzerLib

/// Tests that validate the quality and helpfulness of error messages
/// Ensures all error messages follow consistent patterns and provide actionable guidance
final class ErrorMessageQualityTests: XCTestCase {
    
    // MARK: - Error Message Structure Tests
    
    func testAllErrorsHaveRequiredComponents() {
        let errors = createAllErrorTypes()
        
        for (errorName, error) in errors {
            // Every error must have a clear title
            XCTAssertFalse(error.title.isEmpty, "\(errorName) must have a title")
            XCTAssertGreaterThan(error.title.count, 5, "\(errorName) title must be descriptive")
            
            // Every error must have a description
            XCTAssertFalse(error.description.isEmpty, "\(errorName) must have a description")
            XCTAssertGreaterThan(error.description.count, 10, "\(errorName) description must be substantial")
            
            // Every error should have possible causes
            XCTAssertGreaterThan(error.possibleCauses.count, 0, "\(errorName) should explain possible causes")
            
            // Every error should have solutions
            XCTAssertGreaterThan(error.solutions.count, 0, "\(errorName) should provide solutions")
        }
    }
    
    func testErrorTitleConsistency() {
        let errors = createAllErrorTypes()
        
        for (errorName, error) in errors {
            let title = error.title
            
            // Titles should not end with punctuation
            XCTAssertFalse(title.hasSuffix("."), "\(errorName) title should not end with period")
            XCTAssertFalse(title.hasSuffix("!"), "\(errorName) title should not end with exclamation")
            XCTAssertFalse(title.hasSuffix("?"), "\(errorName) title should not end with question mark")
            
            // Titles should be sentence case or contain specific terms
            let firstChar = title.first!
            XCTAssertTrue(firstChar.isUppercase || firstChar.isNumber, "\(errorName) title should start with uppercase or number")
            
            // Titles should be concise (not too long)
            XCTAssertLessThan(title.count, 100, "\(errorName) title should be concise")
        }
    }
    
    func testErrorDescriptionQuality() {
        let errors = createAllErrorTypes()
        
        for (errorName, error) in errors {
            let description = error.description
            
            // Descriptions should end with proper punctuation
            XCTAssertTrue(description.hasSuffix(".") || description.hasSuffix("!"), 
                         "\(errorName) description should end with punctuation")
            
            // Descriptions should not be too short or too long
            XCTAssertGreaterThan(description.count, 20, "\(errorName) description should be substantial")
            XCTAssertLessThan(description.count, 300, "\(errorName) description should be concise")
            
            // Descriptions should not contain technical jargon without explanation
            let technicalTerms = ["SPM", "libFuzzer", "LLVM", "dylib", "Xcode"]
            for term in technicalTerms {
                if description.contains(term) {
                    // If technical terms are used, there should be context
                    XCTAssertTrue(description.count > 50, 
                                "\(errorName) using '\(term)' should provide context")
                }
            }
        }
    }
    
    func testPossibleCausesQuality() {
        let errors = createAllErrorTypes()
        
        for (errorName, error) in errors {
            XCTAssertGreaterThan(error.possibleCauses.count, 1, 
                               "\(errorName) should have multiple possible causes")
            XCTAssertLessThan(error.possibleCauses.count, 6, 
                            "\(errorName) should not overwhelm with too many causes")
            
            for (index, cause) in error.possibleCauses.enumerated() {
                // Causes should be substantial
                XCTAssertGreaterThan(cause.count, 10, 
                                   "\(errorName) cause \(index + 1) should be descriptive")
                
                // Causes should not start with capital letters (they're list items)
                if !cause.isEmpty {
                    let firstChar = cause.first!
                    XCTAssertTrue(firstChar.isUppercase || firstChar.isNumber, 
                                "\(errorName) cause \(index + 1) should start with uppercase")
                }
                
                // Causes should not end with periods (they're short phrases)
                XCTAssertFalse(cause.hasSuffix("."), 
                             "\(errorName) cause \(index + 1) should not end with period")
            }
        }
    }
    
    func testSolutionsQuality() {
        let errors = createAllErrorTypes()
        
        for (errorName, error) in errors {
            XCTAssertGreaterThan(error.solutions.count, 1, 
                               "\(errorName) should have multiple solutions")
            XCTAssertLessThan(error.solutions.count, 6, 
                            "\(errorName) should not overwhelm with too many solutions")
            
            for (index, solution) in error.solutions.enumerated() {
                // Solutions should be substantial and actionable
                XCTAssertGreaterThan(solution.count, 10, 
                                   "\(errorName) solution \(index + 1) should be descriptive")
                
                // Solutions should start with action verbs
                let actionVerbs = ["Add", "Install", "Check", "Verify", "Run", "Use", "Try", "Fix", 
                                 "Update", "Create", "Remove", "Change", "Set", "Ensure", "Make"]
                let startsWithAction = actionVerbs.contains { solution.hasPrefix($0) }
                XCTAssertTrue(startsWithAction, 
                            "\(errorName) solution \(index + 1) should start with action verb: '\(solution)'")
                
                // Solutions should not end with periods
                XCTAssertFalse(solution.hasSuffix("."), 
                             "\(errorName) solution \(index + 1) should not end with period")
            }
        }
    }
    
    func testExampleQuality() {
        let errors = createAllErrorTypes()
        
        for (errorName, error) in errors {
            if let example = error.example {
                // Examples should be substantial
                XCTAssertGreaterThan(example.count, 10, 
                                   "\(errorName) example should be descriptive")
                
                // Examples should not be too long
                XCTAssertLessThan(example.count, 200, 
                                "\(errorName) example should be concise")
                
                // Examples should contain relevant command or code
                let containsCommand = example.contains("swift-fuzz") || 
                                    example.contains("swift ") ||
                                    example.contains("@fuzzTest") ||
                                    example.contains("swiftly")
                XCTAssertTrue(containsCommand, 
                            "\(errorName) example should contain relevant command or code")
            }
        }
    }
    
    func testRelatedCommandsQuality() {
        let errors = createAllErrorTypes()
        
        for (errorName, error) in errors {
            XCTAssertGreaterThan(error.relatedCommands.count, 0, 
                               "\(errorName) should have related commands")
            XCTAssertLessThan(error.relatedCommands.count, 5, 
                            "\(errorName) should not overwhelm with too many commands")
            
            for (index, command) in error.relatedCommands.enumerated() {
                // Commands should be substantial
                XCTAssertGreaterThan(command.count, 5, 
                                   "\(errorName) command \(index + 1) should be meaningful")
                
                // Commands should contain actual commands or helpful info
                let containsUsefulContent = command.contains("swift") || 
                                          command.contains("Available targets:") ||
                                          command.contains("xcode-select") ||
                                          command.contains("swiftly") ||
                                          command.contains("grep")
                XCTAssertTrue(containsUsefulContent, 
                            "\(errorName) command \(index + 1) should be useful: '\(command)'")
            }
        }
    }
    
    // MARK: - Error Specificity Tests
    
    func testTargetNotFoundErrorSpecificity() {
        let availableTargets = ["ValidTarget1", "ValidTarget2", "LibraryTarget"]
        let error = DiagnosticError.targetNotFound("InvalidTarget", availableTargets: availableTargets)
        
        // Should mention the specific target that wasn't found
        XCTAssertTrue(error.title.contains("InvalidTarget"))
        
        // Should list available targets
        let hasAllTargets = availableTargets.allSatisfy { target in
            error.relatedCommands.contains { $0.contains(target) }
        }
        XCTAssertTrue(hasAllTargets, "Should list all available targets")
        
        // Should suggest exact naming
        XCTAssertTrue(error.solutions.contains { $0.contains("exact name") })
    }
    
    func testCompilationErrorSpecificity() {
        let errorDetails = "File.swift:42: error: use of undeclared identifier 'foo'"
        let error = DiagnosticError.compilationFailed(errorDetails)
        
        // Should provide specific guidance for common compilation issues
        XCTAssertTrue(error.possibleCauses.contains { $0.contains("Syntax errors") })
        XCTAssertTrue(error.possibleCauses.contains { $0.contains("import") })
        XCTAssertTrue(error.solutions.contains { $0.contains("Fix compilation errors") })
        XCTAssertTrue(error.solutions.contains { $0.contains("import FuzzTest") })
        
        // Should include helpful example
        XCTAssertNotNil(error.example)
        XCTAssertTrue(error.example!.contains("@fuzzTest"))
    }
    
    func testSwiftVersionErrorSpecificity() {
        let version = "5.8.1"
        let error = DiagnosticError.unsupportedSwiftVersion(version)
        
        // Should mention specific version
        XCTAssertTrue(error.title.contains(version))
        
        // Should mention minimum required version
        XCTAssertTrue(error.description.contains("5.9"))
        
        // Should provide specific installation guidance
        XCTAssertTrue(error.solutions.contains { $0.contains("Swift 5.9+") })
        XCTAssertTrue(error.relatedCommands.contains { $0.contains("swiftly") })
    }
    
    func testMissingToolsErrorSpecificity() {
        let tools = ["swift", "clang", "ld"]
        let error = DiagnosticError.missingTools(tools)
        
        // Should mention specific tools
        let allToolsMentioned = tools.allSatisfy { tool in
            error.solutions.contains { $0.contains(tool) }
        }
        XCTAssertTrue(allToolsMentioned, "Should mention all missing tools")
        
        // Should provide installation commands
        XCTAssertTrue(error.relatedCommands.contains { $0.contains("xcode-select") })
        XCTAssertTrue(error.relatedCommands.contains { $0.contains("swiftly") })
    }
    
    // MARK: - User Experience Tests
    
    func testErrorMessageTone() {
        let errors = createAllErrorTypes()
        
        for (errorName, error) in errors {
            // Should be helpful, not accusatory
            let negativeWords = ["failed", "wrong", "bad", "broken", "stupid", "invalid"]
            let description = error.description.lowercased()
            
            // Allow "failed" but discourage harsh language
            let harshWords = negativeWords.filter { $0 != "failed" }
            for word in harshWords {
                XCTAssertFalse(description.contains(word), 
                             "\(errorName) should avoid harsh language: '\(word)'")
            }
            
            // Should use positive, solution-oriented language in solutions
            let positiveWords = ["check", "verify", "ensure", "add", "install", "use", "try"]
            let hasPosLanguage = error.solutions.contains { solution in
                let lowerSolution = solution.lowercased()
                return positiveWords.contains { lowerSolution.contains($0) }
            }
            XCTAssertTrue(hasPosLanguage, "\(errorName) should use positive language in solutions")
        }
    }
    
    func testErrorProgression() {
        let errors = createAllErrorTypes()
        
        for (errorName, error) in errors {
            // Should progress from problem identification to solution
            // 1. Title: What went wrong
            // 2. Description: What happened
            // 3. Causes: Why it might have happened
            // 4. Solutions: How to fix it
            // 5. Example: What success looks like
            // 6. Commands: Tools to help
            
            // Causes should be investigative
            XCTAssertTrue(error.possibleCauses.contains { $0.contains("not") || $0.contains("missing") || $0.contains("wrong") },
                        "\(errorName) should include investigative causes")
            
            // Solutions should be constructive
            XCTAssertTrue(error.solutions.contains { $0.lowercased().hasPrefix("add") || 
                                                   $0.lowercased().hasPrefix("install") || 
                                                   $0.lowercased().hasPrefix("check") ||
                                                   $0.lowercased().hasPrefix("verify") ||
                                                   $0.lowercased().hasPrefix("use") },
                        "\(errorName) should include constructive solutions")
        }
    }
    
    // MARK: - Helper Methods
    
    private func createAllErrorTypes() -> [(String, DiagnosticError)] {
        return [
            ("targetNotFound", DiagnosticError.targetNotFound("TestTarget", availableTargets: ["RealTarget1", "RealTarget2"])),
            ("compilationFailed", DiagnosticError.compilationFailed("Swift compilation error details")),
            ("missingTools", DiagnosticError.missingTools(["swift", "clang"])),
            ("unsupportedSwiftVersion", DiagnosticError.unsupportedSwiftVersion("5.8.0")),
            ("noFuzzTests", DiagnosticError.noFuzzTests())
        ]
    }
}