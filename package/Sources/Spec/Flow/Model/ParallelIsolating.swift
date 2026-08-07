//
//  ParallelIsolating.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// The parallel boundary is also an isolation boundary for the host: ambient
// state the host carries on the task (task locals like an open agent session)
// would otherwise leak into every child at once — concurrent siblings sharing
// one conversation. A host environment that declares this protocol gets each
// child body handed through `isolateParallelChild`, where it can sever or fork
// that ambient state. The kernel stays ignorant of what the state is.
public protocol ParallelIsolating: Sendable {
    func isolateParallelChild<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async throws -> T
}
