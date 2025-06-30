import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import MacroTesting
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(FuzzTestMacros)
import FuzzTestMacros

let testMacros: [String: Macro.Type] = [
    "fuzzTest": FuzzTestMacro.self,
]
#endif

final class FuzzTestMacroTests: XCTestCase {
    
    override func invokeTest() {
        #if canImport(FuzzTestMacros)
        withMacroTesting(
            macros: [
                "fuzzTest": FuzzTestMacro.self
            ]
        ) {
            super.invokeTest()
        }
        #else
        super.invokeTest()
        #endif
    }
    
    func testFuzzTestMacroWithValidFunction() throws {
        #if canImport(FuzzTestMacros)
        assertMacro {
            """
            @fuzzTest
            func parseData(_ data: Data) -> Bool {
                return true
            }
            """
        } expansion: {
            """
            func parseData(_ data: Data) -> Bool {
                return true
            }
            
            @objc
            private class __FuzzTestRegistrator_parseData: NSObject {
                @objc static func register() {
                    FuzzTestRegistry.register(name: "parseData", function: parseData)
                }
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testFuzzTestMacroWithDataParameter() throws {
        #if canImport(FuzzTestMacros)
        assertMacro {
            """
            @fuzzTest
            func processInput(_ inputData: Data) {
                // Process input
            }
            """
        } expansion: {
            """
            func processInput(_ inputData: Data) {
                // Process input
            }
            
            @objc
            private class __FuzzTestRegistrator_processInput: NSObject {
                @objc static func register() {
                    FuzzTestRegistry.register(name: "processInput", function: processInput)
                }
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testFuzzTestMacroWithOptionalDataParameter() throws {
        #if canImport(FuzzTestMacros)
        assertMacro {
            """
            @fuzzTest
            func handleOptionalData(_ data: Data?) -> String {
                return "result"
            }
            """
        } expansion: {
            """
            func handleOptionalData(_ data: Data?) -> String {
                return "result"
            }
            
            @objc
            private class __FuzzTestRegistrator_handleOptionalData: NSObject {
                @objc static func register() {
                    FuzzTestRegistry.register(name: "handleOptionalData", function: handleOptionalData)
                }
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testFuzzTestMacroFailsOnNonFunction() throws {
        #if canImport(FuzzTestMacros)
        assertMacro {
            """
            @fuzzTest
            var testVariable = 42
            """
        } diagnostics: {
            """
            @fuzzTest
            ┬────────
            ╰─ 🛑 @fuzzTest can only be applied to functions
            var testVariable = 42
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testFuzzTestMacroFailsOnFunctionWithoutDataParameter() throws {
        #if canImport(FuzzTestMacros)
        assertMacro {
            """
            @fuzzTest
            func invalidFunction(input: String) -> Bool {
                return true
            }
            """
        } diagnostics: {
            """
            @fuzzTest
            ┬────────
            ╰─ 🛑 @fuzzTest functions must take a Data parameter as their first argument
            func invalidFunction(input: String) -> Bool {
                return true
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testFuzzTestMacroFailsOnFunctionWithNoParameters() throws {
        #if canImport(FuzzTestMacros)
        assertMacro {
            """
            @fuzzTest
            func noParametersFunction() -> Bool {
                return true
            }
            """
        } diagnostics: {
            """
            @fuzzTest
            ┬────────
            ╰─ 🛑 @fuzzTest functions must take a Data parameter as their first argument
            func noParametersFunction() -> Bool {
                return true
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testFuzzTestMacroWithComplexFunctionName() throws {
        #if canImport(FuzzTestMacros)
        assertMacro {
            """
            @fuzzTest
            func parseJSONWithComplexValidation(_ data: Data) throws -> [String: Any] {
                return [:]
            }
            """
        } expansion: {
            """
            func parseJSONWithComplexValidation(_ data: Data) throws -> [String: Any] {
                return [:]
            }
            
            @objc
            private class __FuzzTestRegistrator_parseJSONWithComplexValidation: NSObject {
                @objc static func register() {
                    FuzzTestRegistry.register(name: "parseJSONWithComplexValidation", function: parseJSONWithComplexValidation)
                }
            }
            """
        }
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
