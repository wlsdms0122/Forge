//
//  JSONValue+Output.swift
//  ForgeCLI
//
//  Created by JSilver on 10/25/26.
//

import Foundation
import Forge

extension JSONValue {
    func printJSON() {
        if
            let data = try? JSONSerialization.data(
                withJSONObject: jsonObject,
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
    func printResult(json: Bool) {
        if json {
            printJSON()
        } else {
            print(resultText)
        }
    }
}
