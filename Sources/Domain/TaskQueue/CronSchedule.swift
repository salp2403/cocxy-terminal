// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CronSchedule.swift - Deterministic five-field POSIX cron scheduling.

import Foundation

enum CronScheduleError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidFieldCount(Int)
    case invalidTimeZone(String)
    case emptyField(position: Int)
    case invalidValue(field: String, value: String)
    case valueOutOfRange(field: String, value: Int, range: ClosedRange<Int>)
    case invalidRange(field: String, value: String)
    case invalidStep(field: String, value: String)

    var description: String {
        switch self {
        case .invalidFieldCount(let count):
            return "Cron expression must contain five fields, got \(count)"
        case .invalidTimeZone(let identifier):
            return "Unknown cron time zone: \(identifier)"
        case .emptyField(let position):
            return "Cron field \(position) cannot be empty"
        case .invalidValue(let field, let value):
            return "Invalid \(field) cron value: \(value)"
        case .valueOutOfRange(let field, let value, let range):
            return "Cron \(field) value \(value) is outside \(range.lowerBound)...\(range.upperBound)"
        case .invalidRange(let field, let value):
            return "Invalid \(field) cron range: \(value)"
        case .invalidStep(let field, let value):
            return "Invalid \(field) cron step: \(value)"
        }
    }
}

struct CronSchedule: Codable, Sendable, Equatable {
    static let maximumSearchMinutes = 5 * 366 * 24 * 60

    let expression: String
    let timeZoneIdentifier: String

    private let minute: CronField
    private let hour: CronField
    private let dayOfMonth: CronField
    private let month: CronField
    private let dayOfWeek: CronField

    init(
        expression: String,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws {
        let fields = expression
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard fields.count == 5 else {
            throw CronScheduleError.invalidFieldCount(fields.count)
        }
        guard TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw CronScheduleError.invalidTimeZone(timeZoneIdentifier)
        }

        self.expression = fields.joined(separator: " ")
        self.timeZoneIdentifier = timeZoneIdentifier
        minute = try CronField(
            rawValue: fields[0],
            name: "minute",
            range: 0...59
        )
        hour = try CronField(
            rawValue: fields[1],
            name: "hour",
            range: 0...23
        )
        dayOfMonth = try CronField(
            rawValue: fields[2],
            name: "day-of-month",
            range: 1...31
        )
        month = try CronField(
            rawValue: fields[3],
            name: "month",
            range: 1...12,
            names: Self.monthNames
        )
        dayOfWeek = try CronField(
            rawValue: fields[4],
            name: "day-of-week",
            range: 0...7,
            names: Self.weekdayNames,
            normalization: { $0 == 7 ? 0 : $0 }
        )
    }

    private enum CodingKeys: String, CodingKey {
        case expression
        case timeZoneIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            expression: try container.decode(String.self, forKey: .expression),
            timeZoneIdentifier: try container.decode(String.self, forKey: .timeZoneIdentifier)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(expression, forKey: .expression)
        try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
    }

    func nextDate(after date: Date) -> Date? {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let minuteBoundary = calendar.date(from: components),
              var candidate = calendar.date(byAdding: .minute, value: 1, to: minuteBoundary) else {
            return nil
        }

        for _ in 0..<Self.maximumSearchMinutes {
            let values = calendar.dateComponents(
                [.minute, .hour, .day, .month, .weekday],
                from: candidate
            )
            guard let minuteValue = values.minute,
                  let hourValue = values.hour,
                  let dayValue = values.day,
                  let monthValue = values.month,
                  let weekdayValue = values.weekday else {
                return nil
            }

            let cronWeekday = weekdayValue - 1
            let dayMatches: Bool
            if dayOfMonth.isWildcard && dayOfWeek.isWildcard {
                dayMatches = true
            } else if dayOfMonth.isWildcard {
                dayMatches = dayOfWeek.contains(cronWeekday)
            } else if dayOfWeek.isWildcard {
                dayMatches = dayOfMonth.contains(dayValue)
            } else {
                dayMatches = dayOfMonth.contains(dayValue) || dayOfWeek.contains(cronWeekday)
            }

            if minute.contains(minuteValue),
               hour.contains(hourValue),
               month.contains(monthValue),
               dayMatches {
                return candidate
            }

            guard let next = calendar.date(byAdding: .minute, value: 1, to: candidate) else {
                return nil
            }
            candidate = next
        }
        return nil
    }

    private static let monthNames = [
        "JAN": 1, "FEB": 2, "MAR": 3, "APR": 4,
        "MAY": 5, "JUN": 6, "JUL": 7, "AUG": 8,
        "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12,
    ]

    private static let weekdayNames = [
        "SUN": 0, "MON": 1, "TUE": 2, "WED": 3,
        "THU": 4, "FRI": 5, "SAT": 6,
    ]
}

private struct CronField: Sendable, Equatable {
    let values: Set<Int>
    let isWildcard: Bool

    init(
        rawValue: String,
        name: String,
        range: ClosedRange<Int>,
        names: [String: Int] = [:],
        normalization: @Sendable (Int) -> Int = { $0 }
    ) throws {
        guard !rawValue.isEmpty else {
            throw CronScheduleError.emptyField(position: 0)
        }

        isWildcard = rawValue == "*"
        var parsedValues: Set<Int> = []
        for segment in rawValue.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
            guard !segment.isEmpty else {
                throw CronScheduleError.invalidValue(field: name, value: rawValue)
            }
            let stepParts = segment.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard stepParts.count <= 2 else {
                throw CronScheduleError.invalidStep(field: name, value: segment)
            }
            let step: Int
            if stepParts.count == 2 {
                guard let parsedStep = Int(stepParts[1]), parsedStep > 0 else {
                    throw CronScheduleError.invalidStep(field: name, value: segment)
                }
                step = parsedStep
            } else {
                step = 1
            }

            let base = stepParts[0]
            let bounds: ClosedRange<Int>
            if base == "*" {
                bounds = range
            } else {
                let rangeParts = base.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
                if rangeParts.count == 1 {
                    let start = try Self.parseValue(
                        rangeParts[0],
                        field: name,
                        range: range,
                        names: names
                    )
                    bounds = stepParts.count == 2 ? start...range.upperBound : start...start
                } else if rangeParts.count == 2 {
                    let start = try Self.parseValue(
                        rangeParts[0],
                        field: name,
                        range: range,
                        names: names
                    )
                    let end = try Self.parseValue(
                        rangeParts[1],
                        field: name,
                        range: range,
                        names: names
                    )
                    guard start <= end else {
                        throw CronScheduleError.invalidRange(field: name, value: base)
                    }
                    bounds = start...end
                } else {
                    throw CronScheduleError.invalidRange(field: name, value: base)
                }
            }

            var value = bounds.lowerBound
            while value <= bounds.upperBound {
                parsedValues.insert(normalization(value))
                guard value <= Int.max - step else { break }
                value += step
            }
        }

        guard !parsedValues.isEmpty else {
            throw CronScheduleError.invalidValue(field: name, value: rawValue)
        }
        values = parsedValues
    }

    func contains(_ value: Int) -> Bool {
        values.contains(value)
    }

    private static func parseValue(
        _ rawValue: String,
        field: String,
        range: ClosedRange<Int>,
        names: [String: Int]
    ) throws -> Int {
        let uppercased = rawValue.uppercased()
        let value = names[uppercased] ?? Int(rawValue)
        guard let value else {
            throw CronScheduleError.invalidValue(field: field, value: rawValue)
        }
        guard range.contains(value) else {
            throw CronScheduleError.valueOutOfRange(field: field, value: value, range: range)
        }
        return value
    }
}
