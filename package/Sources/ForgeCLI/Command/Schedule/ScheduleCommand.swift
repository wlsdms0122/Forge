//
//  ScheduleCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
//

import ArgumentParser
import Foundation

struct ScheduleCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "schedule",
        abstract: "Inspect, create, and toggle workflow schedules.",
        discussion: """
            Schedules fire a workflow on a trigger. Repeating: `--every`
            interval or `--at` wall-clock, forever. One-shot: `--once`
            wall-clock or `--after` relative delay, fired exactly once. A
            single surface covers both repeating and one-shot.

            Definitions live in two directories — an operational split, not a
            domain tier:

                config     schedule_directory/*.yaml — hand-authored. The daemon's
                           autonomous machinery never mutates these.
                runtime    runtime_directory/schedule/*.yaml — created via `create`,
                           daemon-owned.

            `create` writes to the runtime dir. `delete` and enable/disable act
            on any schedule regardless of origin; hand-authored config files are
            usually edited directly.
            """,
        subcommands: [
            ScheduleListCommand.self,
            ScheduleCreateCommand.self,
            ScheduleDeleteCommand.self,
            ScheduleEnableCommand.self,
            ScheduleDisableCommand.self,
        ]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
