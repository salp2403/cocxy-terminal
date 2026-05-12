// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RateLimitIndicatorFormatting.swift - Pure helpers that render the
// status-bar pill's percent label and tooltip from a snapshot.

import Foundation

/// Pure rendering helpers consumed by `RateLimitIndicatorView`.
///
/// Keeping the visible strings here lets the unit suite pin them
/// without the SwiftUI runtime, snapshot fixtures, or accessibility
/// tree introspection. The view layer composes these strings with
/// SF Symbols and colours and never reformulates them inline.
enum RateLimitIndicatorFormatting {

    // MARK: - Percent label

    /// Renders `usagePercent` as a whole-number percent suffixed with
    /// "%". When the provider cannot determine a denominator
    /// (`limitAmount == 0`), the pill renders `local` instead of a fake
    /// percentage so users do not mistake a local activity counter for
    /// an authoritative quota read.
    static func percentLabel(for snapshot: RateLimitSnapshot) -> String {
        guard snapshot.limitAmount > 0 else { return "local" }
        let clamped = max(0, snapshot.usagePercent)
        let percent = Int((clamped * 100).rounded())
        return "\(percent)%"
    }

    // MARK: - Agent display name

    /// Maps the canonical `AgentKind` enum to its capitalised display
    /// name. Pinned by tests so the four supported agents always
    /// render with their canonical brand spelling.
    static func agentDisplayName(_ agent: RateLimitSnapshot.AgentKind) -> String {
        switch agent {
        case .claude: return "Claude"
        case .codex:  return "Codex"
        case .gemini: return "Gemini"
        case .aider:  return "Aider"
        case .cursor: return "Cursor"
        case .copilot: return "Copilot"
        case .opencode: return "OpenCode"
        case .amp: return "Amp"
        case .factory: return "Factory"
        case .kimi: return "Kimi"
        case .minimax: return "MiniMax"
        case .zai: return "Z.ai"
        }
    }

    // MARK: - Tooltip text

    /// Builds the tooltip string the pill exposes via the SwiftUI
    /// `.help(_:)` modifier. Layout:
    ///
    /// ```
    /// <Agent>
    /// <used> / <limit> <unit>   ← `/ <limit>` omitted when limit is 0
    /// Local estimate from CLI ledgers — not an authoritative quota.
    /// <upstream-disclosure>     ← only emitted when the source ledger has
    ///                             a known, documented issue users must
    ///                             know about to interpret the count
    ///                             correctly (e.g. Codex CLI's inflated
    ///                             totals — see `codexLedgerDisclosure`).
    /// ```
    ///
    /// The tooltip explicitly calls out that the value is a local
    /// estimate so the user does not mistake the pill for an
    /// authoritative read of their plan rate limit. Providers should
    /// use local files only, so Cocxy can render the indicator without
    /// sending telemetry or asking an external quota endpoint.
    static func tooltipText(for snapshot: RateLimitSnapshot) -> String {
        let agent = agentDisplayName(snapshot.agent)
        let usedString = decimalFormatter.string(from: NSNumber(value: snapshot.usedAmount)) ?? "\(snapshot.usedAmount)"
        let unit = snapshot.unit.rawValue
        let countLine: String
        if snapshot.limitAmount > 0 {
            let limitString = decimalFormatter.string(from: NSNumber(value: snapshot.limitAmount)) ?? "\(snapshot.limitAmount)"
            countLine = "\(usedString) / \(limitString) \(unit)"
        } else {
            countLine = "\(usedString) \(unit)"
        }
        var lines: [String] = [
            agent,
            countLine,
            "Local estimate from CLI ledgers — not an authoritative quota.",
        ]
        if let extra = upstreamLedgerDisclosure(for: snapshot.agent) {
            lines.append(extra)
        }
        return lines.joined(separator: "\n")
    }

    /// Optional per-agent disclosure appended to the tooltip when the
    /// upstream CLI's local ledger has a documented quirk users need to
    /// understand to interpret the rendered count. Returning `nil`
    /// keeps the tooltip identical to the agent-agnostic baseline.
    ///
    /// Currently scoped to Codex CLI: its `state_5.sqlite` thread
    /// ledger reports token totals inflated by an undocumented factor
    /// (upstream issue openai/codex#18498). Without this disclosure
    /// the user would see a number that looks like real usage but is
    /// not directly comparable to the value Codex itself reports — a
    /// regression of `feedback_user_feels_incomplete` ("showing
    /// inflated numbers is worse than showing nothing"). Surfacing the
    /// known caveat in the tooltip lets the pill stay useful as a
    /// relative activity signal while keeping the contract honest.
    static func upstreamLedgerDisclosure(for agent: RateLimitSnapshot.AgentKind) -> String? {
        switch agent {
        case .codex:
            return "Codex CLI's local ledger reports inflated token totals (openai/codex#18498). Treat as a relative activity signal, not absolute usage."
        case .claude, .gemini, .aider, .cursor, .copilot, .opencode, .amp, .factory, .kimi, .minimax, .zai:
            return nil
        }
    }

    // MARK: - Private

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        return formatter
    }()
}
