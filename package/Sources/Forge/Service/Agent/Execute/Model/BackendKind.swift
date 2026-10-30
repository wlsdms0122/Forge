//
//  BackendKind.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// The backends a provider's `kind` can name in `config.toml`.
package enum BackendKind: String, CaseIterable, Sendable {
    case claudeCLI = "claude-cli"
    case codexCLI = "codex-cli"
    case openAICompatible = "openai-compat"
}
