//
//  EventSink.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

protocol EventSink: Sendable {
    func emit(_ object: JSONObject) async
}
