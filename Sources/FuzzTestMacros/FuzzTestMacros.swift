import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftCompilerPlugin
import Foundation

/// Macro that registers a function for fuzzing and modifies the function to include registration
public struct FuzzTestMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        
        // Ensure this is applied to a function
        guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
            throw FuzzTestError.onlyApplicableToFunction
        }
        
        // Get function name
        let funcName = funcDecl.name.text
        
        // Validate function signature - should take Data parameter
        guard let firstParam = funcDecl.signature.parameterClause.parameters.first else {
            throw FuzzTestError.functionMustTakeDataParameter
        }
        
        // Check if the parameter type contains "Data"
        let paramTypeString = firstParam.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard paramTypeString.contains("Data") else {
            throw FuzzTestError.functionMustTakeDataParameter
        }
        
        let className = "__FuzzTestRegistrator_\(funcName)"
        
        let registrationClass = DeclSyntax("""
        @objc
        private class \(raw: className): NSObject {
            @objc static func register() {
                FuzzTestRegistry.register(name: "\(raw: funcName)", function: \(raw: funcName))
            }
        }
        """);
        
        return [registrationClass]
    }
}

enum FuzzTestError: Error, CustomStringConvertible {
    case onlyApplicableToFunction
    case functionMustTakeDataParameter
    
    var description: String {
        switch self {
        case .onlyApplicableToFunction:
            return "@fuzzTest can only be applied to functions"
        case .functionMustTakeDataParameter:
            return "@fuzzTest functions must take a Data parameter as their first argument"
        }
    }
}

extension FuzzTestError: DiagnosticMessage {
    var severity: DiagnosticSeverity { .error }
    
    var message: String { description }
    
    var diagnosticID: MessageID {
        switch self {
        case .onlyApplicableToFunction:
            return MessageID(domain: "FuzzTestMacro", id: "onlyApplicableToFunction")
        case .functionMustTakeDataParameter:
            return MessageID(domain: "FuzzTestMacro", id: "functionMustTakeDataParameter")
        }
    }
}

@main
struct FuzzTestPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        FuzzTestMacro.self
    ]
}