//
//  CommandAuthorizationPolicy.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct CommandAuthorizationPolicy: Sendable, Equatable {
    enum Decision: Sendable, Equatable {
        case allowed(argv: [String])
        case denied(reason: String)
    }
    
    struct TokenizeError: ForgeError {
        var message: String { "tool command tokenization failed (unbalanced quote/escape)" }
    }
    
    struct DetailedToken {
        // MARK: - Property
        let text: String
        let quoted: Bool
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    private enum DelegatedArguments {
        case arguments([String])
        case invalid(String)
        case notDelegated
    }
    
    // MARK: - Property
    private let allowedPatterns: [CommandPattern]?
    
    var isEmpty: Bool { allowedPatterns?.isEmpty == true }
    
    // MARK: - Initializer
    init(allowed: [CommandPattern]?) {
        self.allowedPatterns = allowed
    }
    
    // MARK: - Public
    static func tokenize(_ command: String) throws -> [String] {
        try tokenizeDetailed(command).map(\.text)
    }
    
    static func tokenizeDetailed(_ command: String) throws -> [DetailedToken] {
        enum Quote {
            case none
            case single
            case double
        }
        
        var tokens: [DetailedToken] = []
        var currentToken = ""
        var hasCurrentToken = false
        var currentQuoted = false
        var quote: Quote = .none
        var index = command.startIndex
        
        while index < command.endIndex {
            let character = command[index]
            
            switch quote {
            case .none:
                if character == " " || character == "\t" || character.isNewline {
                    if hasCurrentToken {
                        tokens.append(DetailedToken(text: currentToken, quoted: currentQuoted))
                        currentToken = ""
                        hasCurrentToken = false
                        currentQuoted = false
                    }
                } else if character == "'" {
                    quote = .single
                    hasCurrentToken = true
                    currentQuoted = true
                } else if character == "\"" {
                    quote = .double
                    hasCurrentToken = true
                    currentQuoted = true
                } else if character == "\\" {
                    let nextIndex = command.index(after: index)
                    
                    guard nextIndex < command.endIndex else { throw TokenizeError() }
                    
                    currentToken.append(command[nextIndex])
                    hasCurrentToken = true
                    currentQuoted = true
                    index = nextIndex
                } else {
                    currentToken.append(character)
                    hasCurrentToken = true
                }
            
            case .single:
                if character == "'" {
                    quote = .none
                } else {
                    currentToken.append(character)
                }
            
            case .double:
                if character == "\"" {
                    quote = .none
                } else if character == "\\" {
                    let nextIndex = command.index(after: index)
                    
                    guard nextIndex < command.endIndex else { throw TokenizeError() }
                    
                    let nextCharacter = command[nextIndex]
                    
                    if nextCharacter == "\"" || nextCharacter == "\\" {
                        currentToken.append(nextCharacter)
                    } else {
                        currentToken.append(character)
                        currentToken.append(nextCharacter)
                    }
                    
                    index = nextIndex
                } else {
                    currentToken.append(character)
                }
            }
            
            index = command.index(after: index)
        }
        
        guard quote == .none else { throw TokenizeError() }
        
        if hasCurrentToken {
            tokens.append(DetailedToken(text: currentToken, quoted: currentQuoted))
        }
        
        return tokens
    }
    
    func authorize(argv: [String]) -> Decision {
        guard !argv.isEmpty else { return .denied(reason: "empty command") }
        
        guard !Self.isEnvironmentAssignment(argv[0]) else {
            return .denied(
                reason: "leading environment assignments must be declared in the agent environment"
            )
        }
        
        guard let allowedPatterns else { return .allowed(argv: argv) }
        
        for pattern in allowedPatterns where pattern.matches(argv) {
            return .allowed(argv: argv)
        }
        
        switch Self.delegatedArguments(argv) {
        case .arguments(let delegatedArguments):
            switch authorize(argv: delegatedArguments) {
            case .allowed:
                return .allowed(argv: argv)
            
            case .denied(let reason):
                return .denied(reason: reason)
            }
        
        case .invalid(let reason):
            return .denied(reason: reason)
        
        case .notDelegated:
            return .denied(reason: "no command tool declaration matched")
        }
    }
    
    // MARK: - Private
    private static func delegatedArguments(_ arguments: [String]) -> DelegatedArguments {
        let executable = (arguments[0] as NSString).lastPathComponent
        var index = 1
        
        switch executable {
        case "env":
            if index < arguments.count, arguments[index] == "--" { index += 1 }
            
            if index < arguments.count, arguments[index].hasPrefix("-") {
                return .invalid("env options are outside a command tool declaration")
            }
            
            if index < arguments.count, isEnvironmentAssignment(arguments[index]) {
                return .invalid(
                    "environment assignments must be declared in the agent environment"
                )
            }
        
        case "command", "exec":
            if index < arguments.count, arguments[index] == "--" { index += 1 }
            
            if index < arguments.count, arguments[index].hasPrefix("-") {
                return .invalid(
                    "command launcher options are outside a command tool declaration"
                )
            }
        
        default:
            return .notDelegated
        }
        
        guard index < arguments.count else {
            return .invalid("command launcher requires an executable")
        }
        
        return .arguments(Array(arguments[index...]))
    }
    
    private static func isEnvironmentAssignment(_ token: String) -> Bool {
        guard let equal = token.firstIndex(of: "=") else { return false }
        
        let name = token[..<equal]
        
        guard let first = name.first, first == "_" || first.isLetter else { return false }
        
        return name.dropFirst().allSatisfy { character in
            character == "_" || character.isLetter || character.isNumber
        }
    }
}
