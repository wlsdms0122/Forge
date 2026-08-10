//
//  JobCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
//

import ArgumentParser
import Foundation

struct JobCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "job",
        abstract: "Create and track work tickets (jobs) agents coordinate through.",
        discussion: """
            A job is a *work ticket*: durable shared data that carries a
            task's context across ephemeral agent sessions — distinct from a
            workflow (the action) and a run (one ephemeral execution). A ticket is
            a free-form canvas, NOT bound to any workflow — no declaration exists.
            Association is observed: when a run's session runs a ticket-targeting
            command (`job show <id>` / `job update <id>`), the daemon records the
            attachment. Several runs may attach to one ticket concurrently —
            mutations are field-level ops, append-safe, so no exclusive lock exists.

            The ticket records in two layers:
              - explicit (brief / refs / plan / comments): what agents deliberately
                write via `job update` — the free-form canvas and the handover the
                next session starts from. What a run did *inside* lives in the
                forge log (cross-reference by the run id in events).
              - system (events): the daemon's append-only lifecycle ledger — what a
                run *was* to this ticket (attached, completed, failed, orphaned).
                Daemon-written only; agents read it. Opening events always get
                closed (the boot scan closes dangling pairs as orphaned), so "is
                anything still open on this ticket" (`open`) is derived purely from
                events — no notification channel needed. (`open` is what the ledger
                asserts: an opening event with no terminal yet. Reading it as
                "alive now" additionally relies on the daemon-mediated query
                surface + the boot orphan scan.)

            Every mutation is stamped with the caller token's id (created_by /
            updated_by / comment `by`) — identity is minted by the daemon, never
            self-declared. `status` is a free string forge never interprets or
            writes; its vocabulary and transitions belong to the agents.
            """,
        subcommands: [
            JobCreateCommand.self,
            JobShowCommand.self,
            JobListCommand.self,
            JobUpdateCommand.self,
            JobDeleteCommand.self,
        ]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
