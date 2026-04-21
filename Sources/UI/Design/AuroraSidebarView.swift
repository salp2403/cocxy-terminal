// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraSidebarView.swift - Redesigned sidebar for the Aurora chrome.
//
// Renders the workspaces → sessions → panes tree that replaces the
// current flat tab list. Consumes `Design.AuroraWorkspace` snapshots
// so the view stays decoupled from the production `TabManager`
// during the migration phase.
//
// Composition:
//
//     Design.GlassSurface
//         VStack
//             sidebarHeader (title + command palette + notification + new-tab buttons)
//             searchField
//             ScrollView { workspaceTree }
//             sidebarFooter (palette kbd hint)
//
// In production this view is mounted by `AuroraChromeController` when
// `appearance.aurora-enabled` is true. The controller supplies live
// `TabManager` + `AgentStatePerSurfaceStore` snapshots through
// `AuroraSourceBuilder` / `AuroraWorkspaceAdapter`.

import SwiftUI

extension Design {

    /// Redesigned sidebar view. Accepts a list of workspaces plus a
    /// handful of callbacks the host wires to real actions.
    ///
    /// `paletteShortcutLabel` / `newTabShortcutLabel` are caller-supplied
    /// so the header tray reflects the live keybindings. Defaults match
    /// `KeybindingActionCatalog.windowCommandPalette.defaultShortcut`
    /// (⌘⇧P) and `.tabNew.defaultShortcut` (⌘T) so previews / tests
    /// render with the catalog baseline without booting the binder.
    struct AuroraSidebarView: View {
        @Binding var workspaces: [AuroraWorkspace]
        /// Session id of the currently active tab. This is a plain
        /// snapshot value instead of a child-owned binding because the
        /// sidebar never mutates selection directly; it only renders the
        /// active row that the controller resolved from the live tab
        /// manager snapshot.
        let activeSessionID: String?
        @State private var query: String = ""
        @State private var hoveredSession: HoveredSessionContext?
        @State private var sessionFrames: [String: CGRect] = [:]

        let onTogglePalette: () -> Void
        let onCreateTab: () -> Void
        let onActivateSession: (String) -> Void
        var onCloseSession: ((String) -> Void)? = nil
        var onTogglePinSession: ((String) -> Void)? = nil
        var onCloseOtherSessions: ((String) -> Void)? = nil
        var onMoveSessionUp: ((String) -> Void)? = nil
        var onMoveSessionDown: ((String) -> Void)? = nil
        /// Optional callback for the notification tray button. Stays
        /// optional so tests and previews that do not care about the
        /// notification center can omit it; the header renders the
        /// bell glyph when a handler is provided.
        var onToggleNotifications: (() -> Void)? = nil
        /// Emits hover state to the window-level overlay. The tooltip is
        /// intentionally rendered outside this sidebar view so it never
        /// covers rows or steals navigation/context-menu interactions.
        var onHoverSession: ((AuroraSidebarTooltipSnapshot?) -> Void)? = nil

        var paletteShortcutLabel: String = "⇧⌘P"
        var newTabShortcutLabel: String = "⌘T"

        @Environment(\.designThemePalette) private var palette

        var body: some View {
            GlassSurface(cornerRadius: .large) {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    sidebarHeader
                    searchField

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: Spacing.hairline) {
                            ForEach(workspaces) { workspace in
                                workspaceBlock(for: workspace)
                            }
                        }
                        .padding(.horizontal, Spacing.hairline)
                    }

                    sidebarFooter
                }
                .padding(Spacing.large)
            }
            // The sidebar fills whatever container the host provides so
            // the NSHostingView frame (matched to the classic sidebar's
            // bounds when Aurora is mounted as an overlay) controls the
            // actual width. Previews and tests that want a pinned width
            // can wrap the view in their own `.frame(width: ...)`.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: Self.coordinateSpaceName)
            .onPreferenceChange(SessionFramePreferenceKey.self) { frames in
                sessionFrames = frames
                publishHoveredSessionIfPossible()
            }
        }

        fileprivate static let coordinateSpaceName = "AuroraSidebarCoordinateSpace"

        // MARK: - Header

        private var sidebarHeader: some View {
            HStack(spacing: Spacing.hairline) {
                Text("WORKSPACES")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.7)
                    .foregroundStyle(palette.textLow.resolvedColor())

                Spacer()

                trayIconButton(
                    systemImage: "command",
                    help: "Command palette (\(paletteShortcutLabel))",
                    action: onTogglePalette
                )
                if let onToggleNotifications {
                    trayIconButton(
                        systemImage: "bell",
                        help: "Notifications",
                        action: onToggleNotifications
                    )
                }
                trayIconButton(
                    systemImage: "plus",
                    help: "New tab (\(newTabShortcutLabel))",
                    action: onCreateTab
                )
            }
            .padding(.horizontal, Spacing.xxSmall)
            .padding(.top, Spacing.hairline)
        }

        /// Sidebar header tray button backed by an SF Symbol. The
        /// previous text-glyph buttons (`⇧⌘P`, `◉`, `+`) failed to
        /// stand out against the glass backdrop at 11pt — users
        /// reported them as near-invisible. SF Symbols render with
        /// the system's high-contrast weight and scale with the
        /// Dynamic Type baseline, which makes them legible over any
        /// backdrop.
        private func trayIconButton(
            systemImage: String,
            help: String,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textHigh.resolvedColor())
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(palette.glassHighlight.resolvedColor())
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(help)
        }

        // MARK: - Search

        private var searchField: some View {
            HStack(spacing: Spacing.xSmall) {
                Text("⌕")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textLow.resolvedColor())
                TextField("Filter sessions…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textHigh.resolvedColor())
            }
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.glassHighlight.resolvedColor())
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(palette.glassBorder.resolvedColor(), lineWidth: 1)
                    )
            )
        }

        // MARK: - Workspace tree

        @ViewBuilder
        private func workspaceBlock(for workspace: AuroraWorkspace) -> some View {
            let filtered = workspace.filteringSessions(by: query)
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                workspaceRow(workspace)
                if !workspace.isCollapsed {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(filtered.sessions) { session in
                            SessionNodeView(
                                session: session,
                                workspaceName: workspace.name,
                                workspaceBranch: workspace.branch,
                                isActive: session.id == activeSessionID,
                                onActivate: { onActivateSession(session.id) },
                                onClose: onCloseSession.map { handler in
                                    { handler(session.id) }
                                },
                                onTogglePin: onTogglePinSession.map { handler in
                                    { handler(session.id) }
                                },
                                onCloseOthers: onCloseOtherSessions.map { handler in
                                    { handler(session.id) }
                                },
                                onMoveUp: onMoveSessionUp.map { handler in
                                    { handler(session.id) }
                                },
                                onMoveDown: onMoveSessionDown.map { handler in
                                    { handler(session.id) }
                                },
                                onHoverChange: { hovering in
                                    if hovering {
                                        hoveredSession = HoveredSessionContext(
                                            session: session,
                                            workspaceName: workspace.name,
                                            workspaceBranch: workspace.branch
                                        )
                                        publishHoveredSessionIfPossible()
                                    } else if hoveredSession?.session.id == session.id {
                                        hoveredSession = nil
                                        onHoverSession?(nil)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.top, Spacing.hairline)
                    .padding(.bottom, Spacing.xSmall)
                }
            }
        }

        private func workspaceRow(_ workspace: AuroraWorkspace) -> some View {
            Button(action: { toggleCollapsed(workspace.id) }) {
                HStack(spacing: Spacing.xSmall) {
                    Text("▾")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.textLow.resolvedColor())
                        .rotationEffect(.degrees(workspace.isCollapsed ? -90 : 0))
                        .animation(.easeInOut(duration: 0.18), value: workspace.isCollapsed)
                    Text(workspace.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.textHigh.resolvedColor())
                    Spacer()
                    if let branch = workspace.branch {
                        Text(branch)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(palette.textLow.resolvedColor())
                    }
                }
                .padding(.horizontal, Spacing.xSmall)
                .padding(.vertical, Spacing.xxSmall)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }

        private func toggleCollapsed(_ workspaceID: String) {
            guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
            workspaces[index].isCollapsed.toggle()
        }

        // MARK: - Footer

        /// Footer shown at the bottom of the sidebar. Originally carried
        /// a second copy of the privacy badge that the Aurora
        /// status bar already renders at the bottom of the window — one
        /// badge per window is enough. The footer now only surfaces the
        /// palette shortcut hint (live-resolved from the host so
        /// rebindings propagate immediately).
        private var sidebarFooter: some View {
            HStack(spacing: Spacing.small) {
                Spacer()
                Text(paletteShortcutLabel)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.textLow.resolvedColor())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(palette.glassHighlight.resolvedColor())
                    )
            }
            .padding(.horizontal, Spacing.xxSmall)
            .padding(.top, Spacing.xSmall)
        }

        private func publishHoveredSessionIfPossible() {
            guard let hoveredSession else {
                onHoverSession?(nil)
                return
            }
            guard let frame = sessionFrames[hoveredSession.session.id] else {
                onHoverSession?(nil)
                return
            }
            onHoverSession?(
                AuroraSidebarTooltipSnapshot(
                    session: hoveredSession.session,
                    workspaceName: hoveredSession.workspaceName,
                    workspaceBranch: hoveredSession.workspaceBranch,
                    rowFrame: frame
                )
            )
        }
    }

    // MARK: - Session node

    /// Single session card in the tree. Active state highlights with
    /// an accent tint + soft glow; hovered state bumps the background
    /// one step.
    struct SessionNodeView: View {
        let session: AuroraSession
        let workspaceName: String
        let workspaceBranch: String?
        let isActive: Bool
        let onActivate: () -> Void
        var onClose: (() -> Void)? = nil
        var onTogglePin: (() -> Void)? = nil
        var onCloseOthers: (() -> Void)? = nil
        var onMoveUp: (() -> Void)? = nil
        var onMoveDown: (() -> Void)? = nil
        var onHoverChange: (Bool) -> Void = { _ in }

        @Environment(\.designThemePalette) private var palette
        @State private var isHovered = false

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Spacing.xSmall) {
                    AgentChipView(agent: session.agent, state: session.state, size: 22)
                    Text(session.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.textHigh.resolvedColor())
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if session.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(palette.textLow.resolvedColor())
                            .accessibilityLabel("Pinned")
                    }
                    Spacer()
                    MiniMatrixView(panes: session.matrixPanes)
                    if let onClose, !session.isPinned {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(palette.textLow.resolvedColor())
                                .frame(width: 18, height: 18)
                                .background(
                                    Circle()
                                        .fill(palette.glassHighlight.resolvedColor())
                                )
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Close tab")
                        .accessibilityLabel("Close \(session.name)")
                        .opacity(isActive || isHovered ? 0.95 : 0.55)
                    }
                }
                HStack(spacing: Spacing.xxSmall) {
                    Circle()
                        .fill(session.state.token.resolvedColor())
                        .frame(width: 7, height: 7)
                    Text(stateLabel)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.textLow.resolvedColor())
                    Text("·")
                        .foregroundStyle(palette.textLow.resolvedColor().opacity(0.5))
                    Text(session.paneCountLabel)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.textLow.resolvedColor())
                }
                .padding(.leading, 30)
            }
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, 8)
            .background(backgroundView)
            .background(SessionFrameReporter(sessionID: session.id))
            .overlay(borderView)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onTapGesture(perform: onActivate)
            .onHover { hovering in
                isHovered = hovering
                onHoverChange(hovering)
            }
            .contextMenu { contextMenuContent }
            .padding(.leading, 12)
        }

        private var stateLabel: String {
            switch session.state {
            case .idle: return "idle"
            case .launched: return "launched"
            case .working: return "working"
            case .waiting: return "waiting"
            case .finished: return "finished"
            case .error: return "error"
            }
        }

        @ViewBuilder
        private var backgroundView: some View {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isActive
                        ? session.agent.token.withAlpha(0.14).resolvedColor()
                        : (isHovered ? palette.glassHighlight.resolvedColor() : Color.clear)
                )
        }

        @ViewBuilder
        private var borderView: some View {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isActive
                        ? session.agent.token.withAlpha(0.55).resolvedColor()
                        : Color.clear,
                    lineWidth: isActive ? 1.5 : 1
                )
        }

        @ViewBuilder
        private var contextMenuContent: some View {
            if let onTogglePin {
                Button(session.isPinned ? "Unpin Tab" : "Pin Tab", action: onTogglePin)
            }
            if let onClose {
                Button("Close Tab", action: onClose)
                    .disabled(session.isPinned)
            }
            if let onCloseOthers {
                Button("Close Other Tabs", action: onCloseOthers)
            }
            if onMoveUp != nil || onMoveDown != nil {
                Divider()
            }
            if let onMoveUp {
                Button("Move Tab Up", action: onMoveUp)
            }
            if let onMoveDown {
                Button("Move Tab Down", action: onMoveDown)
            }
        }
    }

    private struct HoveredSessionContext: Equatable {
        let session: AuroraSession
        let workspaceName: String
        let workspaceBranch: String?
    }

    private struct SessionFramePreferenceKey: PreferenceKey {
        static let defaultValue: [String: CGRect] = [:]

        static func reduce(
            value: inout [String: CGRect],
            nextValue: () -> [String: CGRect]
        ) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }

    private struct SessionFrameReporter: View {
        let sessionID: String

        var body: some View {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SessionFramePreferenceKey.self,
                    value: [
                        sessionID: proxy.frame(
                            in: .named(AuroraSidebarView.coordinateSpaceName)
                        ),
                    ]
                )
            }
        }
    }

    // MARK: - Session inspector tooltip

    /// Rich hover inspector for a sidebar session. This intentionally
    /// replaces the system `.help` string for session rows: the
    /// native tooltip was useful for quick debugging but too plain and
    /// cramped for a product surface that needs to summarize multiple
    /// split panes and agents at a glance.
    struct AuroraSessionTooltipCard: View {
        let session: AuroraSession
        let workspaceName: String
        let workspaceBranch: String?

        @Environment(\.designThemePalette) private var palette

        var body: some View {
            GlassSurface(cornerRadius: .large, tint: session.agent.token.withAlpha(0.16)) {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    metrics
                    contextBlock
                    panesBlock
                    footer
                }
                .padding(14)
            }
            .padding(1)
        }

        private var header: some View {
            HStack(alignment: .center, spacing: 10) {
                AgentChipView(agent: session.agent, state: session.state, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.textHigh.resolvedColor())
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(agentLabel(session.agent))
                        Text("·")
                        Text(session.state.rawValue)
                    }
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(session.agent.token.resolvedColor())
                }
                Spacer()
                Text(session.paneCountLabel)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.textMedium.resolvedColor())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(palette.glassHighlight.resolvedColor())
                    )
            }
        }

        private var metrics: some View {
            HStack(spacing: 8) {
                metricChip("live", "\(session.activePaneCount)")
                metricChip("tools", "\(session.totalToolCount)")
                metricChip("errors", "\(session.totalErrorCount)", isWarning: session.totalErrorCount > 0)
            }
        }

        private func metricChip(_ label: String, _ value: String, isWarning: Bool = false) -> some View {
            let color = isWarning ? AgentStateRole.error.token.resolvedColor() : session.agent.token.resolvedColor()
            return HStack(spacing: 5) {
                Text(value)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textLow.resolvedColor())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(color.opacity(0.25), lineWidth: 1)
                    )
            )
        }

        private var contextBlock: some View {
            VStack(alignment: .leading, spacing: 7) {
                infoLine(icon: "square.stack.3d.up", label: "Workspace", value: workspaceSummary)
                if let process = cleaned(session.foregroundProcessName) {
                    infoLine(icon: "cpu", label: "Process", value: process)
                }
                if let directory = cleaned(session.workingDirectory) {
                    infoLine(icon: "folder", label: "Directory", value: prettyDirectory(directory))
                }
                if let command = cleaned(session.lastCommandSummary) {
                    infoLine(icon: "terminal", label: "Command", value: command)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.backgroundSecondary.withAlpha(0.72).resolvedColor())
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(palette.glassBorder.resolvedColor(), lineWidth: 1)
                    )
            )
        }

        private func infoLine(icon: String, label: String, value: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(session.agent.token.resolvedColor())
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.textLow.resolvedColor())
                    .frame(width: 62, alignment: .leading)
                Text(value)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textMedium.resolvedColor())
                    .lineLimit(2)
            }
        }

        @ViewBuilder
        private var panesBlock: some View {
            if session.matrixPanes.isEmpty {
                emptyPanes
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Live panes")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(palette.textLow.resolvedColor())
                    ForEach(session.matrixPanes.prefix(5)) { pane in
                        paneLine(pane)
                    }
                    if session.matrixPanes.count > 5 {
                        Text("+ \(session.matrixPanes.count - 5) more active panes")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.textLow.resolvedColor())
                    }
                }
            }
        }

        private var emptyPanes: some View {
            HStack(spacing: 8) {
                Circle()
                    .fill(AgentStateRole.idle.token.resolvedColor())
                    .frame(width: 7, height: 7)
                Text("All panes are idle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.textLow.resolvedColor())
            }
        }

        private func paneLine(_ pane: AuroraPane) -> some View {
            HStack(spacing: 8) {
                AgentChipView(agent: pane.agent, state: pane.state, size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pane.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.textHigh.resolvedColor())
                        .lineLimit(1)
                    Text(paneSubtitle(pane))
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.textLow.resolvedColor())
                        .lineLimit(1)
                }
                Spacer()
                Circle()
                    .fill(pane.state.token.resolvedColor())
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(pane.agent.token.withAlpha(0.09).resolvedColor())
            )
        }

        private var footer: some View {
            Text("Click the row to focus · use × to close")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.textDim.resolvedColor())
        }

        private var workspaceSummary: String {
            if let branch = workspaceBranch, !branch.isEmpty {
                return "\(workspaceName) · \(branch)"
            }
            return workspaceName
        }

        private func paneSubtitle(_ pane: AuroraPane) -> String {
            var parts = [pane.state.rawValue]
            if let activity = cleaned(pane.activity) {
                parts.append(activity)
            }
            if pane.toolCount > 0 || pane.errorCount > 0 {
                parts.append("tools \(pane.toolCount)")
                parts.append("errors \(pane.errorCount)")
            }
            return parts.joined(separator: " · ")
        }

        private func cleaned(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return nil
            }
            return value
        }

        private func prettyDirectory(_ path: String) -> String {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            if path == home { return "~" }
            if path.hasPrefix(home + "/") {
                return "~" + path.dropFirst(home.count)
            }
            return path
        }

        private func agentLabel(_ agent: AgentAccent) -> String {
            switch agent {
            case .claude: return "Claude Code"
            case .codex: return "Codex"
            case .gemini: return "Gemini"
            case .aider: return "Aider"
            case .shell: return "Shell"
            }
        }
    }

    // MARK: - Mini matrix

    /// Tiny horizontal matrix rendered next to the session name. One
    /// cell per active pane, filled with the agent accent and outlined
    /// with the lifecycle-state color so Claude/Codex/Gemini identity
    /// stays visible even when several panes are all `working`.
    struct MiniMatrixView: View {
        let panes: [AuroraPane]

        var body: some View {
            HStack(spacing: 3) {
                ForEach(panes) { pane in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(pane.agent.token.resolvedColor())
                        .overlay(
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(pane.state.token.resolvedColor(), lineWidth: 0.8)
                        )
                        .frame(width: 6, height: 6)
                        .help(pane.diagnosticLine)
                }
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: - Local badge

    /// Privacy status badge used by the Aurora status bar's leftmost
    /// chip. Keep the copy scoped to telemetry, not execution locality:
    /// Cocxy supports explicit remote sessions, so "100% local" would
    /// overstate the runtime model whenever SSH features are active.
    struct LocalBadgeView: View {
        @Environment(\.designThemePalette) private var palette

        var body: some View {
            let finished = AgentStateRole.finished.token.resolvedColor()
            HStack(spacing: Spacing.xxSmall) {
                Circle()
                    .fill(finished)
                    .frame(width: 6, height: 6)
                    .shadow(color: finished.opacity(0.7), radius: 3)
                Text("no telemetry")
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(finished)
            }
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(finished.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .strokeBorder(finished.opacity(0.35), lineWidth: 1)
                    )
            )
            .help("Cocxy does not phone home. Remote panes connect only when you explicitly open them.")
            .accessibilityLabel("No telemetry: Cocxy does not phone home")
        }
    }
}
