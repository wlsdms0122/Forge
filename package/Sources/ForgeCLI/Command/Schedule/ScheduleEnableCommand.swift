//
//  ScheduleEnableCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct ScheduleEnableCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "enable",
        abstract: "Enable a schedule."
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
            enabled: true,
            token: resolveToken(global.token),
            json: json
        )
    }
    
    // MARK: - Private
}
