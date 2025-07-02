import Foundation
import FuzzTest

// Simple CLI app that processes strings
func processInput(_ input: String) -> String {
    if input.hasPrefix("crash") {
        // Potential crash scenario for testing
        return String(input.dropFirst(5).reversed())
    } else if input.hasPrefix("json") {
        // JSON parsing scenario
        let jsonString = String(input.dropFirst(4))
        if let data = jsonString.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data),
           let dict = parsed as? [String: Any] {
            return "Parsed: \(dict.keys.joined(separator: ", "))"
        }
        return "Invalid JSON"
    }
    return input.uppercased()
}

// CLI argument parsing
func parseArguments(_ args: [String]) -> String {
    guard args.count > 1 else {
        return "Usage: ExecutableApp <input>"
    }
    
    let input = args.dropFirst().joined(separator: " ")
    return processInput(input)
}

// Fuzz tests for the executable
@fuzzTest
func fuzzProcessInput(_ data: Data) {
    guard let input = String(data: data, encoding: .utf8) else { return }
    let _ = processInput(input)
}

@fuzzTest 
func fuzzArgumentParsing(_ data: Data) {
    guard let input = String(data: data, encoding: .utf8) else { return }
    let args = ["ExecutableApp"] + input.components(separatedBy: " ")
    let _ = parseArguments(args)
}

@fuzzTest
func fuzzJSONProcessing(_ data: Data) {
    let input = "json" + (String(data: data, encoding: .utf8) ?? "")
    let _ = processInput(input)
}

// Main entry point function - needed because SwiftFuzzer uses -parse-as-library
func main() {
    let result = parseArguments(CommandLine.arguments)
    print(result)
}

// Call main - this works with -parse-as-library
main()