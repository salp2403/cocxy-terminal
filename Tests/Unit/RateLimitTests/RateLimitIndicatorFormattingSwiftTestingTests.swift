// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Unit coverage for `RateLimitIndicatorFormatting`, the pure helpers
/// the SwiftUI pill calls when rendering its label and tooltip.
///
/// Keeping the rendering rules outside the SwiftUI view lets the suite
/// pin the user-visible strings (percent label, agent display name,
/// tooltip layout) without standing up a `View` snapshot harness.
@Suite("RateLimitIndicatorFormatting")
struct RateLimitIndicatorFormattingSwiftTestingTests {

    private static let frozenInstant = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeSnapshot(
        agent: RateLimitSnapshot.AgentKind = .claude,
        usagePercent: Double,
        usedAmount: Int = 0,
        limitAmount: Int = 1_000_000,
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

    // MARK: - percentLabel

    @Test("percentLabel rounds to the nearest whole percent")
    func percentLabelRoundsToWhole() {
        let snapshot = makeSnapshot(usagePercent: 0.426)
        #expect(RateLimitIndicatorFormatting.percentLabel(for: snapshot) == "43%")
    }

    @Test("percentLabel renders zero as 0%")
    func percentLabelZero() {
        let snapshot = makeSnapshot(usagePercent: 0.0)
        #expect(RateLimitIndicatorFormatting.percentLabel(for: snapshot) == "0%")
    }

    @Test("percentLabel renders the full budget as 100%")
    func percentLabelFull() {
        let snapshot = makeSnapshot(usagePercent: 1.0)
        #expect(RateLimitIndicatorFormatting.percentLabel(for: snapshot) == "100%")
    }

    @Test("percentLabel goes above 100% when the user crossed a soft cap so the tooltip data and the label stay consistent")
    func percentLabelOverBudget() {
        let snapshot = makeSnapshot(usagePercent: 1.5)
        #expect(RateLimitIndicatorFormatting.percentLabel(for: snapshot) == "150%")
    }

    @Test("percentLabel clamps a negative percentile to 0% so the pill never renders a negative number")
    func percentLabelNegativeClamps() {
        let snapshot = makeSnapshot(usagePercent: -0.2)
        #expect(RateLimitIndicatorFormatting.percentLabel(for: snapshot) == "0%")
    }

    @Test("percentLabel renders local when the provider cannot determine a denominator")
    func percentLabelRendersLocalForUnknownLimit() {
        let snapshot = makeSnapshot(
            agent: .codex,
            usagePercent: 0.0,
            usedAmount: 25_000,
            limitAmount: 0,
            unit: .tokens
        )

        #expect(RateLimitIndicatorFormatting.percentLabel(for: snapshot) == "local")
    }

    // MARK: - agentDisplayName

    @Test("each agent kind maps to its proper display name")
    func agentDisplayNamesAreSpelledOut() {
        #expect(RateLimitIndicatorFormatting.agentDisplayName(.claude) == "Claude")
        #expect(RateLimitIndicatorFormatting.agentDisplayName(.codex) == "Codex")
        #expect(RateLimitIndicatorFormatting.agentDisplayName(.gemini) == "Gemini")
        #expect(RateLimitIndicatorFormatting.agentDisplayName(.aider) == "Aider")
    }

    // MARK: - tooltipText

    @Test("tooltip leads with the agent display name and the used / limit count")
    func tooltipIncludesAgentAndCounts() {
        let snapshot = makeSnapshot(
            agent: .claude,
            usagePercent: 0.42,
            usedAmount: 420_000,
            limitAmount: 1_000_000,
            unit: .tokens
        )

        let text = RateLimitIndicatorFormatting.tooltipText(for: snapshot)

        #expect(text.contains("Claude"))
        #expect(text.contains("420,000"))
        #expect(text.contains("1,000,000"))
        #expect(text.contains("tokens"))
    }

    @Test("tooltip omits the denominator when the provider could not determine a limit")
    func tooltipOmitsDenominatorWhenLimitIsZero() {
        let snapshot = makeSnapshot(
            agent: .codex,
            usagePercent: 0.0,
            usedAmount: 25,
            limitAmount: 0,
            unit: .requests
        )

        let text = RateLimitIndicatorFormatting.tooltipText(for: snapshot)

        #expect(text.contains("Codex"))
        #expect(text.contains("25"))
        #expect(text.contains("requests"))
        #expect(!text.contains(" / 0 "))
        #expect(!text.contains(" / 0\n"))
    }

    @Test("tooltip surfaces the unit so users know whether the count is tokens, requests, or messages")
    func tooltipIncludesUnit() {
        let tokensSnapshot = makeSnapshot(usagePercent: 0.5, usedAmount: 500, limitAmount: 1000, unit: .tokens)
        let requestsSnapshot = makeSnapshot(usagePercent: 0.5, usedAmount: 5, limitAmount: 10, unit: .requests)
        let messagesSnapshot = makeSnapshot(usagePercent: 0.5, usedAmount: 5, limitAmount: 10, unit: .messages)

        #expect(RateLimitIndicatorFormatting.tooltipText(for: tokensSnapshot).contains("tokens"))
        #expect(RateLimitIndicatorFormatting.tooltipText(for: requestsSnapshot).contains("requests"))
        #expect(RateLimitIndicatorFormatting.tooltipText(for: messagesSnapshot).contains("messages"))
    }

    @Test("tooltip notes that the value is a local estimate so users do not mistake it for an authoritative quota")
    func tooltipDeclaresEstimate() {
        let snapshot = makeSnapshot(usagePercent: 0.5)

        let text = RateLimitIndicatorFormatting.tooltipText(for: snapshot)

        // The wording can shift but it must contain the disclosure
        // word "estimate" so the user knows the pill is heuristic, not
        // an authoritative read of their plan limit.
        #expect(text.lowercased().contains("estimate"))
    }

    @Test("tooltip discloses the upstream Codex ledger inflation so users can interpret the number as a relative activity signal")
    func tooltipDisclosesCodexLedgerInflation() {
        let codexSnapshot = makeSnapshot(
            agent: .codex,
            usagePercent: 0.0,
            usedAmount: 1234,
            limitAmount: 0,
            unit: .tokens
        )

        let text = RateLimitIndicatorFormatting.tooltipText(for: codexSnapshot)

        // The exact wording is allowed to evolve, but the disclosure
        // MUST mention the inflation so the user knows the absolute
        // number is not directly comparable to Codex's own reporting.
        #expect(text.lowercased().contains("inflated"))
        #expect(text.contains("openai/codex#18498"))
        #expect(text.lowercased().contains("relative activity"))
    }

    @Test("tooltip skips the Codex inflation disclosure for other agents so unrelated providers do not leak Codex-specific caveats")
    func tooltipOmitsCodexDisclosureForOtherAgents() {
        for agent in [RateLimitSnapshot.AgentKind.claude, .gemini, .aider] {
            let snapshot = makeSnapshot(
                agent: agent,
                usagePercent: 0.5,
                usedAmount: 500,
                limitAmount: 1000,
                unit: .tokens
            )

            let text = RateLimitIndicatorFormatting.tooltipText(for: snapshot)

            #expect(!text.contains("openai/codex#18498"))
            #expect(!text.lowercased().contains("inflated token totals"))
        }
    }

    @Test("upstreamLedgerDisclosure returns nil for non-Codex agents so the helper stays a pure decision table the tooltip can rely on")
    func upstreamLedgerDisclosureScopedToCodex() {
        #expect(RateLimitIndicatorFormatting.upstreamLedgerDisclosure(for: .codex) != nil)
        #expect(RateLimitIndicatorFormatting.upstreamLedgerDisclosure(for: .claude) == nil)
        #expect(RateLimitIndicatorFormatting.upstreamLedgerDisclosure(for: .gemini) == nil)
        #expect(RateLimitIndicatorFormatting.upstreamLedgerDisclosure(for: .aider) == nil)
    }
}
