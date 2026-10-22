// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Cron schedule")
struct CronScheduleSwiftTestingTests {
    @Test("supports steps ranges lists and symbolic month and weekday names")
    func supportsCommonPOSIXFields() throws {
        let schedule = try CronSchedule(
            expression: "*/15 9-17 * JAN,MAR MON-FRI",
            timeZoneIdentifier: "UTC"
        )
        let start = try utcDate(year: 2026, month: 1, day: 5, hour: 8, minute: 59)

        let next = try #require(schedule.nextDate(after: start))
        let expected = try utcDate(year: 2026, month: 1, day: 5, hour: 9, minute: 0)

        #expect(next == expected)
    }

    @Test("uses POSIX OR semantics when month-day and weekday are both restricted")
    func usesPOSIXDayOrSemantics() throws {
        let schedule = try CronSchedule(
            expression: "0 0 1 * MON",
            timeZoneIdentifier: "UTC"
        )
        let start = try utcDate(year: 2026, month: 1, day: 2, hour: 0, minute: 0)
        let expected = try utcDate(year: 2026, month: 1, day: 5, hour: 0, minute: 0)

        #expect(schedule.nextDate(after: start) == expected)
    }

    @Test("accepts Sunday as zero or seven")
    func acceptsSundayAliases() throws {
        let zero = try CronSchedule(expression: "0 12 * * 0", timeZoneIdentifier: "UTC")
        let seven = try CronSchedule(expression: "0 12 * * 7", timeZoneIdentifier: "UTC")
        let start = try utcDate(year: 2026, month: 1, day: 3, hour: 12, minute: 0)
        let expected = try utcDate(year: 2026, month: 1, day: 4, hour: 12, minute: 0)

        #expect(zero.nextDate(after: start) == seven.nextDate(after: start))
        #expect(zero.nextDate(after: start) == expected)
    }

    @Test("rejects malformed expressions and unknown time zones")
    func rejectsMalformedExpressions() {
        #expect(throws: CronScheduleError.invalidFieldCount(4)) {
            _ = try CronSchedule(expression: "0 1 2 3", timeZoneIdentifier: "UTC")
        }
        #expect(throws: CronScheduleError.valueOutOfRange(
            field: "minute",
            value: 60,
            range: 0...59
        )) {
            _ = try CronSchedule(expression: "60 * * * *", timeZoneIdentifier: "UTC")
        }
        #expect(throws: CronScheduleError.invalidTimeZone("Mars/Olympus")) {
            _ = try CronSchedule(expression: "0 * * * *", timeZoneIdentifier: "Mars/Olympus")
        }
    }

    private func utcDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        return try #require(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }
}
