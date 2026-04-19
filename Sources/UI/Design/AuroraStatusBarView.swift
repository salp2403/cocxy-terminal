// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraStatusBarView.swift - Redesigned status bar for the Aurora chrome.
//
// Renders the bottom glass bar that the design reference composes
// from five groups:
//
//   | 100% local ● | agents ■■■ | ports :3000 :4001 :9000 | timeline ▬●▬ | HH:MM |
//
// The view consumes `Design.AuroraWorkspace` snapshots (same shape as
// the sidebar) plus an ambient `AuroraTimelineState` so it can
// preview and test in isolation. A future integration commit will
// feed it from the live `AgentStatePerSurfaceStore` + the real
// `portScanner` + the command-duration timeline store.
//
// As with every file under `Sources/UI/Design/`, this is additive:
// nothing in the currently shipping chrome imports it yet.

import SwiftUI

extension Design {

    /// Status bar for the Aurora redesign. Callers bind the timeline
    /// progress so the scrubber can live-update while a replay is
    /// active.
    struct AuroraStatusBarView: View {
        let workspaces: [AuroraWorkspace]
        let ports: [AuroraPortBinding]
        @Binding var timeline: AuroraTimelineState
        let clockLabel: String
        let onReplay: () -> Void

        @Environment(\.designThemePalette) private var palette

        var body: some View {
            // The status bar sits at the bottom edge of the window,
            // so the `GlassSurface` wrapper with `.medium` corner
            // radius used to leave a visible gap between the terminal
            // area and the bar's top edge (the rounded corners
            // exposed the rootView background). A flat opaque band
            // fills the 24pt host frame exactly, matching the classic
            // status bar's geometry and keeping the Aurora markup
            // legible in the limited vertical budget.
            HStack(spacing: Spacing.large) {
                LocalBadgeView()
                separator
                AgentMatrixView(panes: Self.allPanes(in: workspaces))
                separator
                PortListView(ports: ports)
                separator
                TimelineScrubberView(
                    timeline: $timeline,
                    onReplay: onReplay
                )
                Spacer()
                Text(clockLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textDim.resolvedColor())
            }
            .padding(.horizontal, Spacing.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.backgroundSecondary.resolvedColor())
            .overlay(
                Rectangle()
                    .fill(palette.divider.resolvedColor())
                    .frame(height: 1),
                alignment: .top
            )
        }

        private var separator: some View {
            Rectangle()
                .fill(palette.divider.resolvedColor())
                .frame(width: 1, height: 14)
        }

        /// Flatten every workspace's session panes into the array the
        /// status-bar matrix consumes. Exposed as a static helper so
        /// tests can assert the flattening contract without spinning
        /// up a view hierarchy.
        static func allPanes(in workspaces: [AuroraWorkspace]) -> [AuroraPane] {
            workspaces.flatMap { ws in
                ws.sessions.flatMap { $0.panes }
            }
        }
    }

    // MARK: - Agent matrix

    /// Horizontal matrix of agent state cells. Each pane contributes
    /// one coloured square; `.idle` panes stay visible but desaturated
    /// so the matrix preserves positional identity across renders.
    struct AgentMatrixView: View {
        let panes: [AuroraPane]

        @Environment(\.designThemePalette) private var palette

        var body: some View {
            HStack(spacing: Spacing.xSmall) {
                Text("agents")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textDim.resolvedColor())

                HStack(spacing: 3) {
                    ForEach(panes) { pane in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(pane.state.token.resolvedColor())
                            .frame(width: 10, height: 10)
                            .accessibilityLabel("\(pane.name): \(Self.stateLabel(for: pane.state))")
                    }
                }
            }
        }

        private static func stateLabel(for state: AgentStateRole) -> String {
            state.rawValue
        }
    }

    // MARK: - Port list

    /// Displays bound local ports as compact chips with a health dot.
    struct PortListView: View {
        let ports: [AuroraPortBinding]

        @Environment(\.designThemePalette) private var palette

        var body: some View {
            HStack(spacing: Spacing.xSmall) {
                Text("ports")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textDim.resolvedColor())
                ForEach(ports) { port in
                    PortChip(port: port)
                }
            }
        }
    }

    struct PortChip: View {
        let port: AuroraPortBinding

        @Environment(\.designThemePalette) private var palette

        var body: some View {
            HStack(spacing: 4) {
                Circle()
                    .fill(port.stateRole.token.resolvedColor())
                    .frame(width: 5, height: 5)
                Text(":\(port.port)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.textMedium.resolvedColor())
                Text(port.name)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.textDim.resolvedColor())
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(palette.glassHighlight.resolvedColor())
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(palette.glassBorder.resolvedColor(), lineWidth: 1)
                    )
            )
            .accessibilityLabel("Port \(port.port) named \(port.name), state \(port.health.rawValue)")
        }
    }

    // MARK: - Timeline scrubber

    /// Horizontal timeline scrubber with a playhead thumb and a
    /// replay button. The scrub gesture updates the bound state
    /// directly; the replay button triggers the caller-supplied
    /// closure so the host can reset the playhead + schedule replay.
    struct TimelineScrubberView: View {
        @Binding var timeline: AuroraTimelineState
        let onReplay: () -> Void

        @Environment(\.designThemePalette) private var palette

        private let barWidth: CGFloat = 180

        var body: some View {
            HStack(spacing: Spacing.xSmall) {
                Text("timeline")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textDim.resolvedColor())

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(palette.glassHighlight.resolvedColor())
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(palette.accent.resolvedColor())
                        .frame(width: max(0, barWidth * timeline.progress), height: 4)
                    Circle()
                        .fill(palette.accent.resolvedColor())
                        .frame(width: 10, height: 10)
                        .shadow(color: palette.accentGlow.resolvedColor(), radius: 5)
                        .offset(x: barWidth * timeline.progress - 5)
                }
                .frame(width: barWidth, height: 10)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let clamped = max(0, min(1, value.location.x / barWidth))
                            timeline = AuroraTimelineState(progress: clamped, windowSeconds: timeline.windowSeconds)
                        }
                )

                Text(timeline.agoLabel)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.textMedium.resolvedColor())
                    .frame(minWidth: 50, alignment: .leading)

                Button(action: onReplay) {
                    Text("▶ replay")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.textMedium.resolvedColor())
                        .padding(.horizontal, Spacing.xSmall)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(palette.glassBorder.resolvedColor(), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Replay last \(Int(timeline.windowSeconds)) seconds")
            }
        }
    }
}
