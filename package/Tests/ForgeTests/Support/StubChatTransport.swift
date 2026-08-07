//
//  StubChatTransport.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
@testable import Forge

actor StubChatTransport: ChatTransport {
    private var scripted: [ChatCompletion]
    private(set) var callCount = 0
    private(set) var lastMessages: [ChatMessage] = []
    private(set) var lastModel: String?
    init(_ scripted: [ChatCompletion]) { self.scripted = scripted }
    func complete(
        messages: [ChatMessage], tools: [ToolSpec], model: String?,
        jsonMode: Bool
    ) async throws -> ChatCompletion {
        callCount += 1
        lastMessages = messages
        lastModel = model
        if scripted.count > 1 { return scripted.removeFirst() }
        
        return scripted.first ?? ChatCompletion(text: "")
    }
}
