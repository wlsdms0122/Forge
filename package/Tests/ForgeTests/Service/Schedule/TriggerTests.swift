//
//  TriggerTests.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import Forge

@Suite("Trigger Tests")
struct TriggerTests {
    // MARK: - Property
    private let seoul = TimeZone(identifier: "Asia/Seoul")!
    
    // MARK: - Initializer
    // MARK: - Test
    // MARK: - parseTrigger fail-loud (misplaced timezone/days rejected — single RPC validation)
    @Test("Rejects timezone and days in the wrong place")
    func parseTriggerRejectsMisplacedTimezoneDays() {
        #expect(throws: (any Error).self) { try ScheduleCreateMethod.parseTrigger(["every": "1h", "timezone": "Asia/Seoul"]) }
        #expect(throws: (any Error).self) { try ScheduleCreateMethod.parseTrigger(["after": "30m", "timezone": "Asia/Seoul"]) }
        #expect(throws: (any Error).self) { try ScheduleCreateMethod.parseTrigger(["every": "1h", "days": ["mon"]]) }
        #expect(throws: (any Error).self) { try ScheduleCreateMethod.parseTrigger(
                ["once": "2099-01-01 09:00:00", "timezone": "Asia/Seoul", "days": ["mon"]]) }
        #expect(throws: Never.self) { try ScheduleCreateMethod.parseTrigger(["every": "1h"]) }
        #expect(throws: Never.self) { try ScheduleCreateMethod.parseTrigger(["after": "30m"]) }
        #expect(throws: Never.self) {
            try ScheduleCreateMethod.parseTrigger(
                ["at": "09:20", "timezone": "Asia/Seoul", "days": ["mon", "wed"]])
        }
    }
    
    // MARK: - Interval (duration parse)
    @Test("Single-unit interval parsing")
    func intervalParseSingleUnit() throws {
        #expect(try Interval.parse("30s") == 30)
        #expect(try Interval.parse("5m") == 300)
        #expect(try Interval.parse("1h") == 3600)
        #expect(try Interval.parse("2d") == 172800)
        #expect(try Interval.parse("90") == 90)
    }
    
    @Test("Compound-unit interval parsing")
    func intervalParseCompound() throws {
        #expect(try Interval.parse("1h30m") == 5400)
        #expect(try Interval.parse("1h 30m") == 5400)
        #expect(try Interval.parse("2d12h") == 216000)
        #expect(try Interval.parse("1h30m15s") == 5415)
    }
    
    @Test("Malformed intervals are rejected")
    func intervalParseRejectsBad() {
        #expect(throws: (any Error).self) { try Interval.parse("") }
        #expect(throws: (any Error).self) { try Interval.parse("1h30") }
        #expect(throws: (any Error).self) { try Interval.parse("1x") }
        #expect(throws: (any Error).self) { try Interval.parse("0m") }
        #expect(throws: (any Error).self) { try Interval.parse("9000000000000000d") }
    }
    
    // MARK: - nextFire (ledger-anchored derivation)
    @Test("Next fire is anchored on the last fire")
    func nextFireAnchorsOnLastFired() {
        // Given
        let every = Trigger.every(Interval(seconds: 3600))
        let now = Date(timeIntervalSince1970: 1_000_000)
        let last = Date(timeIntervalSince1970: 990_000)

        // Then
        #expect(every.nextFire(after: last, now: now) == last.addingTimeInterval(3600))
        #expect(every.nextFire(after: nil, now: now) == now.addingTimeInterval(3600))
        let fireAt = Date(timeIntervalSince1970: 500_000)
        let once = Trigger.once(fireAt: fireAt, timezone: seoul)
        #expect(once.nextFire(after: fireAt, now: now) == nil)
        #expect(once.nextFire(after: nil, now: now) == fireAt)
    }
    
    // MARK: - every
    @Test("every advances by its interval")
    func everyAdvance() {
        // Given
        let result = Trigger.every(Interval(seconds: 3600))
        let moment = Date(timeIntervalSince1970: 1_000_000)

        // Then
        #expect(result.advance(after: moment) == moment.addingTimeInterval(3600))
        #expect(result.firstFire(now: moment) == moment.addingTimeInterval(3600))
    }
    
    // MARK: - once
    @Test("once fires a single time and is exhausted")
    func onceAdvanceAndExhaust() {
        // Given
        let fireAt = seoulDate(2030, 1, 1, 9, 0)
        let result = Trigger.once(fireAt: fireAt, timezone: seoul)

        // Then
        #expect(result.advance(after: seoulDate(2029, 12, 31, 23, 59)) == fireAt)
        #expect(result.advance(after: fireAt) == nil, "exhausted after its own fire time")
        #expect(result.advance(after: seoulDate(2031, 1, 1, 0, 0)) == nil)
    }
    
    @Test("A past once catches up on first fire")
    func onceFirstFireCatchesUpPast() {
        // Given
        let past = seoulDate(2020, 1, 1, 9, 0)
        let result = Trigger.once(fireAt: past, timezone: seoul)

        // Then
        #expect(result.firstFire(now: Date()) == past)
        #expect(result.isOneShot)
    }
    
    // MARK: - at (wall clock)
    @Test("at prefers the remaining time today, otherwise moves to the next day")
    func atAdvanceSameDayThenNextDay() {
        // Given
        let result = Trigger.at(hour: 9, minute: 20, days: [], timezone: seoul)

        // Then
        #expect(result.advance(after: seoulDate(2026, 6, 17, 8, 0)) == seoulDate(2026, 6, 17, 9, 20))
        #expect(result.advance(after: seoulDate(2026, 6, 17, 10, 0)) == seoulDate(2026, 6, 18, 9, 20))
    }
    
    @Test("at respects the specified timezone")
    func atRespectsTimezone() {
        // Given
        let result = Trigger.at(hour: 9, minute: 20, days: [], timezone: seoul)
        let next = result.advance(after: seoulDate(2026, 6, 17, 0, 0))!
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        // Then
        #expect(utc.component(.hour, from: next) == 0)
        #expect(utc.component(.minute, from: next) == 20)
    }
    
    @Test("The days filter constrains which weekdays fire")
    func atDaysFilter() {
        // Given
        let result = Trigger.at(hour: 9, minute: 20, days: [.mon], timezone: seoul)
        let next = result.advance(after: seoulDate(2026, 6, 17, 12, 0))!
        let cal = seoulCal()

        // Then
        #expect(cal.component(.weekday, from: next) == 2, "next match is Monday (2)")
        #expect(cal.component(.hour, from: next) == 9)
        #expect(cal.component(.minute, from: next) == 20)
        #expect(next > seoulDate(2026, 6, 17, 12, 0))
    }
    
    // MARK: - parsing
    @Test("HH:mm parsing")
    func parseHHmm() {
        #expect(Trigger.parseHHmm("09:20")?.0 == 9)
        #expect(Trigger.parseHHmm("09:20")?.1 == 20)
        #expect(Trigger.parseHHmm("0:5")?.0 == 0)
        #expect(Trigger.parseHHmm("24:00") == nil)
        #expect(Trigger.parseHHmm("09:60") == nil)
        #expect(Trigger.parseHHmm("0920") == nil)
        #expect(Trigger.parseHHmm("xx:yy") == nil)
    }
    
    @Test("Wall-clock representation round-trips")
    func parseWallClockRoundTrip() {
        // Given
        let parsed = Trigger.parseWallClock("2026-06-20 09:00:00", timezone: seoul)

        // Then
        #expect(parsed != nil)
        #expect(Trigger.formatWallClock(parsed!, timezone: seoul) == "2026-06-20 09:00:00")
        #expect(Trigger.parseWallClock("2026-06-20T09:00:00", timezone: seoul) == nil)
    }
    
    // MARK: - Codable validation
    @Test("Decodes multiple spellings")
    func decodeVariants() throws {
        #expect(try decode(#"{"every":"3h"}"#) == .every(Interval(seconds: 10800)))
        #expect(try decode(#"{"at":"09:20","timezone":"Asia/Seoul"}"#) == .at(hour: 9, minute: 20, days: [], timezone: seoul))
        #expect(try decode(#"{"at":"09:20","days":["mon","fri"],"timezone":"Asia/Seoul"}"#) == .at(hour: 9, minute: 20, days: [.mon, .fri], timezone: seoul))
    }
    
    @Test("Malformed input is rejected")
    func decodeRejectsBadInput() {
        #expect(throws: (any Error).self, "zero variants") { try decode(#"{}"#) }
        #expect(throws: (any Error).self, "two variants") { try decode(#"{"every":"1h","at":"09:20","timezone":"Asia/Seoul"}"#) }
        #expect(throws: (any Error).self, "missing timezone") { try decode(#"{"at":"09:20"}"#) }
        #expect(throws: (any Error).self, "once missing timezone") { try decode(#"{"once":"2026-06-20 09:00:00"}"#) }
        #expect(throws: (any Error).self, "unknown timezone") { try decode(#"{"at":"09:20","timezone":"Mars/Olympus"}"#) }
        #expect(throws: (any Error).self, "malformed HH:mm") { try decode(#"{"at":"9","timezone":"Asia/Seoul"}"#) }
        #expect(throws: (any Error).self, "empty days") { try decode(#"{"at":"09:20","days":[],"timezone":"Asia/Seoul"}"#) }
    }
    
    // MARK: - Private
    private func seoulCal() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        
        return calendar
    }
    
    private func seoulDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        seoulCal().date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: 0))!
    }
    
    private func decode(_ json: String) throws -> Trigger {
        try JSONDecoder().decode(Trigger.self, from: Data(json.utf8))
    }
}
