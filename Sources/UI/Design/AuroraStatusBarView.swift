// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraStatusBarView.swift - Redesigned status bar for the Aurora chrome.
//
// Renders the bottom glass bar composed from four live groups:
//
//   | no telemetry ● | agents ■■■ | ports :3000 :4001 :9000 | HH:MM |
//
// The design reference also drew a timeline scrubber between the ports
// and the clock. `TimelineScrubberView` still ships in this file so a
// future release can re-mount it once there is a real
// activity-replay feed, but the body deliberately omits it today: the
// scrubber had no backing data, the "replay" button fired into an
// intentionally empty closure, and the `Xs ago` label could not
// advance because nothing was publishing progress. Showing a control
// that looks interactive but does nothing would mislead the user, so
// we hide it until the replay subsystem is wired.
//
// In production, `AuroraChromeController` feeds the remaining groups
// from the live per-surface agent store and port scanner while the
// Aurora feature flag is enabled.

import SwiftUI

extension Design {

    static func localizedAgentStateLabel(
        _ state: AgentStateRole,
        using localizer: AppLocalizer
    ) -> String {
        switch state {
        case .idle:
            return localizer.string("auroraStatus.state.idle", fallback: "idle")
        case .launched:
            return localizer.string("auroraStatus.state.launched", fallback: "launching")
        case .working:
            return localizer.string("auroraStatus.state.working", fallback: "working")
        case .waiting:
            return localizer.string("auroraStatus.state.waiting", fallback: "waiting")
        case .finished:
            return localizer.string("auroraStatus.state.finished", fallback: "finished")
        case .error:
            return localizer.string("auroraStatus.state.error", fallback: "error")
        }
    }

    static func localizedPaneCount(_ count: Int, using localizer: AppLocalizer) -> String {
        let key = count == 1 ? "auroraSidebar.panes.count.one" : "auroraSidebar.panes.count.many"
        let fallback = count == 1 ? "%d pane" : "%d panes"
        return String(format: localizer.string(key, fallback: fallback), count)
    }

    static func localizedToolCount(_ count: Int, using localizer: AppLocalizer) -> String {
        let key = count == 1 ? "auroraStatus.diagnostic.tools.one" : "auroraStatus.diagnostic.tools.many"
        let fallback = count == 1 ? "%d tool" : "%d tools"
        return String(format: localizer.string(key, fallback: fallback), count)
    }

    static func localizedErrorCount(_ count: Int, using localizer: AppLocalizer) -> String {
        let key = count == 1 ? "auroraStatus.diagnostic.errors.one" : "auroraStatus.diagnostic.errors.many"
        let fallback = count == 1 ? "%d error" : "%d errors"
        return String(format: localizer.string(key, fallback: fallback), count)
    }

    static func localizedPaneDiagnosticLine(
        for pane: AuroraPane,
        using localizer: AppLocalizer
    ) -> String {
        var parts = [
            "\(pane.name) — \(localizedAgentStateLabel(pane.state, using: localizer))",
        ]
        if let activity = pane.activity?.trimmingCharacters(in: .whitespacesAndNewlines),
           !activity.isEmpty {
            parts.append(activity)
        }
        if pane.toolCount > 0 || pane.errorCount > 0 {
            parts.append(localizedToolCount(pane.toolCount, using: localizer))
            parts.append(localizedErrorCount(pane.errorCount, using: localizer))
        }
        return "• " + parts.joined(separator: " · ")
    }

    /// Status bar for the Aurora redesign. Callers bind the timeline
    /// progress so the scrubber can live-update while a replay is
    /// active.
    struct AuroraStatusBarView: View {
        let workspaces: [AuroraWorkspace]
        let ports: [AuroraPortBinding]
        @Binding var timeline: AuroraTimelineState
        let clockLabel: String
        let onReplay: () -> Void
        let onCopyPort: (AuroraPortBinding) -> Void
        let onOpenPort: (AuroraPortBinding) -> Void
        var localizer: AppLocalizer

        @Environment(\.designThemePalette) private var palette

        init(
            workspaces: [AuroraWorkspace],
            ports: [AuroraPortBinding],
            timeline: Binding<AuroraTimelineState>,
            clockLabel: String,
            onReplay: @escaping () -> Void,
            onCopyPort: @escaping (AuroraPortBinding) -> Void = { _ in },
            onOpenPort: @escaping (AuroraPortBinding) -> Void = { _ in },
            localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
        ) {
            self.workspaces = workspaces
            self.ports = ports
            self._timeline = timeline
            self.clockLabel = clockLabel
            self.onReplay = onReplay
            self.onCopyPort = onCopyPort
            self.onOpenPort = onOpenPort
            self.localizer = localizer
        }

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
                LocalBadgeView(localizer: localizer)
                separator
                AgentMatrixView(panes: Self.allPanes(in: workspaces), localizer: localizer)
                separator
                PortListView(
                    ports: ports,
                    onCopyPort: onCopyPort,
                    onOpenPort: onOpenPort,
                    localizer: localizer
                )
                // Timeline scrubber intentionally omitted. See the file
                // header: the replay subsystem that would feed it is
                // not implemented yet, and keeping a non-functional
                // control in the status bar is worse than hiding it.
                Spacer()
                Text(verbatim: clockLabel)
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

    /// Horizontal matrix of active agent state cells. Idle panes are
    /// excluded from the matrix so the status bar communicates actual
    /// running/waiting/finished/error agents instead of every split in
    /// the window. The text summary mirrors the classic status bar
    /// counters (`2 working`, `1 waiting`) and the tooltip lists the
    /// agent names so Aurora does not hide detection detail.
    struct AgentMatrixView: View {
        let panes: [AuroraPane]
        var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

        @Environment(\.designThemePalette) private var palette

        private var activePanes: [AuroraPane] {
            panes.filter(\.contributesToMatrix)
        }

        var body: some View {
            HStack(spacing: Spacing.xSmall) {
                Text(Self.localizedTitle(using: localizer))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textDim.resolvedColor())

                Text(Self.summaryText(for: panes, using: localizer))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.textDim.resolvedColor())

                HStack(spacing: 3) {
                    ForEach(activePanes) { pane in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(pane.agent.token.resolvedColor())
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(pane.state.token.resolvedColor(), lineWidth: 1)
                            )
                            .frame(width: 10, height: 10)
                            .accessibilityLabel(
                                "\(pane.name): \(Self.stateLabel(for: pane.state, using: localizer))"
                            )
                            .help(Design.localizedPaneDiagnosticLine(for: pane, using: localizer))
                    }
                }
            }
            .help(Self.agentTooltip(for: panes, using: localizer))
        }

        static func localizedTitle(using localizer: AppLocalizer) -> String {
            localizer.string("auroraStatus.agents.title", fallback: "agents")
        }

        static func summaryText(
            for panes: [AuroraPane],
            using localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
        ) -> String {
            let active = panes.filter(\.contributesToMatrix)
            guard !active.isEmpty else {
                return localizer.string("auroraStatus.summary.idle", fallback: "idle")
            }

            var working = 0
            var waiting = 0
            var errors = 0
            var finished = 0

            for pane in active {
                switch pane.state {
                case .launched, .working:
                    working += 1
                case .waiting:
                    waiting += 1
                case .error:
                    errors += 1
                case .finished:
                    finished += 1
                case .idle:
                    break
                }
            }

            var parts: [String] = []
            if working > 0 {
                let key = working == 1 ? "auroraStatus.summary.working.one" : "auroraStatus.summary.working.many"
                let fallback = working == 1 ? "%d working" : "%d working"
                parts.append(String(format: localizer.string(key, fallback: fallback), working))
            }
            if waiting > 0 {
                let key = waiting == 1 ? "auroraStatus.summary.waiting.one" : "auroraStatus.summary.waiting.many"
                let fallback = waiting == 1 ? "%d waiting" : "%d waiting"
                parts.append(String(format: localizer.string(key, fallback: fallback), waiting))
            }
            if errors > 0 {
                let key = errors == 1 ? "auroraStatus.summary.error.one" : "auroraStatus.summary.error.many"
                let fallback = errors == 1 ? "%d error" : "%d errors"
                parts.append(String(format: localizer.string(key, fallback: fallback), errors))
            }
            if finished > 0 {
                let key = finished == 1 ? "auroraStatus.summary.done.one" : "auroraStatus.summary.done.many"
                let fallback = finished == 1 ? "%d done" : "%d done"
                parts.append(String(format: localizer.string(key, fallback: fallback), finished))
            }
            return parts.joined(separator: " · ")
        }

        static func agentTooltip(
            for panes: [AuroraPane],
            using localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
        ) -> String {
            let active = panes.filter(\.contributesToMatrix)
            guard !active.isEmpty else {
                return localizer.string(
                    "auroraStatus.agents.tooltip.empty",
                    fallback: "No active agents detected in the current Aurora workspace snapshot."
                )
            }

            return String(
                format: localizer.string("auroraStatus.agents.tooltip.active", fallback: "Active agents:\n%@"),
                active.map { Design.localizedPaneDiagnosticLine(for: $0, using: localizer) }
                    .joined(separator: "\n")
            )
        }

        static func stateLabel(
            for state: AgentStateRole,
            using localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
        ) -> String {
            Design.localizedAgentStateLabel(state, using: localizer)
        }
    }

    // MARK: - Port list

    /// Displays bound local ports as compact chips with a health dot.
    struct PortListView: View {
        let ports: [AuroraPortBinding]
        let onCopyPort: (AuroraPortBinding) -> Void
        let onOpenPort: (AuroraPortBinding) -> Void
        var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

        @Environment(\.designThemePalette) private var palette
        @State private var isPopoverPresented = false

        /// Tooltip exposed on compact chips. The richer click target is
        /// the popover, but tooltips keep hover discovery lightweight.
        private var portsTooltip: String {
            Self.localizedPortsTooltip(ports, using: localizer)
        }

        var body: some View {
            HStack(spacing: Spacing.xSmall) {
                Button {
                    isPopoverPresented.toggle()
                } label: {
                    Text(Self.localizedTitle(using: localizer))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.textDim.resolvedColor())
                }
                .buttonStyle(.plain)
                .help(portsTooltip)
                .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
                    PortsPopoverView(
                        ports: ports,
                        onCopyPort: onCopyPort,
                        onOpenPort: onOpenPort,
                        localizer: localizer
                    )
                }
                if ports.isEmpty {
                    Text(Self.localizedNone(using: localizer))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.textDim.resolvedColor())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(palette.glassHighlight.resolvedColor().opacity(0.6))
                        )
                        .help(portsTooltip)
                } else {
                    ForEach(ports) { port in
                        Button {
                            onOpenPort(port)
                        } label: {
                            PortChip(port: port, localizer: localizer)
                        }
                        .buttonStyle(.plain)
                        .help(Self.localizedOpenPortHelp(port, using: localizer))
                        .contextMenu {
                            Button(Self.localizedOpenPortMenuTitle(port, using: localizer)) {
                                onOpenPort(port)
                            }
                            Button(Self.localizedCopyPortMenuTitle(port, using: localizer)) {
                                onCopyPort(port)
                            }
                        }
                        .accessibilityLabel(
                            Text(Self.localizedOpenPortAccessibility(port, using: localizer))
                        )
                    }
                }
            }
        }

        static func localizedTitle(using localizer: AppLocalizer) -> String {
            localizer.string("auroraStatus.ports.title", fallback: "ports")
        }

        static func localizedNone(using localizer: AppLocalizer) -> String {
            localizer.string("auroraStatus.ports.none", fallback: "none")
        }

        static func localizedPortsTooltip(
            _ ports: [AuroraPortBinding],
            using localizer: AppLocalizer
        ) -> String {
            guard !ports.isEmpty else {
                return localizer.string(
                    "auroraStatus.ports.tooltip.empty",
                    fallback: "Localhost ports detected by the background scanner. None are listening right now."
                )
            }
            let lines = ports.map { ":\($0.port)  \($0.name)" }.joined(separator: "\n")
            return String(
                format: localizer.string("auroraStatus.ports.tooltip.active", fallback: "Localhost ports listening right now:\n%@"),
                lines
            )
        }

        static func localizedOpenPortHelp(
            _ port: AuroraPortBinding,
            using localizer: AppLocalizer
        ) -> String {
            String(
                format: localizer.string(
                    "auroraStatus.ports.open.help",
                    fallback: "Open %@. Use the ports popover for Copy/Open actions."
                ),
                port.localhostURLString
            )
        }

        static func localizedOpenPortMenuTitle(
            _ port: AuroraPortBinding,
            using localizer: AppLocalizer
        ) -> String {
            String(
                format: localizer.string("auroraStatus.ports.open.menu", fallback: "Open %@"),
                port.localhostURLString
            )
        }

        static func localizedCopyPortMenuTitle(
            _ port: AuroraPortBinding,
            using localizer: AppLocalizer
        ) -> String {
            String(
                format: localizer.string("auroraStatus.ports.copy.menu", fallback: "Copy %@"),
                port.localhostURLString
            )
        }

        static func localizedOpenPortAccessibility(
            _ port: AuroraPortBinding,
            using localizer: AppLocalizer
        ) -> String {
            String(
                format: localizer.string("auroraStatus.ports.open.accessibility", fallback: "Open local port %d, %@"),
                port.port,
                port.name
            )
        }
    }

    struct PortsPopoverView: View {
        let ports: [AuroraPortBinding]
        let onCopyPort: (AuroraPortBinding) -> Void
        let onOpenPort: (AuroraPortBinding) -> Void
        var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

        @Environment(\.designThemePalette) private var palette

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(Self.localizedTitle(using: localizer))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textHigh.resolvedColor())

                if ports.isEmpty {
                    Text(Self.localizedEmptyMessage(using: localizer))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textDim.resolvedColor())
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(ports) { port in
                        HStack(spacing: Spacing.small) {
                            PortChip(port: port, localizer: localizer)
                            Spacer(minLength: Spacing.large)
                            Button(Self.localizedCopyButton(using: localizer)) { onCopyPort(port) }
                                .buttonStyle(.borderless)
                            Button(Self.localizedOpenButton(using: localizer)) { onOpenPort(port) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .padding(Spacing.large)
            .frame(minWidth: 280, alignment: .leading)
            .background(palette.backgroundSecondary.resolvedColor())
        }

        static func localizedTitle(using localizer: AppLocalizer) -> String {
            localizer.string("auroraStatus.ports.popover.title", fallback: "Local ports")
        }

        static func localizedEmptyMessage(using localizer: AppLocalizer) -> String {
            localizer.string(
                "auroraStatus.ports.popover.empty",
                fallback: "No localhost services are listening right now."
            )
        }

        static func localizedCopyButton(using localizer: AppLocalizer) -> String {
            localizer.string("common.copy", fallback: "Copy")
        }

        static func localizedOpenButton(using localizer: AppLocalizer) -> String {
            localizer.string("common.open", fallback: "Open")
        }
    }

    struct PortChip: View {
        let port: AuroraPortBinding
        var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

        @Environment(\.designThemePalette) private var palette

        var body: some View {
            HStack(spacing: 4) {
                Circle()
                    .fill(port.stateRole.token.resolvedColor())
                    .frame(width: 5, height: 5)
                // SwiftUI `Text` with a plain string literal is treated
                // as a `LocalizedStringKey`, which runs number
                // localization over any `Int` interpolated into it. A
                // port like 8080 ends up rendered as "8,080" in locales
                // that use a thousands separator. `Text(verbatim:)` opts
                // out so the chip shows raw digits — the shape every
                // developer expects for a network port.
                Text(verbatim: ":\(port.port)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.textMedium.resolvedColor())
                Text(verbatim: port.name)
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
            .accessibilityLabel(
                Text(Self.localizedAccessibilityLabel(port, using: localizer))
            )
        }

        static func localizedAccessibilityLabel(
            _ port: AuroraPortBinding,
            using localizer: AppLocalizer
        ) -> String {
            String(
                format: localizer.string("auroraStatus.portChip.accessibility", fallback: "Port %d named %@, state %@"),
                port.port,
                port.name,
                localizedHealthLabel(port.health, using: localizer)
            )
        }

        static func localizedHealthLabel(
            _ health: AuroraPortBinding.Health,
            using localizer: AppLocalizer
        ) -> String {
            switch health {
            case .ok:
                return localizer.string("auroraStatus.port.health.ok", fallback: "ok")
            case .idle:
                return localizer.string("auroraStatus.port.health.idle", fallback: "idle")
            case .error:
                return localizer.string("auroraStatus.port.health.error", fallback: "error")
            }
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
        var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

        @Environment(\.designThemePalette) private var palette

        private let barWidth: CGFloat = 180

        var body: some View {
            HStack(spacing: Spacing.xSmall) {
                Text(Self.localizedTitle(using: localizer))
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
                    Text(Self.localizedReplayButton(using: localizer))
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
                .accessibilityLabel(Self.localizedReplayAccessibility(timeline, using: localizer))
            }
        }

        static func localizedTitle(using localizer: AppLocalizer) -> String {
            localizer.string("auroraStatus.timeline.title", fallback: "timeline")
        }

        static func localizedReplayButton(using localizer: AppLocalizer) -> String {
            localizer.string("auroraStatus.timeline.replay", fallback: "▶ replay")
        }

        static func localizedReplayAccessibility(
            _ timeline: AuroraTimelineState,
            using localizer: AppLocalizer
        ) -> String {
            String(
                format: localizer.string("auroraStatus.timeline.replay.accessibility", fallback: "Replay last %d seconds"),
                Int(timeline.windowSeconds)
            )
        }
    }
}
