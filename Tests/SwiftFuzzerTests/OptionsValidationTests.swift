import XCTest
import Foundation
@testable import SwiftFuzzerLib

/// Fast unit tests for CLI options validation and configuration parsing
/// These tests validate argument parsing and option handling without expensive builds
final class OptionsValidationTests: XCTestCase {
    
    // MARK: - SwiftFuzzerOptions Tests
    
    func testOptionsWithAllParameters() {
        let options = SwiftFuzzerOptions(
            packagePath: "/path/to/package",
            configuration: "release",
            target: "MyTarget",
            buildOnly: true,
            maxTotalTime: 300,
            runs: 1000,
            corpus: "/path/to/corpus"
        )
        
        XCTAssertEqual(options.packagePath, "/path/to/package")
        XCTAssertEqual(options.configuration, "release")
        XCTAssertEqual(options.target, "MyTarget")
        XCTAssertTrue(options.buildOnly)
        XCTAssertEqual(options.maxTotalTime, 300)
        XCTAssertEqual(options.runs, 1000)
        XCTAssertEqual(options.corpus, "/path/to/corpus")
    }
    
    func testOptionsWithMinimalParameters() {
        let options = SwiftFuzzerOptions(
            packagePath: "/minimal/path",
            target: "MinimalTarget"
        )
        
        XCTAssertEqual(options.packagePath, "/minimal/path")
        XCTAssertEqual(options.configuration, "debug") // default
        XCTAssertEqual(options.target, "MinimalTarget")
        XCTAssertFalse(options.buildOnly) // default
        XCTAssertNil(options.maxTotalTime)
        XCTAssertNil(options.runs)
        XCTAssertNil(options.corpus)
    }
    
    func testOptionsConfigurationValidation() {
        // Valid configurations
        let debugOptions = SwiftFuzzerOptions(packagePath: "/path", configuration: "debug", target: "Target")
        let releaseOptions = SwiftFuzzerOptions(packagePath: "/path", configuration: "release", target: "Target")
        
        XCTAssertEqual(debugOptions.configuration, "debug")
        XCTAssertEqual(releaseOptions.configuration, "release")
        
        // Invalid configurations are allowed (will be handled by Swift Package Manager)
        let customOptions = SwiftFuzzerOptions(packagePath: "/path", configuration: "custom", target: "Target")
        XCTAssertEqual(customOptions.configuration, "custom")
    }
    
    func testOptionsWithEdgeCaseValues() {
        // Test with zero and negative values
        let options = SwiftFuzzerOptions(
            packagePath: "",
            target: "",
            maxTotalTime: 0,
            runs: 0
        )
        
        XCTAssertEqual(options.packagePath, "")
        XCTAssertEqual(options.target, "")
        XCTAssertEqual(options.maxTotalTime, 0)
        XCTAssertEqual(options.runs, 0)
    }
    
    func testOptionsWithLargeValues() {
        let options = SwiftFuzzerOptions(
            packagePath: "/very/long/path/that/might/exist/somewhere/in/the/filesystem/hierarchy",
            target: "VeryLongTargetNameThatSomeoneActuallyMightUse",
            maxTotalTime: Int.max,
            runs: Int.max
        )
        
        XCTAssertEqual(options.maxTotalTime, Int.max)
        XCTAssertEqual(options.runs, Int.max)
        XCTAssertTrue(options.packagePath.count > 50)
        XCTAssertTrue(options.target.count > 20)
    }
    
    // MARK: - StringError Tests
    
    func testStringErrorCreation() {
        let error = StringError("Test error message")
        XCTAssertEqual(error.message, "Test error message")
        
        let emptyError = StringError("")
        XCTAssertEqual(emptyError.message, "")
        
        let longError = StringError(String(repeating: "Error ", count: 1000))
        XCTAssertEqual(longError.message.count, 6000) // "Error " * 1000
    }
    
    func testStringErrorConformance() {
        let error = StringError("Test")
        
        // Should conform to Error protocol
        XCTAssertTrue(error is Error)
        
        // Should be usable in throw/catch
        do {
            throw error
        } catch let caught as StringError {
            XCTAssertEqual(caught.message, "Test")
        } catch {
            XCTFail("Should catch as StringError")
        }
    }
    
    // MARK: - Configuration Validation Tests
    
    func testConfigurationNormalization() {
        // Test that configuration strings are handled consistently
        let testCases = [
            ("debug", "debug"),
            ("DEBUG", "DEBUG"), // Should preserve case
            ("release", "release"),
            ("RELEASE", "RELEASE"), // Should preserve case
            ("Debug", "Debug"), // Should preserve case
            ("Release", "Release"), // Should preserve case
            ("custom-config", "custom-config"),
            ("test_config", "test_config"),
            ("", "")
        ]
        
        for (input, expected) in testCases {
            let options = SwiftFuzzerOptions(packagePath: "/path", configuration: input, target: "Target")
            XCTAssertEqual(options.configuration, expected, "Configuration '\(input)' should be preserved as '\(expected)'")
        }
    }
    
    func testTargetNameValidation() {
        // Test various target name formats that should be accepted
        let validTargets = [
            "SimpleTarget",
            "My-Target",
            "My_Target", 
            "MyTarget123",
            "target",
            "TARGET",
            "CamelCaseTarget",
            "snake_case_target",
            "kebab-case-target",
            "Target.Framework",
            "123Target" // Numbers at start
        ]
        
        for target in validTargets {
            let options = SwiftFuzzerOptions(packagePath: "/path", target: target)
            XCTAssertEqual(options.target, target, "Target name '\(target)' should be preserved")
        }
    }
    
    func testPackagePathValidation() {
        let testPaths = [
            "/absolute/path",
            "./relative/path",
            "../parent/path",
            "current/directory",
            "/",
            ".",
            "..",
            "~/home/path",
            "/path with spaces/to/package",
            "/path/with/unicode/émoji/🎯",
            "" // Empty path
        ]
        
        for path in testPaths {
            let options = SwiftFuzzerOptions(packagePath: path, target: "Target")
            XCTAssertEqual(options.packagePath, path, "Package path '\(path)' should be preserved")
        }
    }
    
    // MARK: - Time and Run Limits Tests
    
    func testTimeAndRunLimitsValidation() {
        // Test boundary values for time and run limits
        let testCases: [(Int?, Int?, Bool)] = [
            (nil, nil, true), // Both nil should be valid
            (0, 0, true), // Zero values should be valid
            (1, 1, true), // Minimum positive values
            (Int.max, Int.max, true), // Maximum values
            (60, 1000, true), // Typical values
            (1, Int.max, true), // Mixed values
            (Int.max, 1, true) // Mixed values
        ]
        
        for (time, runs, shouldBeValid) in testCases {
            let options = SwiftFuzzerOptions(
                packagePath: "/path",
                target: "Target",
                maxTotalTime: time,
                runs: runs
            )
            
            XCTAssertEqual(options.maxTotalTime, time)
            XCTAssertEqual(options.runs, runs)
            
            if shouldBeValid {
                // All combinations should be structurally valid
                // (Runtime validation happens elsewhere)
                XCTAssertNotNil(options)
            }
        }
    }
    
    func testBuildOnlyFlagValidation() {
        let buildOnlyTrue = SwiftFuzzerOptions(packagePath: "/path", target: "Target", buildOnly: true)
        let buildOnlyFalse = SwiftFuzzerOptions(packagePath: "/path", target: "Target", buildOnly: false)
        let buildOnlyDefault = SwiftFuzzerOptions(packagePath: "/path", target: "Target")
        
        XCTAssertTrue(buildOnlyTrue.buildOnly)
        XCTAssertFalse(buildOnlyFalse.buildOnly)
        XCTAssertFalse(buildOnlyDefault.buildOnly) // Default should be false
    }
    
    func testCorpusPathValidation() {
        let testCorpusPaths = [
            nil,
            "/absolute/corpus/path",
            "./relative/corpus",
            "../corpus",
            "corpus",
            "/tmp/corpus",
            "/var/folders/temp/corpus",
            "/path with spaces/corpus",
            ""
        ]
        
        for corpusPath in testCorpusPaths {
            let options = SwiftFuzzerOptions(
                packagePath: "/path",
                target: "Target",
                corpus: corpusPath
            )
            
            XCTAssertEqual(options.corpus, corpusPath)
        }
    }
    
    // MARK: - Options Combination Tests
    
    func testMutuallyExclusiveOptions() {
        // buildOnly=true with time limits should be valid (time limits ignored)
        let buildOnlyWithTime = SwiftFuzzerOptions(
            packagePath: "/path",
            target: "Target",
            buildOnly: true,
            maxTotalTime: 60
        )
        
        XCTAssertTrue(buildOnlyWithTime.buildOnly)
        XCTAssertEqual(buildOnlyWithTime.maxTotalTime, 60)
        
        // buildOnly=true with run limits should be valid (run limits ignored)
        let buildOnlyWithRuns = SwiftFuzzerOptions(
            packagePath: "/path",
            target: "Target",
            buildOnly: true,
            runs: 1000
        )
        
        XCTAssertTrue(buildOnlyWithRuns.buildOnly)
        XCTAssertEqual(buildOnlyWithRuns.runs, 1000)
    }
    
    func testFuzzingOptionsValidation() {
        // Both time and run limits specified (should be valid, implementation decides precedence)
        let bothLimits = SwiftFuzzerOptions(
            packagePath: "/path",
            target: "Target",
            maxTotalTime: 60,
            runs: 1000
        )
        
        XCTAssertEqual(bothLimits.maxTotalTime, 60)
        XCTAssertEqual(bothLimits.runs, 1000)
        
        // Only time limit
        let timeOnly = SwiftFuzzerOptions(
            packagePath: "/path",
            target: "Target",
            maxTotalTime: 120
        )
        
        XCTAssertEqual(timeOnly.maxTotalTime, 120)
        XCTAssertNil(timeOnly.runs)
        
        // Only run limit
        let runsOnly = SwiftFuzzerOptions(
            packagePath: "/path",
            target: "Target",
            runs: 500
        )
        
        XCTAssertNil(runsOnly.maxTotalTime)
        XCTAssertEqual(runsOnly.runs, 500)
    }
}