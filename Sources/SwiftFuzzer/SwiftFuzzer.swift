import ArgumentParser
import Foundation
import SwiftFuzzerLib
import FuzzTest

@main
struct SwiftFuzzer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-fuzz",
        abstract: "Build and run Swift fuzz tests using libFuzzer"
    )
    
    @Argument(help: "Path to the Swift package to build")
    var packagePath: String
    
    @Option(name: .shortAndLong, help: "Build configuration (debug/release)")
    var configuration: String = "debug"
    
    @Option(name: .long, help: "Target to build with fuzz instrumentation (required)")
    var target: String
    
    @Flag(name: .long, help: "Only build the fuzzer executable, don't run it")
    var buildOnly: Bool = false
    
    @Option(name: .long, help: "Maximum time to run fuzzer in seconds")
    var maxTotalTime: Int?
    
    @Option(name: .long, help: "Maximum number of runs")
    var runs: Int?
    
    @Option(name: .long, help: "Corpus directory for fuzzer input")
    var corpus: String?
    
    func run() async throws {
        // Validate environment before starting
        do {
            try UserInterface.validateEnvironment()
        } catch {
            // Validation errors are already reported by UserInterface
            throw ExitCode.failure
        }
        
        let options = SwiftFuzzerOptions(
            packagePath: packagePath,
            configuration: configuration,
            target: target,
            buildOnly: buildOnly,
            maxTotalTime: maxTotalTime,
            runs: runs,
            corpus: corpus
        )
        
        do {
            try await SwiftFuzzerCore.run(options: options)
        } catch let error as StringError {
            // Legacy error handling - convert to user-friendly format
            let friendlyError = UserFriendlyError(
                title: "SwiftFuzzer operation failed",
                description: error.message,
                possibleCauses: [
                    "Configuration issue",
                    "Build environment problem",
                    "Target specification error"
                ],
                solutions: [
                    "Verify your package configuration",
                    "Check that the target exists and is buildable",
                    "Try running 'swift build' first to check basic compilation"
                ],
                example: "swift build && swift-fuzz --target \(target)",
                relatedCommands: [
                    "swift package describe --type json",
                    "swift build --show-bin-path"
                ]
            )
            try UserInterface.reportError(friendlyError)
        } catch {
            // Handle any other unexpected errors
            let friendlyError = UserFriendlyError(
                title: "Unexpected error occurred",
                description: "SwiftFuzzer encountered an unexpected error: \(error)",
                possibleCauses: [
                    "Internal tool error",
                    "System resource issue",
                    "Unsupported configuration"
                ],
                solutions: [
                    "Try running the command again",
                    "Check system resources (disk space, memory)",
                    "Report this issue with the full error message"
                ],
                example: nil,
                relatedCommands: [
                    "df -h  # Check disk space",
                    "swift --version  # Check Swift version"
                ]
            )
            try UserInterface.reportError(friendlyError)
        }
    }
}
