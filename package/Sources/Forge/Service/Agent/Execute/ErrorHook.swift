//
//  ErrorHook.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

protocol ErrorHook: Sendable {
    var name: String { get }

    func onError(_ invocation: Invocation, _ error: any Error) async -> ErrorAction
}
