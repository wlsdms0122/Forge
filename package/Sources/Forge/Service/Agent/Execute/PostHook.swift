//
//  PostHook.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

protocol PostHook: Sendable {
    var name: String { get }

    func after(_ invocation: Invocation, _ response: BackendResponse) async
}
