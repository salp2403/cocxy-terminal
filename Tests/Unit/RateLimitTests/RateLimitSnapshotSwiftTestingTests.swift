// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Unit coverage for `RateLimitSnapshot`, the value type the probe
/// service produces every time it samples local usage data and the
/// status-bar pill renders.
///
/// Three things must hold for every snapshot consumer downstream:
///
///   1. `heatLevel` partitions the `[0, 1]` usage percentile into
///      three bands (green < 50%, yellow [50%, 80%), red >= 80%) so
///      the pill colour is a pure function of the snapshot.
///   2. Values outside the nominal `[0, 1]` range still map to a
///      defined heat level (red for over-budget, green for negative
///      / zero) — the probe occasionally produces extrapolated values
///      and the view layer must never crash on those.
///   3. The percent boundary is reached *exactly* at 50% and 80% so
///      manual QA against round numbers stays predictable.
@Suite("RateLimitSnapshot.heatLevel")
struct RateLimitSnapshotSwiftTestingTests {

    // MARK: - Fixtures

    private static let frozenInstant = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeSnapshot(
        usagePercent: Double,
        agent: RateLimitSnapshot.AgentKind = .claude,
        usedAmount: Int = 0,
        limitAmount: Int = 100,
        unit: RateLimitSnapshot.Unit = .tokens
    ) -> RateLimitSnapshot {
        RateLimitSnapshot(
            agent: agent,
            usagePercent: usagePercent,
            usedAmount: usedAmount,
            limitAmount: limitAmount,
            unit: unit,
            updatedAt: Self.frozenInstant
        )
    }

    // MARK: - Green band

    @Test("usagePercent at 0.0 is green")
    func zeroIsGreen() {
        #expect(makeSnapshot(usagePercent: 0.0).heatLevel == .green)
    }

    @Test("usagePercent at 0.49 stays green just below the yellow threshold")
    func justBelowYellowIsGreen() {
        #expect(makeSnapshot(usagePercent: 0.49).heatLevel == .green)
    }

    // MARK: - Yellow band

    @Test("usagePercent at 0.5 crosses into the yellow band exactly at half")
    func halfIsYellow() {
        #expect(makeSnapshot(usagePercent: 0.5).heatLevel == .yellow)
    }

    @Test("usagePercent at 0.79 stays yellow just below the red threshold")
    func justBelowRedIsYellow() {
        #expect(makeSnapshot(usagePercent: 0.79).heatLevel == .yellow)
    }

    // MARK: - Red band

    @Test("usagePercent at 0.8 crosses into the red band exactly at four-fifths")
    func fourFifthsIsRed() {
        #expect(makeSnapshot(usagePercent: 0.8).heatLevel == .red)
    }

    @Test("usagePercent at 1.0 is red")
    func fullIsRed() {
        #expect(makeSnapshot(usagePercent: 1.0).heatLevel == .red)
    }

    // MARK: - Out-of-range defensive behaviour

    @Test("over-budget percent above 1.0 stays red instead of wrapping or crashing")
    func overBudgetStaysRed() {
        #expect(makeSnapshot(usagePercent: 1.5).heatLevel == .red)
    }

    @Test("negative usage clamps to green so the pill never renders an unknown colour")
    func negativeIsGreen() {
        #expect(makeSnapshot(usagePercent: -0.1).heatLevel == .green)
    }

    // MARK: - Equatable identity

    @Test("two snapshots with the same fields compare equal")
    func equalFieldsCompareEqual() {
        let a = makeSnapshot(usagePercent: 0.6, usedAmount: 60)
        let b = makeSnapshot(usagePercent: 0.6, usedAmount: 60)

        #expect(a == b)
    }

    @Test("snapshots with different agents are not equal even when usage matches")
    func differentAgentsAreNotEqual() {
        let claude = makeSnapshot(usagePercent: 0.6, agent: .claude)
        let codex = makeSnapshot(usagePercent: 0.6, agent: .codex)

        #expect(claude != codex)
    }
}
