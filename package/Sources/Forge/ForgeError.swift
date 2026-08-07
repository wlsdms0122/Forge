//
//  ForgeError.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

protocol ForgeError: Error, Sendable {
    var message: String { get }
    var wireType: String { get }
}

extension ForgeError {
    var wireType: String { String(describing: type(of: self)) }
}
