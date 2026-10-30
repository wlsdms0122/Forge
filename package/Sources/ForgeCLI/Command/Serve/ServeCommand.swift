//
//  ServeCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
//

import ArgumentParser
import Foundation
import Forge

struct ServeCommand: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Run the LLM invocation daemon over a Unix socket.",
        discussion: """
            `forge serve` runs a long-running supervisor that owns LLM
            backends (e.g. claude), workflow execution, schedules, and the
            ACL gate for nested dispatch. Clients (admin, runner, agent
            subprocesses) talk to it via line-delimited JSON-RPC over a
            Unix socket.

            SOCKET DISCOVERY (clients compute the same path — config-free)
                serve binds <instanceHome>/forged.sock, where instanceHome =
                <XDG_CONFIG_HOME|~/.config>/forge/<instance> and instance =
                --instance > FORGE_INSTANCE > "default". The socket is determined
                purely by the instance — NOT a config key, not overridable; config
                (`--config`) only locates the daemon's settings/data. Refuses to
                start if a live daemon already holds the socket.

            CONFIG PRECEDENCE (serve only — clients never read config)
                --config flag > <instanceHome>/config.toml > FORGE_* env > defaults.
                env only fills keys left silent by toml (emergency override).
                PATH ANCHORING: a relative path written in the toml resolves
                against the toml's directory; unspecified catalogs/logs default
                under instanceHome. runtime·socket are instance-owned.

            CONFIG SCHEMA (everything optional — convention defaults shown)
                [directory]  catalog roots default to `<instanceHome>/<key>`
                        (workflow · schedule · resource · policy); a
                        relative value resolves against the toml's directory.
                        (runtime is instance-owned at `<instanceHome>/runtime` —
                        not configurable.)
                [log]   jsonl · error · maximum_bytes (default 50 MiB). Default under
                        `<instanceHome>/log`.
                [pool]  maximum_concurrent_steps (default 4) — leaf-step concurrency cap.
                        maximum_active_runs (default 256) — concurrent registered-run cap.
                [provider.<name>]   configured backends; `kind` = \(BackendKind.allCases.map(\.rawValue).joined(separator: "|")).
                        CLI kinds take `executable` (default: the CLI on PATH);
                        openai-compat requires `endpoint`. A provider without a known
                        kind or a required setting is skipped with a warning.
                        Silent → a single `claude` (claude-cli) default. Declaring any
                        drops that default, so list `claude` explicitly alongside others.
                        Secrets via env FORGE_PROVIDER_<NAME>_API_KEY only.
                [service.<name>]    managed child processes (no default; must be declared):
                        command (argv, required) · working_directory · environment · auto_spawn · log_file ·
                        restart_backoff_initial_milliseconds · restart_backoff_maximum_milliseconds · restart_crash_loop_limit.
                [hooks] logging (default true).
                Inspect the resolved values + their source with `forge status`.

            STATE FILES
                <instanceHome>/forged.sock      Unix socket (RPC entry).
                <instanceHome>/runtime.json     self-record (pid, instance, socket,
                                               resolved paths). Written on boot,
                                               deleted on clean shutdown — a
                                               down/crashed-daemon diagnostic
                                               (clients discover via instance, not this).
                <runtime_directory>/                 jobs · scratch · service/schedule state.
                <log_jsonl>                    structured JSONL event log.
                <error_log>                    stderr / traceback log.

            RPC METHODS
                Every method — its params, result shape, and the token it
                demands — is written in document/API.md §"RPC methods". The
                client subcommands (`forge workflow`, `schedule`, `job`,
                `resource`, `policy`, `token`, `service`, `status`) cover
                the same surface from a terminal.

            SIGNALS
                SIGINT, SIGTERM    graceful shutdown (drains in-flight RPCs).

            EXIT STATUS
                0   Clean shutdown.
                1   Boot failure (config load, socket bind, etc.).
                2   Argument parse error.
            """
    )
    
    @Option(
        name: [.short, .long],
        help: "Path to config.toml (default: <instanceHome>/config.toml)."
    )
    var config: String?
    
    @Option(
        help: "Instance name — binds the socket at <XDG_CONFIG_HOME|~/.config>/forge/<name>/ (default: default)."
    )
    var instance: String?
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        do {
            try await Server.run(configPath: config, instance: instance)
        } catch {
            FileHandle.standardError.write(Data("forge serve: \(error)\n".utf8))
            
            throw ExitCode(1)
        }
    }
    
    // MARK: - Private
}
