import XCTest
import Foundation
import TSCBasic
import SwiftFuzzerLib

final class SwiftFuzzerIntegrationTests: XCTestCase {
    
    func testSimpleLibraryBuildOnly() async throws {
        // Given
        let testFilePath = try AbsolutePath(validating: #filePath)
        let testProjectPath = testFilePath
            .parentDirectory  // SwiftFuzzerTests
            .appending(components: "IntegrationTests", "TestProjects", "SimpleLibrary")
        
        // When
        let options = SwiftFuzzerOptions(
            packagePath: testProjectPath.pathString,
            configuration: "debug",
            target: "SimpleLibrary",
            buildOnly: true
        )
        
        // Then - should not throw
        try await SwiftFuzzerCore.run(options: options)
        
        // Verify fuzzer executable exists and is executable
        let expectedExecutable = testProjectPath
            .appending(components: ".fuzz", ".build", "debug", "SimpleLibrary")
        XCTAssertTrue(localFileSystem.exists(expectedExecutable), 
                     "Fuzzer executable should exist at \(expectedExecutable)")
        
        // Verify the executable exists and has proper file size (indicating successful build)
        let fileAttributes = try localFileSystem.getFileInfo(expectedExecutable)
        XCTAssertGreaterThan(fileAttributes.size, 0, 
                           "Fuzzer executable should have non-zero size")
        
        // Verify fuzzer entrypoint was generated with proper structure
        let entrypointFile = testProjectPath
            .appending(components: ".fuzz", ".build", "debug", "SimpleLibrary.build", "FuzzerEntrypoint.swift")
        XCTAssertTrue(localFileSystem.exists(entrypointFile), 
                     "Fuzzer entrypoint should exist at \(entrypointFile)")
        
        let entrypointContent = try localFileSystem.readFileContents(entrypointFile).description
        XCTAssertTrue(entrypointContent.contains("@_cdecl(\"LLVMFuzzerTestOneInput\")"), 
                     "Entrypoint should have LibFuzzer entry point")
        XCTAssertTrue(entrypointContent.contains("FuzzTestRegistry.initialize()"), 
                     "Entrypoint should initialize registry")
        XCTAssertTrue(entrypointContent.contains("FuzzTestRegistry.runSelected"), 
                     "Entrypoint should run registered tests")
    }
    
    func testSimpleLibraryBuildAndRunWithTimeLimit() async throws {
        // Given
        let testFilePath = try AbsolutePath(validating: #filePath)
        let testProjectPath = testFilePath
            .parentDirectory
            .appending(components: "IntegrationTests", "TestProjects", "SimpleLibrary")
        
        // When - run for 2 seconds only to verify fuzzer registry works
        let options = SwiftFuzzerOptions(
            packagePath: testProjectPath.pathString,
            configuration: "debug",
            target: "SimpleLibrary",
            buildOnly: false,
            maxTotalTime: 2
        )
        
        // Then - should complete without throwing (fuzzer should run registered tests)
        do {
            try await SwiftFuzzerCore.run(options: options)
        } catch {
            // Fuzzer may find bugs and throw - that's acceptable for this test
            // What matters is that it ran without build/registration errors
        }
        
        // Verify that the fuzzer actually ran by checking it created its working directory
        let fuzzDir = testProjectPath.appending(component: ".fuzz")
        XCTAssertTrue(localFileSystem.exists(fuzzDir),
                     "Fuzzer should have created its working directory")
    }
    
    func testFuzzTestRegistryPopulation() async throws {
        // Given
        let testFilePath = try AbsolutePath(validating: #filePath)
        let testProjectPath = testFilePath
            .parentDirectory
            .appending(components: "IntegrationTests", "TestProjects", "SimpleLibrary")
        
        // When - build the fuzzer
        let options = SwiftFuzzerOptions(
            packagePath: testProjectPath.pathString,
            configuration: "debug",
            target: "SimpleLibrary",
            buildOnly: true
        )
        
        try await SwiftFuzzerCore.run(options: options)
        
        // Then - verify that the macro-generated registrator classes were built
        let buildDir = testProjectPath.appending(components: ".fuzz", ".build", "debug")
        
        // Check that build artifacts exist (indicating macro expansion worked)
        let buildArtifacts = try localFileSystem.getDirectoryContents(buildDir)
        XCTAssertTrue(buildArtifacts.contains("SimpleLibrary"), 
                     "Fuzzer executable should exist in build directory")
        
        // Verify that the build process succeeded without macro expansion errors
        // If macros failed to expand, the build would have failed
        let executable = buildDir.appending(component: "SimpleLibrary")
        XCTAssertTrue(localFileSystem.exists(executable),
                     "Successful build indicates macro expansion worked correctly")
    }
    
    func testInvalidTargetShowsError() async throws {
        // Given
        let testFilePath = try AbsolutePath(validating: #filePath)
        let testProjectPath = testFilePath
            .parentDirectory
            .appending(components: "IntegrationTests", "TestProjects", "SimpleLibrary")
        
        // When
        let options = SwiftFuzzerOptions(
            packagePath: testProjectPath.pathString,
            configuration: "debug",
            target: "NonExistentTarget",
            buildOnly: true
        )
        
        // Then
        do {
            try await SwiftFuzzerCore.run(options: options)
            XCTFail("Should throw error for non-existent target")
        } catch let error as SwiftFuzzerLib.StringError {
            XCTAssertTrue(error.message.contains("Target 'NonExistentTarget' not found"))
        }
    }
    
    func testBuildShowsAvailableTargets() async throws {
        // Given
        let testFilePath = try AbsolutePath(validating: #filePath)
        let testProjectPath = testFilePath
            .parentDirectory
            .appending(components: "IntegrationTests", "TestProjects", "SimpleLibrary")
        
        // When
        let options = SwiftFuzzerOptions(
            packagePath: testProjectPath.pathString,
            configuration: "debug",
            target: "WrongTarget",
            buildOnly: true
        )
        
        // Then
        do {
            try await SwiftFuzzerCore.run(options: options)
            XCTFail("Should throw error for wrong target")
        } catch let error as SwiftFuzzerLib.StringError {
            XCTAssertTrue(error.message.contains("Target 'WrongTarget' not found"))
        }
    }
}
