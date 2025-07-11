import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftCompilerPlugin
import Foundation

/// Macro that registers a function for fuzzing and creates appropriate adapter
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
        
        let className = "__FuzzTestRegistrator_\(funcName)"
        
        // Analyze function parameters to determine registration approach
        let parameters = funcDecl.signature.parameterClause.parameters
        
        // Fuzz tests must have at least one parameter
        guard !parameters.isEmpty else {
            throw FuzzTestError.functionMustHaveParameters
        }
        
        // Extract parameter labels for proper Swift FQN
        let parameterSignatures = parameters.map { param in
            // firstName is non-optional TokenSyntax, so access .text directly
            let label = param.firstName.text
            return "\(label):"
        }
        
        // Create proper Swift FQN: functionName(label1:label2:...)
        let fqn = "\(funcName)(\(parameterSignatures.joined(separator: "")))"
        
        // Generate registration code with FQN for hash-based dispatch
        let registrationCode = "FuzzTestRegistry.register(fqn: \"\(fqn)\", adapter: FuzzerAdapter(\(funcName)))"
        
        let registrationClass = DeclSyntax("""
        @objc
        private class \(raw: className): NSObject {
            @objc static func register() {
                \(raw: registrationCode)
            }
        }
        """);
        
        return [registrationClass]
    }
}

enum FuzzTestError: Error, CustomStringConvertible {
    case onlyApplicableToFunction
    case functionMustHaveParameters
    
    var description: String {
        switch self {
        case .onlyApplicableToFunction:
            return "@fuzzTest can only be applied to functions"
        case .functionMustHaveParameters:
            return "@fuzzTest functions must have at least one parameter"
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
        case .functionMustHaveParameters:
            return MessageID(domain: "FuzzTestMacro", id: "functionMustHaveParameters")
        }
    }
}

@main
struct FuzzTestPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        FuzzTestMacro.self
    ]
}