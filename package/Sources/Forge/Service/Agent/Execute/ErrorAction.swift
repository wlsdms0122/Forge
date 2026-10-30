//
//  ErrorAction.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

enum ErrorAction: Sendable {
    case propagate
    case substitute(BackendResponse)
}
