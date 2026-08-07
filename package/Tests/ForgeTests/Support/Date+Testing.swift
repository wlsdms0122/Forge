//
//  Date+Testing.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

extension Date {
    /// A timestamp whose value plays no part in the verdict but must exist as an argument.
    ///
    /// Passing `Date()` forces every reader to check whether the timestamp changes the outcome.
    /// A fixed value removes that question — tests where the timestamp does matter build their own.
    static let fixture = Date(timeIntervalSince1970: 1_700_000_000)
}
