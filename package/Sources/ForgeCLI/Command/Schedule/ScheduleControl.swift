//
//  ScheduleControl.swift
//  ForgeCLI
//
//  Created by JSilver on 8/11/26.
//

import Foundation

func setScheduleEnabled(
    _ socketPath: String,
    id: String,
    enabled: Bool,
    token: String,
    json: Bool
) {
    switch callRPC(
        socketPath: socketPath,
        method: "schedule.set_enabled",
        params: ["id": id, "enabled": enabled],
        token: token
    ) {
    case .ok(let dict):
        if json { printJSON(dict) } else { print(renderResultPlain(dict)) }
    
    case .err(let type, let message):
        dieRPC("schedule \(enabled ? "enable" : "disable")", type: type, message: message)
    }
}
