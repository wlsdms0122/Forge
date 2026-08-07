//
//  Lookup.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public enum Lookup: Sendable, Equatable {
    // Absence is an answer — a missing key, an out-of-range index, anything derived
    // from nothing. Shape misuse is a failure — drilling a field into a string, indexing
    // a number. Folding the two together disguises author typos as missing data, so the
    // walk keeps them apart and lets each consumer choose its policy.
    case found(Value)
    case absent
    case unfit(reason: String)
}
