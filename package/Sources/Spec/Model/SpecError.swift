//
//  SpecError.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public protocol SpecError: Error, Sendable, CustomStringConvertible {
    var message: String { get }
}

public extension SpecError {
    var description: String { message }
}
