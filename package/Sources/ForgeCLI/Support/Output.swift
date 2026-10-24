//
//  Output.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
//

import Foundation

func die(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data(("forge: " + message + "\n").utf8))
    exit(code)
}
