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
    func emit(_ object: JSONObject) async {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: object.dict,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
        else {
            return
        }

        await connection.send(data + Data([0x0a]))
    }

    // MARK: - Private
}
