//
//  Trigger.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum Trigger: Sendable, Equatable {
    case once(fireAt: Date, timezone: TimeZone)
    case every(Interval)
    case at(hour: Int, minute: Int, days: Set<Weekday>, timezone: TimeZone)
    
    var isOneShot: Bool {
        if case .once = self { return true }
        
        return false
    }
    
    func nextFire(after lastFired: Date?, now: Date) -> Date? {
        if let lastFired { return advance(after: lastFired) }
        
        return firstFire(now: now)
    }
    
    func firstFire(now: Date) -> Date? {
        switch self {
        case .once:
            return advance(after: .distantPast)
        
        case .every, .at:
            return advance(after: now)
        }
    }
    
    func advance(after moment: Date) -> Date? {
        switch self {
        case .once(let fireAt, _):
            return moment < fireAt ? fireAt : nil
        
        case .every(let interval):
            return moment.addingTimeInterval(Double(interval.seconds))
        
        case .at(let hour, let minute, let days, let timezone):
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timezone
            
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            components.second = 0
            
            var cursor = moment
            
            for _ in 0..<8 {
                guard
                    let next = calendar.nextDate(
                        after: cursor,
                        matching: components,
                        matchingPolicy: .nextTime
                    )
                else {
                    return nil
                }
                
                let weekday = Weekday(
                    calendarWeekday: calendar.component(.weekday, from: next)
                )
                
                if days.isEmpty || (weekday.map { day in days.contains(day) } ?? false) {
                    return next
                }
                
                cursor = next
            }
            
            return nil
        }
    }
}

extension Trigger: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case once
        case every
        case at
        case days
        case timezone
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let present = [CodingKeys.once, .every, .at].filter { key in container.contains(key) }
        
        guard present.count == 1 else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "trigger requires exactly one of 'once' / 'every' / 'at'"
                        + " (got \(present.count))"
                )
            )
        }
        
        if container.contains(.every) {
            self = .every(try container.decode(Interval.self, forKey: .every))
            
            return
        }
        
        if container.contains(.once) {
            let raw = try container.decode(String.self, forKey: .once)
            let timezone = try Self.decodeTimezone(container, context: "once")
            
            guard let date = Self.parseWallClock(raw, timezone: timezone) else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: container.codingPath + [CodingKeys.once],
                        debugDescription: "once must be 'yyyy-MM-dd HH:mm:ss': '\(raw)'"
                    )
                )
            }
            
            self = .once(fireAt: date, timezone: timezone)
            
            return
        }
        
        let raw = try container.decode(String.self, forKey: .at)
        
        guard let (hour, minute) = Self.parseHHmm(raw) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath + [CodingKeys.at],
                    debugDescription: "at must be 'HH:mm' (24h): '\(raw)'"
                )
            )
        }
        
        let timezone = try Self.decodeTimezone(container, context: "at")
        var days: Set<Weekday> = []
        
        if let list = try container.decodeIfPresent([Weekday].self, forKey: .days) {
            guard !list.isEmpty else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: container.codingPath + [CodingKeys.days],
                        debugDescription: "days must be non-empty when present"
                            + " (omit for every day)"
                    )
                )
            }
            
            days = Set(list)
        }
        
        self = .at(hour: hour, minute: minute, days: days, timezone: timezone)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .every(let interval):
            try container.encode(interval, forKey: .every)
        
        case .once(let fireAt, let timezone):
            try container.encode(
                Self.formatWallClock(fireAt, timezone: timezone),
                forKey: .once
            )
            try container.encode(timezone.identifier, forKey: .timezone)
        
        case .at(let hour, let minute, let days, let timezone):
            try container.encode(String(format: "%02d:%02d", hour, minute), forKey: .at)
            
            if !days.isEmpty {
                try container.encode(
                    Weekday.allCases.filter { day in days.contains(day) },
                    forKey: .days
                )
            }
            
            try container.encode(timezone.identifier, forKey: .timezone)
        }
    }
    
    private static func decodeTimezone(
        _ container: KeyedDecodingContainer<CodingKeys>,
        context: String
    ) throws -> TimeZone {
        guard container.contains(.timezone) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "\(context) requires 'timezone' (e.g. 'Asia/Seoul')"
                )
            )
        }
        
        let identifier = try container.decode(String.self, forKey: .timezone)
        
        guard let timezone = TimeZone(identifier: identifier) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath + [CodingKeys.timezone],
                    debugDescription: "\(context): unknown timezone identifier '\(identifier)'"
                )
            )
        }
        
        return timezone
    }
}

extension Trigger {
    static func parseWallClock(_ text: String, timezone: TimeZone) -> Date? {
        wallClockFormatter(timezone).date(from: text.trimmingCharacters(in: .whitespaces))
    }
    
    static func formatWallClock(_ date: Date, timezone: TimeZone) -> String {
        wallClockFormatter(timezone).string(from: date)
    }
    
    static func parseHHmm(_ text: String) -> (Int, Int)? {
        let parts = text
            .trimmingCharacters(in: .whitespaces)
            .split(separator: ":", omittingEmptySubsequences: false)
        
        guard
            parts.count == 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1]),
            (0..<24).contains(hour),
            (0..<60).contains(minute)
        else {
            return nil
        }
        
        return (hour, minute)
    }
    
    private static func wallClockFormatter(_ timezone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        
        return formatter
    }
}
