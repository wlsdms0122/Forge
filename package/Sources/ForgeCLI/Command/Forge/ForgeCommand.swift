//
//  ForgeCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Forge
import Foundation

@main
struct ForgeCommand: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "forge",
        abstract: "Forge — LLM invocation daemon and its client, in one binary.",
        discussion: """
            forge has two faces in one executable:

                forge serve   run the daemon — LLM backends, workflow
                              execution, schedules, the ACL gate for nested
                              dispatch. long-running.
                forge workflow / schedule / service /
                forge status / policy / token
                              client subcommands. speak line-delimited
                              JSON-RPC over the daemon's Unix socket — the
                              single surface for using forge. nothing else
                              opens the socket directly.

            The client side serves both workflow subprocesses (LLM agents,
            shell steps) and operators at a terminal. Every RPC carries a
            daemon-signed bearer token, supplied as input — the `--token`
            option or the FORGE_ACCESS_TOKEN environment variable. forge
            never mints one on your behalf: a workflow subprocess receives
            FORGE_ACCESS_TOKEN at spawn, an operator obtains one explicitly
            with `token issue`. `token issue` itself requires a token and mints
            under attenuation; the first token comes from the daemon's boot fd
            handed to its launcher (FORGE_BOOTSTRAP_FD).

            SOCKET DISCOVERY
                The socket is <instanceHome>/forged.sock, where instanceHome =
                <XDG_CONFIG_HOME|~/.config>/forge/<instance> and instance =
                --instance > FORGE_INSTANCE > "default". serve binds it; a client
                falls back to it but honors FORGE_SOCKET first (a spawned child
                reaches its exact daemon). The client never reads config;
                config (--config) is a `serve`-only input.

            ENVIRONMENT
                FORGE_INSTANCE          default instance name when --instance is
                                        omitted — selects which daemon socket.
                FORGE_SOCKET            exact socket path for a client to connect
                                        (skips instance derivation). Injected into
                                        spawned subprocesses by the daemon.
                FORGE_ACCESS_TOKEN      daemon-signed bearer token carried on
                                        every RPC. Injected into workflow
                                        subprocesses at spawn; set it
                                        yourself (or pass --token) for
                                        operator use. `token issue` mints it.

            EXIT STATUS
                0   Success.
                1   The command itself failed: `serve` could not boot (config
                    included), `service register` could not register or lost
                    the daemon, `policy check` denied, `workflow check` found
                    a failing file.
                4   The request could not be formed: a missing token, a bad
                    JSON option, conflicting flags, an unusable instance or
                    socket path.
                5   The call failed: the daemon returned an RPC error or could
                    not be reached, or `service describe` named a service that
                    is not registered.
                6   RPC rejected for a stale or invalid token. Reissue it.
                64  Argument parse error.
            """,
        version: Version.current,
        subcommands: [
            ServeCommand.self,
            WorkflowCommand.self,
            ScheduleCommand.self,
            JobCommand.self,
            ResourceCommand.self,
            ServiceCommand.self,
            StatusCommand.self,
            PolicyCommand.self,
            TokenCommand.self
        ]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
