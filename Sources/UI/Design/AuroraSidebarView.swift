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
import UniformTypeIdentifiers

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
        let workspaces: [AuroraWorkspace]
        /// Session id of the currently active tab. This is a plain
        /// snapshot value instead of a child-owned binding because the
        /// sidebar never mutates selection directly; it only renders the
        /// active row that the controller resolved from the live tab
        /// manager snapshot.
        let activeSessionID: String?
        /// Per-workspace notes summaries keyed by
        /// `NoteWorkspaceID.rawValue`. Empty (`[:]`) hides every notes
        /// section so the sidebar stays bit-for-bit identical to the
        /// pre-notes layout when the feature is disabled, the provider
        /// is unwired, or no workspace currently has notes.
        var notesByWorkspace: [String: AuroraWorkspaceNotesSummary] = [:]
        @State private var query: String = ""
        @State private var hoveredSession: HoveredSessionContext?
        @State private var sessionFrames: [String: CGRect] = [:]
        @State private var workspaceDisclosure = AuroraWorkspaceDisclosureOverrides()
        @State private var notesExpansion: [String: Bool] = [:]

        let onTogglePalette: () -> Void
        let onCreateTab: () -> Void
        let onActivateSession: (String) -> Void
        var onCloseSession: ((String) -> Void)? = nil
        var onTogglePinSession: ((String) -> Void)? = nil
        var onCloseOtherSessions: ((String) -> Void)? = nil
        var onMoveSessionUp: ((String) -> Void)? = nil
        var onMoveSessionDown: ((String) -> Void)? = nil
        var onMoveSessionBefore: ((String, String) -> Void)? = nil
        var onMovePaneToSession: ((String, String) -> Void)? = nil
        /// Optional callback for the notification tray button. Stays
        /// optional so tests and previews that do not care about the
        /// notification center can omit it; the header renders the
        /// bell glyph when a handler is provided.
        var onToggleNotifications: (() -> Void)? = nil
        /// Optional callback for the notes tray button. Stays optional
        /// so tests, previews, and configurations with `[notes].enabled
        /// = false` can omit it; the header renders the note glyph
        /// only when a handler is provided so the affordance disappears
        /// when the feature is turned off instead of leaking a button
        /// that does nothing.
        var onToggleNotes: (() -> Void)? = nil
        /// Optional callback when the user picks a note row in the
        /// per-workspace notes section. First parameter is the
        /// `NoteWorkspaceID.rawValue`; second is the note's UUID
        /// rendered as a string. Stays optional so configurations
        /// without notes wiring (no provider, feature disabled) hide
        /// every section's row click instead of triggering a no-op
        /// handler.
        var onOpenNote: ((String, String) -> Void)? = nil
        /// Optional callback shown only when `availableUpdate` exists.
        /// The host routes this to Sparkle's user-initiated update check.
        var onInstallUpdate: (() -> Void)? = nil
        /// Emits hover state to the window-level overlay. The tooltip is
        /// intentionally rendered outside this sidebar view so it never
        /// covers rows or steals navigation/context-menu interactions.
        var onHoverSession: ((AuroraSidebarTooltipSnapshot?) -> Void)? = nil

        var availableUpdate: CocxyUpdateAvailability? = nil
        var displayMode: AuroraSidebarDisplayMode = .detailed
        var primaryInfo: AuroraSidebarPrimaryInfo = .state
        var onDisplayModeChange: ((AuroraSidebarDisplayMode) -> Void)? = nil
        var onPrimaryInfoChange: ((AuroraSidebarPrimaryInfo) -> Void)? = nil
        var paletteShortcutLabel: String = "⇧⌘P"
        var newTabShortcutLabel: String = "⌘T"
        var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

        @Environment(\.designThemePalette) private var palette

        var body: some View {
            GlassSurface(cornerRadius: .large) {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    sidebarHeader
                    VerticalTabSearchBar(query: $query, localizer: localizer)
                    VerticalTabControlBar(
                        displayMode: displayMode,
                        primaryInfo: primaryInfo,
                        localizer: localizer,
                        onDisplayModeChange: onDisplayModeChange,
                        onPrimaryInfoChange: onPrimaryInfoChange
                    )
                    if let availableUpdate, let onInstallUpdate {
                        updateCallout(availableUpdate, action: onInstallUpdate)
                    }

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
            .onChange(of: workspaces.map(\.id)) { _, workspaceIDs in
                workspaceDisclosure.prune(validWorkspaceIDs: workspaceIDs)
            }
        }

        fileprivate static let coordinateSpaceName = "AuroraSidebarCoordinateSpace"

        // MARK: - Header

        private var sidebarHeader: some View {
            HStack(spacing: Spacing.hairline) {
                Text(Self.localizedWorkspacesTitle(using: localizer))
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.7)
                    .foregroundStyle(palette.textLow.resolvedColor())

                Spacer()

                trayIconButton(
                    systemImage: "command",
                    help: Self.localizedCommandPaletteHelp(shortcut: paletteShortcutLabel, using: localizer),
                    action: onTogglePalette
                )
                if let onToggleNotes {
                    trayIconButton(
                        systemImage: "note.text",
                        help: Self.localizedToggleNotesHelp(using: localizer),
                        action: onToggleNotes
                    )
                }
                if let onToggleNotifications {
                    trayIconButton(
                        systemImage: "bell",
                        help: Self.localizedNotificationsHelp(using: localizer),
                        action: onToggleNotifications
                    )
                }
                trayIconButton(
                    systemImage: "plus",
                    help: Self.localizedNewTabHelp(shortcut: newTabShortcutLabel, using: localizer),
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

        private func updateCallout(
            _ update: CocxyUpdateAvailability,
            action: @escaping () -> Void
        ) -> some View {
            HStack(spacing: Spacing.xSmall) {
                Image(systemName: update.isCritical ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.accent.resolvedColor())
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.localizedUpdateTitle(update, using: localizer))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.textHigh.resolvedColor())
                        .lineLimit(1)
                    Text(update.sidebarVersionLabel)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.textLow.resolvedColor())
                        .lineLimit(1)
                }

                Spacer(minLength: Spacing.xSmall)

                Button(action: action) {
                    Text(Self.localizedUpdateButton(using: localizer))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.backgroundPrimary.resolvedColor())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(palette.accent.resolvedColor())
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.localizedUpdateAccessibility(update, using: localizer))
                .help(Self.localizedUpdateHelp(update, using: localizer))
            }
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.glassHighlight.resolvedColor())
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(palette.accent.resolvedColor().opacity(0.45), lineWidth: 1)
                    )
            )
        }

        static func localizedWorkspacesTitle(using localizer: AppLocalizer) -> String {
            localizer.string("tabbar.workspaces", fallback: "WORKSPACES")
        }

        static func localizedCommandPaletteHelp(shortcut: String, using localizer: AppLocalizer) -> String {
            String(
                format: localizer.string("auroraSidebar.commandPalette.help", fallback: "Command palette (%@)"),
                shortcut
            )
        }

        static func localizedToggleNotesHelp(using localizer: AppLocalizer) -> String {
            localizer.string("auroraSidebar.notes.help", fallback: "Toggle notes for this workspace")
        }

        static func localizedNotificationsHelp(using localizer: AppLocalizer) -> String {
            localizer.string("tabbar.notifications.title", fallback: "Notifications")
        }

        static func localizedNewTabHelp(shortcut: String, using localizer: AppLocalizer) -> String {
            String(
                format: localizer.string("auroraSidebar.newTab.help", fallback: "New tab (%@)"),
                shortcut
            )
        }

        static func localizedUpdateTitle(_ update: CocxyUpdateAvailability, using localizer: AppLocalizer) -> String {
            update.isCritical
                ? localizer.string("update.critical.title", fallback: "Critical update")
                : localizer.string("update.available.title", fallback: "Update available")
        }

        static func localizedUpdateButton(using localizer: AppLocalizer) -> String {
            localizer.string("tabbar.update.button", fallback: "Update")
        }

        static func localizedUpdateAccessibility(
            _ update: CocxyUpdateAvailability,
            using localizer: AppLocalizer
        ) -> String {
            "\(localizedUpdateTitle(update, using: localizer)): \(update.sidebarVersionLabel)"
        }

        static func localizedUpdateHelp(_ update: CocxyUpdateAvailability, using localizer: AppLocalizer) -> String {
            String(
                format: localizer.string("tabbar.update.help", fallback: "Update Cocxy Terminal to %@"),
                update.sidebarVersionLabel
            )
        }

        // MARK: - Workspace tree

        @ViewBuilder
        private func workspaceBlock(for workspace: AuroraWorkspace) -> some View {
            let filtered = workspace.filteringSessions(by: query)
            let isCollapsed = workspaceDisclosure.isCollapsed(workspace)
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                workspaceRow(workspace, isCollapsed: isCollapsed)
                if !isCollapsed {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(filtered.sessions) { session in
                            SessionNodeView(
                                session: session,
                                workspaceName: workspace.name,
                                workspaceBranch: workspace.branch,
                                isActive: session.id == activeSessionID,
                                displayMode: displayMode,
                                primaryInfo: primaryInfo,
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
                                onMoveSessionBefore: onMoveSessionBefore.map { handler in
                                    { sourceSessionID in
                                        handler(sourceSessionID, session.id)
                                    }
                                },
                                onMovePaneToSession: onMovePaneToSession.map { handler in
                                    { paneID in
                                        handler(paneID, session.id)
                                    }
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
                                },
                                localizer: localizer
                            )
                        }
                        notesSection(for: workspace)
                    }
                    .padding(.top, Spacing.hairline)
                    .padding(.bottom, Spacing.xSmall)
                }
            }
        }

        /// Renders the per-workspace notes section under the session
        /// list when the workspace has both a resolvable
        /// `notesWorkspaceID` and a non-empty summary published by the
        /// chrome controller. The section stays hidden otherwise so
        /// disabling notes (or hosts that never wire `onOpenNote`)
        /// keeps the sidebar's classic layout untouched.
        @ViewBuilder
        private func notesSection(for workspace: AuroraWorkspace) -> some View {
            if let workspaceID = workspace.notesWorkspaceID,
               let summary = notesByWorkspace[workspaceID],
               summary.count > 0,
               let onOpenNote {
                NotesSectionView(
                    summary: summary,
                    isExpanded: notesExpansion[workspaceID] ?? false,
                    onToggleExpansion: {
                        let current = notesExpansion[workspaceID] ?? false
                        notesExpansion[workspaceID] = !current
                    },
                    onOpenNote: { noteID in
                        onOpenNote(workspaceID, noteID)
                    },
                    localizer: localizer
                )
                .padding(.top, 2)
            }
        }

        private func workspaceRow(_ workspace: AuroraWorkspace, isCollapsed: Bool) -> some View {
            Button(action: { toggleCollapsed(workspace) }) {
                HStack(spacing: Spacing.xSmall) {
                    Text("▾")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.textLow.resolvedColor())
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        .animation(.easeInOut(duration: 0.18), value: isCollapsed)
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

        private func toggleCollapsed(_ workspace: AuroraWorkspace) {
            workspaceDisclosure.toggle(workspace)
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
        var displayMode: AuroraSidebarDisplayMode = .detailed
        var primaryInfo: AuroraSidebarPrimaryInfo = .state
        let onActivate: () -> Void
        var onClose: (() -> Void)? = nil
        var onTogglePin: (() -> Void)? = nil
        var onCloseOthers: (() -> Void)? = nil
        var onMoveUp: (() -> Void)? = nil
        var onMoveDown: (() -> Void)? = nil
        var onMoveSessionBefore: ((String) -> Void)? = nil
        var onMovePaneToSession: ((String) -> Void)? = nil
        var onHoverChange: (Bool) -> Void = { _ in }
        var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

        @Environment(\.designThemePalette) private var palette
        @State private var isHovered = false
        @State private var isDropTargeted = false

        var body: some View {
            let layout = VerticalTabCompactMode(mode: displayMode)
            let summary = VerticalTabSummaryMode(
                session: session,
                primaryInfo: primaryInfo,
                localizer: localizer
            )
            VStack(alignment: .leading, spacing: CGFloat(layout.rowSpacing)) {
                HStack(spacing: Spacing.xSmall) {
                    AgentChipView(agent: session.agent, state: session.state, size: 22, localizer: localizer)
                    Text(session.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.textHigh.resolvedColor())
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if session.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(palette.textLow.resolvedColor())
                            .accessibilityLabel(TabItemView.localizedPinned(using: localizer))
                    }
                    if session.hasWorktree {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(palette.accent.resolvedColor())
                            .help(Self.localizedWorktreeHelp(using: localizer))
                            .accessibilityLabel(TabItemView.localizedWorktree(using: localizer))
                    }
                    Spacer()
                    if layout.showsPaneMatrix {
                        MiniMatrixView(panes: session.matrixPanes, localizer: localizer)
                    }
                    if !session.movablePanes.isEmpty {
                        PaneTransferHandleView(panes: session.movablePanes, localizer: localizer)
                    }
                    if let onClose, !session.isPinned, layout.showsCloseButton {
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
                        .help(Self.localizedCloseTabHelp(using: localizer))
                        .accessibilityLabel(Self.localizedCloseTabAccessibility(session.name, using: localizer))
                        .opacity(isActive || isHovered ? 0.95 : 0.55)
                    }
                }
                if layout.showsPrimaryMetadata {
                    HStack(spacing: Spacing.xxSmall) {
                        Circle()
                            .fill(summary.state.token.resolvedColor())
                            .frame(width: 7, height: 7)
                        Text(summary.metadataLine)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(palette.textLow.resolvedColor())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.leading, 30)
                }
            }
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, CGFloat(layout.verticalPadding))
            .background(backgroundView)
            .background(SessionFrameReporter(sessionID: session.id))
            .overlay(borderView)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onDrag {
                NSItemProvider(
                    object: VerticalTabDragPayload.session(session.id).encodedValue as NSString
                )
            }
            .onDrop(of: [UTType.text], isTargeted: $isDropTargeted) { providers in
                handleSessionDrop(providers)
            }
            .onTapGesture(perform: onActivate)
            .onHover { hovering in
                isHovered = hovering
                onHoverChange(hovering)
            }
            .contextMenu { contextMenuContent }
            .padding(.leading, 12)
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
                    isDropTargeted
                        ? palette.accent.resolvedColor()
                        : isActive
                        ? session.agent.token.withAlpha(0.55).resolvedColor()
                        : Color.clear,
                    lineWidth: isDropTargeted || isActive ? 1.5 : 1
                )
        }

        private func handleSessionDrop(_ providers: [NSItemProvider]) -> Bool {
            guard let provider = providers.first(where: {
                $0.canLoadObject(ofClass: NSString.self)
            }) else {
                return false
            }

            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let payload = object as? String else {
                    return
                }

                guard let parsed = VerticalTabDragPayload(encodedValue: payload) else {
                    return
                }

                Task { @MainActor in
                    handleParsedDrop(parsed)
                }
            }
            return true
        }

        @MainActor
        private func handleParsedDrop(_ payload: VerticalTabDragPayload) {
            let handler = VerticalTabDragHandler(
                currentSessionID: session.id,
                onMoveSessionBefore: onMoveSessionBefore,
                onMovePaneToSession: onMovePaneToSession
            )
            _ = handler.handle(payload)
        }

        @ViewBuilder
        private var contextMenuContent: some View {
            if let onTogglePin {
                Button(session.isPinned ? Self.localizedUnpinTab(using: localizer) : Self.localizedPinTab(using: localizer), action: onTogglePin)
            }
            if let onClose {
                Button(Self.localizedCloseTab(using: localizer), action: onClose)
                    .disabled(session.isPinned)
            }
            if let onCloseOthers {
                Button(Self.localizedCloseOtherTabs(using: localizer), action: onCloseOthers)
            }
            if onMoveUp != nil || onMoveDown != nil {
                Divider()
            }
            if let onMoveUp {
                Button(Self.localizedMoveTabUp(using: localizer), action: onMoveUp)
            }
            if let onMoveDown {
                Button(Self.localizedMoveTabDown(using: localizer), action: onMoveDown)
            }
        }

        static func localizedWorktreeHelp(using localizer: AppLocalizer) -> String {
            localizer.string("auroraSidebar.session.worktree.help", fallback: "Attached to a cocxy-managed worktree")
        }

        static func localizedCloseTabHelp(using localizer: AppLocalizer) -> String {
            localizer.string("auroraSidebar.session.close.help", fallback: "Close tab")
        }

        static func localizedCloseTabAccessibility(_ name: String, using localizer: AppLocalizer) -> String {
            String(
                format: localizer.string("auroraSidebar.session.close.accessibility", fallback: "Close %@"),
                name
            )
        }

        static func localizedPinTab(using localizer: AppLocalizer) -> String {
            localizer.string("tabbar.context.pin", fallback: "Pin Tab")
        }

        static func localizedUnpinTab(using localizer: AppLocalizer) -> String {
            localizer.string("tabbar.context.unpin", fallback: "Unpin Tab")
        }

        static func localizedCloseTab(using localizer: AppLocalizer) -> String {
            localizer.string("tabbar.context.close", fallback: "Close Tab")
        }

        static func localizedCloseOtherTabs(using localizer: AppLocalizer) -> String {
            localizer.string("tabbar.context.closeOthers", fallback: "Close Other Tabs")
        }

        static func localizedMoveTabUp(using localizer: AppLocalizer) -> String {
            localizer.string("tabbar.context.moveUp", fallback: "Move Tab Up")
        }

        static func localizedMoveTabDown(using localizer: AppLocalizer) -> String {
            localizer.string("tabbar.context.moveDown", fallback: "Move Tab Down")
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
        var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

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
                AgentChipView(agent: session.agent, state: session.state, size: 28, localizer: localizer)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.textHigh.resolvedColor())
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(agentLabel(session.agent))
                        Text("·")
                        Text(Design.localizedAgentStateLabel(session.state, using: localizer))
                    }
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(session.agent.token.resolvedColor())
                }
                Spacer()
                Text(Design.localizedPaneCount(session.panes.count, using: localizer))
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
                metricChip(Self.localizedLiveMetric(using: localizer), "\(session.activePaneCount)")
                metricChip(Self.localizedToolsMetric(using: localizer), "\(session.totalToolCount)")
                metricChip(Self.localizedErrorsMetric(using: localizer), "\(session.totalErrorCount)", isWarning: session.totalErrorCount > 0)
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
                infoLine(
                    icon: "square.stack.3d.up",
                    label: Self.localizedWorkspaceLabel(using: localizer),
                    value: workspaceSummary
                )
                if let process = cleaned(session.foregroundProcessName) {
                    infoLine(icon: "cpu", label: Self.localizedProcessLabel(using: localizer), value: process)
                }
                if let directory = cleaned(session.workingDirectory) {
                    infoLine(icon: "folder", label: Self.localizedDirectoryLabel(using: localizer), value: prettyDirectory(directory))
                }
                if let command = cleaned(session.lastCommandSummary) {
                    infoLine(icon: "terminal", label: Self.localizedCommandLabel(using: localizer), value: command)
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
                    Text(Self.localizedLivePanesTitle(using: localizer))
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(palette.textLow.resolvedColor())
                    ForEach(session.matrixPanes.prefix(5)) { pane in
                        paneLine(pane)
                    }
                    if session.matrixPanes.count > 5 {
                        Text(Self.localizedMoreActivePanes(session.matrixPanes.count - 5, using: localizer))
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
                Text(Self.localizedAllPanesIdle(using: localizer))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.textLow.resolvedColor())
            }
        }

        private func paneLine(_ pane: AuroraPane) -> some View {
            HStack(spacing: 8) {
                AgentChipView(agent: pane.agent, state: pane.state, size: 18, localizer: localizer)
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
            Text(Self.localizedFooter(using: localizer))
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
            var parts = [Design.localizedAgentStateLabel(pane.state, using: localizer)]
            if let activity = cleaned(pane.activity) {
                parts.append(activity)
            }
            if pane.toolCount > 0 || pane.errorCount > 0 {
                parts.append(Design.localizedToolCount(pane.toolCount, using: localizer))
                parts.append(Design.localizedErrorCount(pane.errorCount, using: localizer))
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

        static func localizedLiveMetric(using localizer: AppLocalizer) -> String {
            localizer.string("auroraSidebar.tooltip.metric.live", fallback: "live")
        }

        static func localizedToolsMetric(using localizer: AppLocalizer) -> String {
            localizer.string("auroraSidebar.tooltip.metric.tools", fallback: "tools")
        }

        static func localizedErrorsMetric(using localizer: AppLocalizer) -> String {
            localizer.string("auroraSidebar.tooltip.metric.errors", fallback: "errors")
        }

        static func localizedWorkspaceLabel(using localizer: AppLocalizer) -> String {
            localizer.string("auroraSidebar.tooltip.context.workspace", fallback: "Workspace")
        }

        static func localizedProcessLabel(using localizer: AppLocalizer) -> String {
            localizer.string("auroraSidebar.tooltip.context.process", fallback: "Process")
        }

        static func localizedDirectoryLabel(using localizer: AppLocalizer) -> String {
            localizer.string("auroraSidebar.tooltip.context.directory", fallback: "Directory")
        }

        static func localizedCommandLabel(using localizer: AppLocalizer) -> String {
            localizer.string("auroraSidebar.tooltip.context.command", fallback: "Command")
        }

        static func localizedLivePanesTitle(using localizer: AppLocalizer) -> String {
            localizer.string("auroraSidebar.tooltip.panes.live", fallback: "Live panes")
        }

        static func localizedMoreActivePanes(_ count: Int, using localizer: AppLocalizer) -> String {
            let key = count == 1
                ? "auroraSidebar.tooltip.panes.moreActive.one"
                : "auroraSidebar.tooltip.panes.moreActive.many"
            let fallback = count == 1 ? "+ %d more active pane" : "+ %d more active panes"
            return String(format: localizer.string(key, fallback: fallback), count)
        }

        static func localizedAllPanesIdle(using localizer: AppLocalizer) -> String {
            localizer.string("auroraSidebar.tooltip.panes.allIdle", fallback: "All panes are idle")
        }

        static func localizedFooter(using localizer: AppLocalizer) -> String {
            localizer.string("auroraSidebar.tooltip.footer", fallback: "Click the row to focus · use × to close")
        }
    }

    // MARK: - Notes section

    /// Per-workspace notes block rendered under the session list when a
    /// workspace has notes. Renders a header (icon + count + chevron)
    /// that toggles a list of the most recently edited notes; each
    /// note row dispatches `onOpenNote` so the host can open the
    /// docked overlay and select the chosen note.
    ///
    /// Kept presentational — every behaviour (counts, list contents,
    /// expansion state, click routing) flows through inputs so the
    /// view stays previewable and unit-testable in isolation.
    struct NotesSectionView: View {
        static let countBadgeMinimumWidth: CGFloat = 18
        static let noteRowMinimumHitHeight: CGFloat = 28

        let summary: AuroraWorkspaceNotesSummary
        let isExpanded: Bool
        let onToggleExpansion: () -> Void
        let onOpenNote: (String) -> Void
        var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

        @Environment(\.designThemePalette) private var palette

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                header
                if isExpanded {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(summary.recentNotes) { row in
                            noteRow(row)
                        }
                    }
                    .padding(.leading, 14)
                }
            }
            .padding(.leading, 12)
        }

        private var header: some View {
            Button(action: onToggleExpansion) {
                HStack(spacing: Spacing.xSmall) {
                    Image(systemName: "note.text")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.textLow.resolvedColor())
                    Text(Self.localizedTitle(using: localizer))
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(palette.textLow.resolvedColor())
                    countBadge(summary.count)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.textLow.resolvedColor())
                        .animation(.easeInOut(duration: 0.18), value: isExpanded)
                }
                .padding(.horizontal, Spacing.xSmall)
                .padding(.vertical, 5)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.localizedAccessibilityLabel(summary.count, using: localizer))
            .accessibilityHint(Self.localizedAccessibilityHint(isExpanded: isExpanded, using: localizer))
        }

        private func countBadge(_ count: Int) -> some View {
            Text(verbatim: "\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.textHigh.resolvedColor())
                .frame(minWidth: Self.countBadgeMinimumWidth)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    Capsule(style: .continuous)
                        .fill(palette.accentSoft.resolvedColor())
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(palette.accent.resolvedColor().opacity(0.30), lineWidth: 0.7)
                )
                .accessibilityHidden(true)
        }

        private func noteRow(_ row: AuroraNoteRow) -> some View {
            Button {
                onOpenNote(row.id)
            } label: {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.textLow.resolvedColor())
                        .frame(width: 12)
                    Text(Note.localizedTitle(row.title, using: localizer))
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textHigh.resolvedColor())
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(row.updatedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(palette.textDim.resolvedColor())
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: Self.noteRowMinimumHitHeight,
                    alignment: .leading
                )
                .padding(.horizontal, Spacing.xSmall)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityLabel(
                Self.localizedOpenNoteAccessibility(
                    Note.localizedTitle(row.title, using: localizer),
                    using: localizer
                )
            )
        }

        static func localizedTitle(using localizer: AppLocalizer) -> String {
            localizer.string("auroraSidebar.notes.title", fallback: "Notes")
        }

        static func localizedAccessibilityLabel(_ count: Int, using localizer: AppLocalizer) -> String {
            let key = count == 1
                ? "auroraSidebar.notes.accessibility.one"
                : "auroraSidebar.notes.accessibility.many"
            let fallback = count == 1 ? "Notes — %d note" : "Notes — %d notes"
            return String(format: localizer.string(key, fallback: fallback), count)
        }

        static func localizedAccessibilityHint(
            isExpanded: Bool,
            using localizer: AppLocalizer
        ) -> String {
            isExpanded
                ? localizer.string("auroraSidebar.notes.collapse", fallback: "Collapse notes list")
                : localizer.string("auroraSidebar.notes.expand", fallback: "Expand notes list")
        }

        static func localizedOpenNoteAccessibility(
            _ title: String,
            using localizer: AppLocalizer
        ) -> String {
            String(
                format: localizer.string("auroraSidebar.notes.open.accessibility", fallback: "Open note: %@"),
                title
            )
        }
    }

    // MARK: - Mini matrix

    /// Tiny horizontal matrix rendered next to the session name. One
    /// cell per active pane, filled with the agent accent and outlined
    /// with the lifecycle-state color so Claude/Codex/Gemini identity
    /// stays visible even when several panes are all `working`.
    struct MiniMatrixView: View {
        let panes: [AuroraPane]
        var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

        var body: some View {
            HStack(spacing: 3) {
                ForEach(panes) { pane in
                    Circle()
                        .fill(pane.agent.token.resolvedColor())
                        .overlay(
                            Circle()
                                .strokeBorder(pane.state.token.resolvedColor(), lineWidth: 0.8)
                        )
                        .frame(width: 7, height: 7)
                        .help(Design.localizedPaneDiagnosticLine(for: pane, using: localizer))
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// Drag handles for split panes. Kept separate from the mini-matrix:
    /// matrix dots describe active agent work, while these handles expose
    /// every movable split pane, including idle shells.
    struct PaneTransferHandleView: View {
        let panes: [AuroraPane]
        var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

        @Environment(\.designThemePalette) private var palette

        var body: some View {
            HStack(spacing: 3) {
                ForEach(panes) { pane in
                    Circle()
                        .fill(palette.glassHighlight.resolvedColor())
                        .overlay(
                            Circle()
                                .strokeBorder(pane.state.token.resolvedColor(), lineWidth: 0.9)
                        )
                        .frame(width: 7, height: 7)
                        .help(Self.localizedDragPaneHelp(pane.name, using: localizer))
                        .accessibilityLabel(Self.localizedMovePaneAccessibility(pane.name, using: localizer))
                        .onDrag {
                            NSItemProvider(
                                object: VerticalTabDragPayload.pane(pane.id).encodedValue as NSString
                            )
                        }
                }
            }
        }

        static func localizedDragPaneHelp(_ name: String, using localizer: AppLocalizer) -> String {
            String(
                format: localizer.string("auroraSidebar.paneTransfer.drag.help", fallback: "Drag %@ pane to another tab"),
                name
            )
        }

        static func localizedMovePaneAccessibility(_ name: String, using localizer: AppLocalizer) -> String {
            String(
                format: localizer.string("auroraSidebar.paneTransfer.move.accessibility", fallback: "Move %@ pane"),
                name
            )
        }
    }

    // MARK: - Local badge

    /// Privacy status badge used by the Aurora status bar's leftmost
    /// chip. Keep the copy scoped to telemetry, not execution locality:
    /// Cocxy supports explicit remote sessions, so "100% local" would
    /// overstate the runtime model whenever SSH features are active.
    struct LocalBadgeView: View {
        var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

        @Environment(\.designThemePalette) private var palette

        var body: some View {
            let finished = AgentStateRole.finished.token.resolvedColor()
            HStack(spacing: Spacing.xxSmall) {
                Circle()
                    .fill(finished)
                    .frame(width: 6, height: 6)
                    .shadow(color: finished.opacity(0.7), radius: 3)
                Text(Self.localizedLabel(using: localizer))
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
            .help(Self.localizedHelp(using: localizer))
            .accessibilityLabel(Self.localizedAccessibilityLabel(using: localizer))
        }

        static func localizedLabel(using localizer: AppLocalizer) -> String {
            localizer.string("auroraStatus.localBadge.label", fallback: "no telemetry")
        }

        static func localizedHelp(using localizer: AppLocalizer) -> String {
            localizer.string(
                "auroraStatus.localBadge.help",
                fallback: "No telemetry or tracking. Update checks only contact Cocxy's signed appcast."
            )
        }

        static func localizedAccessibilityLabel(using localizer: AppLocalizer) -> String {
            localizer.string(
                "auroraStatus.localBadge.accessibility",
                fallback: "No telemetry or tracking"
            )
        }
    }
}
