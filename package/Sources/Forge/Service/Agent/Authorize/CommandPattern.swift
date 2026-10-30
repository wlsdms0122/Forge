//
//  CommandPattern.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

struct CommandPattern: Sendable, Equatable, CustomStringConvertible {
    struct ValidationError: ForgeError {
        // MARK: - Property
        let message: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    let tokens: [String]
    
    var acceptsTrailingArguments: Bool { tokens.last == "*" }
    
    var fixedTokens: ArraySlice<String> {
        acceptsTrailingArguments ? tokens.dropLast() : tokens[...]
    }
    
    var description: String { tokens.joined(separator: " ") }
    
    // MARK: - Initializer
    init(tokens: [String]) throws {
        guard let executable = tokens.first, executable != "*" else {
            throw ValidationError(message: "command tool pattern must start with an executable")
        }
        
        guard !tokens.contains("") else {
            throw ValidationError(message: "command tool pattern must not contain empty tokens")
        }
        
        guard !tokens.dropLast().contains("*") else {
            throw ValidationError(message: "command tool '*' is only supported as the final token")
        }
        
        self.tokens = tokens
    }
    
    init(_ pattern: String) throws {
        let detailed: [CommandAuthorizationPolicy.DetailedToken]
        
        do {
            detailed = try CommandAuthorizationPolicy.tokenizeDetailed(pattern)
        } catch {
            throw ValidationError(message: "command tool pattern has an unbalanced quote or escape")
        }
        
        guard !detailed.contains(where: { token in token.text == "*" && token.quoted }) else {
            throw ValidationError(
                message: "command tool pattern cannot declare a quoted '*'"
                    + " — a literal-asterisk argument is indistinguishable from the trailing"
                    + " wildcard in this pattern grammar"
            )
        }
        
        try self.init(tokens: detailed.map(\.text))
    }
    
    // MARK: - Public
    func matches(_ arguments: [String]) -> Bool {
        let fixed = fixedTokens
        
        guard
            acceptsTrailingArguments
                ? arguments.count >= fixed.count
                : arguments.count == fixed.count
        else {
            return false
        }
        
        return zip(fixed, arguments).allSatisfy { pair in pair.0 == pair.1 }
    }
    
    // MARK: - Private
}

extension CommandPattern: Codable {
    init(from decoder: Decoder) throws {
        try self.init(tokens: [String](from: decoder))
    }
    
    func encode(to encoder: Encoder) throws {
        try tokens.encode(to: encoder)
    }
}
