//
//  ForgeError.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// An error a client meets: its type and message, and the fields the wire
// carries beside them. Printed, it is its message.
protocol ForgeError: Error, Sendable, CustomStringConvertible {
    var message: String { get }
    var wireType: String { get }
    var wireDetails: [String: JSONValue] { get }
}

extension ForgeError {
    var description: String { message }

    var wireType: String { String(describing: type(of: self)) }

    var wireDetails: [String: JSONValue] { [:] }
}
