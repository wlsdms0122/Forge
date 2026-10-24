//
//  Weekday.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

enum Weekday: String, Sendable, Codable, CaseIterable, Equatable {
    case sun
    case mon
    case tue
    case wed
    case thu
    case fri
    case sat
    
    init?(calendarWeekday weekday: Int) {
        switch weekday {
        case 1: self = .sun
        case 2: self = .mon
        case 3: self = .tue
        case 4: self = .wed
        case 5: self = .thu
        case 6: self = .fri
        case 7: self = .sat
        default: return nil
        }
    }
}
