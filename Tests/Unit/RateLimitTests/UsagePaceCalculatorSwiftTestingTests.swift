// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("UsagePaceCalculator")
struct UsagePaceCalculatorSwiftTestingTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("returns nil for fewer than two samples")
    func returnsNilForInsufficientSamples() {
        let calculator = UsagePaceCalculator(now: { now })
        let sample = RateLimitSnapshot(
            agent: .cursor,
            usagePercent: 0.1,
            usedAmount: 100,
            limitAmount: 1000,
            unit: .tokens,
            updatedAt: now
        )

        #expect(calculator.pace(from: [sample]) == nil)
    }

    @Test("computes tokens per hour from the first and latest samples")
    func computesTokensPerHour() throws {
        let calculator = UsagePaceCalculator(now: { now })
        let first = RateLimitSnapshot(
            agent: .cursor,
            usagePercent: 0.1,
            usedAmount: 100,
            limitAmount: 1000,
            unit: .tokens,
            updatedAt: now.addingTimeInterval(-30 * 60)
        )
        let latest = RateLimitSnapshot(
            agent: .cursor,
            usagePercent: 0.3,
            usedAmount: 300,
            limitAmount: 1000,
            unit: .tokens,
            updatedAt: now
        )

        let pace = try #require(calculator.pace(from: [latest, first]))

        #expect(pace.amountPerHour == 400)
        #expect(pace.unit == .tokens)
    }

    @Test("projects daily and monthly totals from the hourly pace")
    func projectsDailyAndMonthlyTotals() throws {
        let calculator = UsagePaceCalculator(now: { now })
        let first = RateLimitSnapshot(
            agent: .opencode,
            usagePercent: 0,
            usedAmount: 0,
            limitAmount: 0,
            unit: .requests,
            updatedAt: now.addingTimeInterval(-60 * 60)
        )
        let latest = RateLimitSnapshot(
            agent: .opencode,
            usagePercent: 0,
            usedAmount: 10,
            limitAmount: 0,
            unit: .requests,
            updatedAt: now
        )

        let pace = try #require(calculator.pace(from: [first, latest]))

        #expect(pace.projectedDailyAmount == 240)
        #expect(pace.projectedMonthlyAmount == 7200)
    }

    @Test("ignores samples for different agents or units")
    func ignoresMixedSamples() {
        let calculator = UsagePaceCalculator(now: { now })
        let cursor = RateLimitSnapshot(
            agent: .cursor,
            usagePercent: 0,
            usedAmount: 100,
            limitAmount: 0,
            unit: .tokens,
            updatedAt: now.addingTimeInterval(-60 * 60)
        )
        let copilot = RateLimitSnapshot(
            agent: .copilot,
            usagePercent: 0,
            usedAmount: 200,
            limitAmount: 0,
            unit: .tokens,
            updatedAt: now
        )

        #expect(calculator.pace(from: [cursor, copilot]) == nil)
    }
}
