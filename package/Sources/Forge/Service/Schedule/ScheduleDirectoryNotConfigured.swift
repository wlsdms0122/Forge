//
//  ScheduleDirectoryNotConfigured.swift
//  Forge
//
//  Created by JSilver on 10/25/26.
//

import Foundation

// The daemon has no runtime schedule directory, so it creates no schedule.
struct ScheduleDirectoryNotConfigured: ForgeError {
    // MARK: - Property
    let message: String

    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }

    // MARK: - Public
    // MARK: - Private
}
