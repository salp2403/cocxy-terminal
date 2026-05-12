// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// UsagePaceCalculator.swift - Pure hourly usage pace estimates.

import Foundation

struct UsagePace: Sendable, Equatable {
    let agent: RateLimitSnapshot.AgentKind
    let unit: RateLimitSnapshot.Unit
    let amountPerHour: Int

    var projectedDailyAmount: Int { amountPerHour * 24 }
    var projectedMonthlyAmount: Int { projectedDailyAmount * 30 }
}

struct UsagePaceCalculator: Sendable {
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    func pace(from samples: [RateLimitSnapshot]) -> UsagePace? {
        guard samples.count >= 2 else { return nil }
        let ordered = samples.sorted { $0.updatedAt < $1.updatedAt }
        guard let first = ordered.first,
              let latest = ordered.last,
              first.agent == latest.agent,
              first.unit == latest.unit else {
            return nil
        }
        let elapsed = latest.updatedAt.timeIntervalSince(first.updatedAt)
        guard elapsed > 0 else { return nil }
        let delta = latest.usedAmount - first.usedAmount
        guard delta >= 0 else { return nil }
        let perHour = Double(delta) / (elapsed / 3600)
        return UsagePace(
            agent: latest.agent,
            unit: latest.unit,
            amountPerHour: Int(perHour.rounded())
        )
    }
}
