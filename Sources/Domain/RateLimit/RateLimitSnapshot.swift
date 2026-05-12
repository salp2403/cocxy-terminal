// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RateLimitSnapshot.swift - Value type the probe service produces and
// the status-bar pill renders.

import Foundation

/// One sample of an agent's locally-observable usage data.
///
/// The snapshot is built off-line from files the agent CLIs already
/// keep on disk (no network calls, no telemetry) and is the contract
/// the status-bar pill draws against. Producers populate every field
/// — `usagePercent` is a hint, but `usedAmount` / `limitAmount` /
/// `unit` are what the tooltip surfaces so users can see the raw
/// numbers behind the colour.
struct RateLimitSnapshot: Sendable, Equatable {

    /// Agent the sample belongs to. Always set to a known case rather
    /// than a free-form string so the view layer can match colours,
    /// icons, and tooltip copy on a closed enum.
    let agent: AgentKind

    /// Estimated usage as a fraction of the agent's perceived budget.
    /// Producers may emit values outside `[0, 1]` (negative when the
    /// limit is unknown, > 1.0 when the user crossed a soft cap); the
    /// `heatLevel` mapping clamps both ends so the pill colour stays
    /// defined.
    let usagePercent: Double

    /// Raw `usedAmount` of the unit. Surfaces in the tooltip so users
    /// can see, for example, "120 000 tokens of 200 000".
    let usedAmount: Int

    /// Raw `limitAmount` of the unit, or zero when the producer cannot
    /// determine a budget. The view layer hides the denominator when
    /// the limit is zero rather than printing `120 000 / 0`.
    let limitAmount: Int

    /// Unit the `usedAmount` / `limitAmount` numbers express. Keeps
    /// the tooltip self-describing across providers (Claude reports
    /// tokens, Codex may report requests, etc.).
    let unit: Unit

    /// Wall-clock instant the sample was produced. The pill consults
    /// this to fade out stale snapshots so the colour is never older
    /// than the user expects from the polling interval.
    let updatedAt: Date

    /// Heat band the pill renders. Pure function of `usagePercent`:
    ///   * green when the user is below 50% of their perceived budget;
    ///   * yellow at 50% and below 80%;
    ///   * red at 80% and above (clamped so over-budget values stay
    ///     red rather than wrapping into another band).
    var heatLevel: HeatLevel {
        if usagePercent < 0.5 { return .green }
        if usagePercent < 0.8 { return .yellow }
        return .red
    }

    // MARK: - Nested types

    /// Agent the sample belongs to.
    enum AgentKind: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
        case claude
        case codex
        case gemini
        case aider
        case cursor
        case copilot
        case opencode
        case amp
        case factory
        case kimi
        case minimax
        case zai
    }

    /// Unit the `usedAmount` / `limitAmount` numbers express.
    enum Unit: String, Sendable, Equatable {
        case tokens
        case requests
        case messages
    }

    /// Three-band partition the pill renders. Closed enum so the view
    /// layer cannot drift onto an unhandled colour by accident.
    enum HeatLevel: Sendable, Equatable {
        case green
        case yellow
        case red
    }
}
