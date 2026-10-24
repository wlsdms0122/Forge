//
//  Output.swift
//  ForgeCLI
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Forge

func printJSON(_ value: JSONValue) {
    if
        let data = try? JSONSerialization.data(
            withJSONObject: value.jsonObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
    }
}

// The default answer of a client command: the whole result, as JSON when the
// caller asked for it and as an indented tree otherwise. A command only writes
// its own renderer when the plain form would bury what the command is for.
func printResult(_ value: JSONValue, json: Bool) {
    if json {
        printJSON(value)
    } else {
        print(value.resultText)
    }
}

func die(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data(("forge: " + message + "\n").utf8))
    exit(code)
}
