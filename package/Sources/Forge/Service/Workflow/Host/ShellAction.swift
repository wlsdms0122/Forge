//
//  ShellAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Spec

struct ShellAction: Spec.Action {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case command
        case cwd
        case env
        case stdin
        case outputs
        case timeout
    }

    // MARK: - Property
    static let key = "shell"

    let command: [Spec.Reference]
    let cwd: Spec.Reference?
    let env: [String: Spec.Reference]?
    let stdin: Spec.Reference?
    let outputs: [String: OutputSpec]?
    let timeout: Double?

    var referencedPaths: [[PathSegment]] {
        command.flatMap(\.referencedPaths)
            + (cwd?.referencedPaths ?? [])
            + (env?.values.flatMap(\.referencedPaths) ?? [])
            + (stdin?.referencedPaths ?? [])
    }

    // MARK: - Initializer
    // The invariants live on the one designated initializer — however a value is
    // constructed, decoded or programmatic, the same rules hold.
    init(
        command: [Spec.Reference],
        cwd: Spec.Reference? = nil,
        env: [String: Spec.Reference]? = nil,
        stdin: Spec.Reference? = nil,
        outputs: [String: OutputSpec]? = nil,
        timeout: Double? = nil
    ) throws {
        guard !command.isEmpty else {
            throw ValidationError("shell.command is empty")
        }

        self.command = command
        self.cwd = cwd
        self.env = env
        self.stdin = stdin
        self.outputs = outputs
        self.timeout = timeout
    }

    init(from decoder: Decoder) throws {
        try Spec.KeyGate.rejectUnknownKeys(in: decoder, known: CodingKeys.self, context: "shell")

        let container = try decoder.container(keyedBy: CodingKeys.self)

        do {
            try self.init(
                command: try container.decode([Spec.Reference].self, forKey: .command),
                cwd: try container.decodeIfPresent(Spec.Reference.self, forKey: .cwd),
                env: try container.decodeIfPresent(
                    [String: Spec.Reference].self,
                    forKey: .env
                ),
                stdin: try container.decodeIfPresent(Spec.Reference.self, forKey: .stdin),
                outputs: try container.decodeIfPresent(
                    [String: OutputSpec].self,
                    forKey: .outputs
                ),
                timeout: try container.decodeIfPresent(Double.self, forKey: .timeout)
            )
        } catch let error as ValidationError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: container.codingPath, debugDescription: "\(error)")
            )
        }
    }

    // MARK: - Public
    func run(_ context: ActionContext) async throws -> Spec.Value {
        let host = try ForgeHost.from(context)
        let resolver = context.resolver
        let arguments = try command.map { reference in try resolver.string(reference) }
        let cwd = try cwd.map { reference in try resolver.string(reference) }
        let env = try (env ?? [:]).mapValues { reference in try resolver.string(reference) }
        let stdin = try stdin.map { reference in try resolver.string(reference) }
        let declarations = outputs
        let stepID = context.stepID

        let result = try await host.withStepSlot {
            try await withHostDeadline(seconds: timeout) {
                try await host.shell.run(
                    executable: arguments[0],
                    args: Array(arguments.dropFirst()),
                    cwd: cwd,
                    env: env,
                    stdin: stdin,
                    stepID: stepID
                )
            }
        }

        guard result.exitCode == 0 else {
            let trimmed = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = trimmed.isEmpty
                ? String(result.stdout.suffix(300))
                : String(trimmed.prefix(300))

            throw BackendNonzeroExit(
                "shell exit \(result.exitCode): \(detail)",
                exitCode: result.exitCode,
                stderr: result.stderr,
                stdout: result.stdout
            )
        }

        let extracted = try OutputExtractor.resolve(
            stdout: result.stdout,
            declarations: declarations
        )

        return ValueBridge.value(extracted)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(cwd, forKey: .cwd)
        try container.encodeIfPresent(env, forKey: .env)
        try container.encodeIfPresent(stdin, forKey: .stdin)
        try container.encodeIfPresent(outputs, forKey: .outputs)
        try container.encodeIfPresent(timeout, forKey: .timeout)
    }

    // MARK: - Private
}
