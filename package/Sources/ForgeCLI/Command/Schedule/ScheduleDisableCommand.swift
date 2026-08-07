//
//  ScheduleDisableCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct ScheduleDisableCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "disable",
        abstract: "Disable a schedule."
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Schedule id.")
    var id: String
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let socketPath = try resolveSocket(global)
        setScheduleEnabled(
            socketPath,
            id: id,
            enabled: false,
            token: resolveToken(global.token),
            json: json
        )
    }
    
    // MARK: - Private
}
