//
//  JSONValue+Testing.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

@testable import Forge

/// Accessors that extract a single case.
///
/// Most assertions are one sentence — "this value is an object and this key inside it is
/// such-and-such" — but unpacked with `guard case` they become four lines
/// (+`Issue.record`+`return`) with a hand-written failure message. Narrowed to an optional
/// and fed to `try #require`, they shrink to one line, and the macro records which line
/// failed and what it wasn't.
extension JSONValue {
    // MARK: - Public
    var objectValue: [String: JSONValue]? {
        guard case .object(let object) = self else { return nil }

        return object
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let array) = self else { return nil }

        return array
    }

    var stringValue: String? {
        guard case .string(let string) = self else { return nil }

        return string
    }

    var intValue: Int? {
        guard case .int(let number) = self else { return nil }

        return number
    }

    var doubleValue: Double? {
        guard case .double(let number) = self else { return nil }

        return number
    }

    var boolValue: Bool? {
        guard case .bool(let flag) = self else { return nil }

        return flag
    }
}
