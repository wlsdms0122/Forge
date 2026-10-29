//
//  Diagnostics.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum Diagnostics {
    static func lastLine(_ stdout: String) -> String {
        Lines.nonEmpty(stdout)
            .last(where: { line in !line.trimmingCharacters(in: .whitespaces).isEmpty })
            .map { line in line.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    }
    
    static func stdoutTail(_ stdout: String, limit: Int = 500) -> String {
        String(lastLine(stdout).prefix(limit))
    }
}
