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

            Schedules are daemon state, one file each under
            state_directory/schedule/, written by `create` and removed by
            `delete`. A repeating schedule stands until it is deleted; a
            one-shot is removed once it has fired.
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
