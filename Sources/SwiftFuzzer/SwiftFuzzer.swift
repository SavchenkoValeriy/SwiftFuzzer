// Sources/SwiftFuzzer/SwiftFuzzer.swift
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
            print("Error: \(error.message)")
            throw ExitCode.failure
        }
    }
}