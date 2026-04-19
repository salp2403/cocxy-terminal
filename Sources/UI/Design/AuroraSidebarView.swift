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
//             sidebarHeader (title + command palette + new-tab buttons)
//             searchField
//             ScrollView { workspaceTree }
//             sidebarFooter (100% local badge + palette kbd hint)
//
// The view is additive: no existing chrome imports it yet. A follow-up
// commit will introduce an adapter that maps the live `TabManager` +
// `AgentStatePerSurfaceStore` state into `[AuroraWorkspace]` so the
// sidebar can replace `TabBarView` incrementally.

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
        @Binding var activeSessionID: String?
        @State private var query: String = ""

        let onTogglePalette: () -> Void
        let onCreateTab: () -> Void
        let onActivateSession: (String) -> Void

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
        }

        // MARK: - Header

        private var sidebarHeader: some View {
            HStack(spacing: Spacing.hairline) {
                Text("WORKSPACES")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.7)
                    .foregroundStyle(palette.textLow.resolvedColor())

                Spacer()

                trayButton(
                    label: paletteShortcutLabel,
                    help: "Command palette (\(paletteShortcutLabel))",
                    action: onTogglePalette
                )
                trayButton(
                    label: "+",
                    help: "New tab (\(newTabShortcutLabel))",
                    action: onCreateTab
                )
            }
            .padding(.horizontal, Spacing.xxSmall)
            .padding(.top, Spacing.hairline)
        }

        private func trayButton(label: String, help: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(label)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.textLow.resolvedColor())
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                                isActive: session.id == activeSessionID,
                                onActivate: { onActivateSession(session.id) }
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
        /// a second copy of the "100% local" badge that the Aurora
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
    }

    // MARK: - Session node

    /// Single session card in the tree. Active state highlights with
    /// an accent tint + soft glow; hovered state bumps the background
    /// one step.
    struct SessionNodeView: View {
        let session: AuroraSession
        let isActive: Bool
        let onActivate: () -> Void

        @Environment(\.designThemePalette) private var palette
        @State private var isHovered = false

        var body: some View {
            Button(action: onActivate) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Spacing.xSmall) {
                        AgentChipView(agent: session.agent, state: session.state, size: 22)
                        Text(session.name)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(palette.textHigh.resolvedColor())
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        MiniMatrixView(panes: session.matrixPanes)
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
                .overlay(borderView)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering in isHovered = hovering }
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
                        ? palette.accent.withAlpha(0.10).resolvedColor()
                        : (isHovered ? palette.glassHighlight.resolvedColor() : Color.clear)
                )
        }

        @ViewBuilder
        private var borderView: some View {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isActive
                        ? palette.accent.withAlpha(0.40).resolvedColor()
                        : Color.clear,
                    lineWidth: 1
                )
        }
    }

    // MARK: - Mini matrix

    /// Tiny horizontal matrix of pane status cells rendered next to
    /// the session name. One cell per pane, coloured by state.
    struct MiniMatrixView: View {
        let panes: [AuroraPane]

        var body: some View {
            HStack(spacing: 3) {
                ForEach(panes) { pane in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(pane.state.token.resolvedColor())
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: - Local badge

    /// "100% local" status badge used by both the sidebar footer and
    /// the Aurora status bar's leftmost chip.
    struct LocalBadgeView: View {
        @Environment(\.designThemePalette) private var palette

        var body: some View {
            let finished = AgentStateRole.finished.token.resolvedColor()
            HStack(spacing: Spacing.xxSmall) {
                Circle()
                    .fill(finished)
                    .frame(width: 6, height: 6)
                    .shadow(color: finished.opacity(0.7), radius: 3)
                Text("100% local")
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
        }
    }
}
