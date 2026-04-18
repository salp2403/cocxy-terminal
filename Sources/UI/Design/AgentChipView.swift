// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentChipView.swift - Reusable agent chip for the Aurora redesign.
//
// The redesigned chrome (sidebar, tab strip, status bar mini-matrix,
// pane header) all render the same two-letter agent chip with three
// responsibilities:
//   1. Communicate the agent identity via colour + abbreviation.
//   2. Communicate the agent lifecycle state via a soft pulse ring
//      when the state is active (`launched` or `working`).
//   3. Stay decoupled from the call site: every adopter supplies the
//      agent + state + size and gets an accessible chip.
//
// This view replaces nothing yet — it lives in the `Design` module
// alongside the tokens and the glass primitive, waiting for the
// next wave of commits that migrate the individual surfaces. Fase B
// still ships `MiniAgentPillView` with the legacy token set; the two
// will coexist until the sidebar migration lands and the legacy file
// is retired in a dedicated cleanup commit.

import SwiftUI

extension Design {

    /// Visual agent chip used by every surface in the Aurora redesign.
    ///
    /// The chip is a 22pt rounded square by default (matches the
    /// reference `.agent-chip` CSS) but adopts any size the caller
    /// supplies so the sidebar row can render a 18pt variant while
    /// the command-palette glyph stays at 22pt. The abbreviation
    /// font scales proportionally.
    ///
    /// Accessibility notes:
    /// - The chip declares `accessibilityLabel` as the human-readable
    ///   agent name plus the lifecycle label (e.g. "Claude, working")
    ///   so VoiceOver does not just announce "Cl".
    /// - The pulsing ring is non-interactive visual feedback, so the
    ///   implementation wraps it in `.accessibilityHidden(true)` — the
    ///   label already conveys the state.
    struct AgentChipView: View {
        let agent: AgentAccent
        let state: AgentStateRole
        var size: CGFloat = 22

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            ZStack {
                base
                if showsPulsingRing {
                    pulseRing
                        .accessibilityHidden(true)
                }
            }
            .frame(width: size, height: size)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(agentDisplayName), \(stateLabel)")
        }

        // MARK: - Subviews

        /// Chip background + border + abbreviation text. Kept as a
        /// computed view so the main `body` stays compact and the
        /// pulsing ring can be overlaid without re-declaring the base.
        private var base: some View {
            let chipColour = agent.token.resolvedColor()
            let background = agent.token.withAlpha(0.28).resolvedColor()
            let border = agent.token.withAlpha(0.50).resolvedColor()
            let fontSize = abbreviationFontSize(for: size)

            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(background)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                )
                .overlay(
                    Text(agent.abbreviation)
                        .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                        .tracking(-0.2)
                        .foregroundStyle(chipColour)
                )
        }

        /// Pulsing halo around the chip when the agent is active.
        /// The animation intentionally runs on a timeline so the view
        /// can live inside lists without triggering layout thrash.
        private var pulseRing: some View {
            let ringColour = agent.token.resolvedColor().opacity(0.8)
            let inset: CGFloat = -2
            let ringCorner = cornerRadius + 2

            return SwiftUI.TimelineView(.animation(minimumInterval: reduceMotion ? nil : 1.0 / 30.0, paused: reduceMotion)) { context in
                let phase = Self.pulsePhase(at: context.date.timeIntervalSinceReferenceDate)
                RoundedRectangle(cornerRadius: ringCorner, style: .continuous)
                    .strokeBorder(ringColour, lineWidth: 1.5)
                    .padding(inset)
                    .scaleEffect(phase.scale)
                    .opacity(phase.opacity)
            }
        }

        // MARK: - Geometry

        private var cornerRadius: CGFloat {
            // Corner radius stays proportional to the chip — the
            // 22pt reference uses a 6pt radius so the chip reads as
            // a rounded square rather than a pill.
            return max(4, size * (6.0 / 22.0))
        }

        private func abbreviationFontSize(for chipSize: CGFloat) -> CGFloat {
            // Reference: chip 22 -> font 10.5, chip 18 -> font 9.5,
            // chip 16 -> font 9. Derive linearly so any future size
            // stays legible. Floor at 8 to stay above the minimum
            // readable pixel density on Retina.
            let scaled = chipSize * (10.5 / 22.0) + 0.5
            return max(8, round(scaled * 2) / 2)
        }

        // MARK: - State helpers

        private var showsPulsingRing: Bool {
            switch state {
            case .working, .launched: return true
            case .idle, .waiting, .finished, .error: return false
            }
        }

        private var agentDisplayName: String {
            switch agent {
            case .claude: return "Claude"
            case .codex:  return "Codex"
            case .gemini: return "Gemini"
            case .aider:  return "Aider"
            case .shell:  return "Shell"
            }
        }

        private var stateLabel: String {
            switch state {
            case .idle:     return "idle"
            case .launched: return "launched"
            case .working:  return "working"
            case .waiting:  return "waiting for input"
            case .finished: return "finished"
            case .error:    return "error"
            }
        }

        // MARK: - Pulse math

        /// Value describing the current pulse scale + opacity. Kept as
        /// a nested type so the view stays focused on layout while
        /// tests can assert on the interpolation curve.
        struct PulsePhase: Equatable, Sendable {
            let scale: CGFloat
            let opacity: Double
        }

        /// Pure helper exercised by tests. Maps a wall-clock value
        /// to a `PulsePhase` using a 1.6 second period that matches
        /// the design reference's `softPulse` keyframes (opacity
        /// 0 -> 1 -> 0, scale 1.0 -> 1.06 -> 1.0).
        static func pulsePhase(at seconds: Double) -> PulsePhase {
            let period: Double = 1.6
            let positiveSeconds = seconds < 0 ? -seconds : seconds
            let t = positiveSeconds.truncatingRemainder(dividingBy: period) / period
            // Sine wave shifted to stay in [0, 1] for the full period.
            let wave = 0.5 - 0.5 * cos(2 * .pi * t)
            return PulsePhase(
                scale: 1.0 + CGFloat(wave) * 0.06,
                opacity: 0.30 + wave * 0.70
            )
        }
    }
}
