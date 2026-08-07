//
//  DispatchMode.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

enum DispatchMode: Sendable {
    case awaited
    case unawaited

    var isUnawaited: Bool { self == .unawaited }
}
