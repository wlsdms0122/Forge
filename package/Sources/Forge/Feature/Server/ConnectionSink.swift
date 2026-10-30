//
//  ConnectionSink.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

struct ConnectionSink: EventSink {
    // MARK: - Property
    private let connection: Connection

    // MARK: - Initializer
    init(connection: Connection) {
        self.connection = connection
    }

    // MARK: - Public
    func emit(_ frame: JSONValue) async {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: frame.jsonObject,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
        else {
            return
        }

        await connection.send(data + Data([0x0a]))
    }

    // MARK: - Private
}
