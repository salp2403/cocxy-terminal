// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+Notes.swift - Notes overlay wiring.

import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
extension MainWindowController {

    // MARK: - Toggle / Show / Dismiss

    func toggleNotes() {
        if isNotesVisible {
            dismissNotes()
        } else {
            showNotes()
        }
    }

    @objc func toggleNotesAction(_ sender: Any?) {
        toggleNotes()
    }

    func showNotes() {
        guard let overlayContainer = overlayContainerView else { return }
        let config = configService?.current.notes ?? .defaults
        guard config.enabled else { return }

        let viewModel = resolveNotesViewModel(config: config)
        notesHostingView?.removeFromSuperview()

        let panelWidth = clampedNotesPanelWidth(containerWidth: overlayContainer.bounds.width)
        let swiftUIView = makeNotesOverlayView(viewModel: viewModel, panelWidth: panelWidth)
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.appearance = Design.appearance(for: swiftUIView.themeIdentity)
        hostingView.wantsLayer = true
        let panelY = statusBarHostingView?.frame.height ?? 24
        hostingView.frame = NSRect(
            x: overlayContainer.bounds.width - panelWidth,
            y: panelY,
            width: panelWidth,
            height: max(0, overlayContainer.bounds.height - panelY)
        )
        hostingView.autoresizingMask = [.height, .minXMargin]

        notesHostingView = hostingView
        overlayContainer.addSubview(hostingView)
        isNotesVisible = true

        Task { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            await self.loadNotesForVisibleTab(using: viewModel)
        }

        layoutRightDockedAgentPanels()
    }

    func dismissNotes() {
        guard let hostingView = notesHostingView,
              let overlayContainer = overlayContainerView else {
            notesHostingView?.removeFromSuperview()
            notesHostingView = nil
            isNotesVisible = false
            return
        }

        isNotesVisible = false
        let targetX = overlayContainer.bounds.width
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AnimationConfig.duration(AnimationConfig.overlaySlideOutDuration)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hostingView.animator().frame.origin.x = targetX
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.notesHostingView?.removeFromSuperview()
                self?.notesHostingView = nil
                self?.layoutRightDockedAgentPanels()
                self?.focusActiveTerminalSurface()
            }
        })
    }

    // MARK: - Config / active-tab sync

    func handleNotesConfigChanged(_ config: NotesConfig) {
        if !config.enabled {
            if isNotesVisible { dismissNotes() }
            notesViewModel = nil
            notesChangeCancellable?.cancel()
            notesChangeCancellable = nil
            auroraChromeController?.refreshNotesSummaries()
            return
        }

        guard isNotesVisible else { return }
        notesViewModel = makeNotesViewModel(config: config)
        syncNotesRootView()
        if let notesViewModel {
            Task { [weak self, weak notesViewModel] in
                guard let self, let notesViewModel else { return }
                await self.loadNotesForVisibleTab(using: notesViewModel)
            }
        }
    }

    func refreshNotesForVisibleTabIfNeeded() {
        guard isNotesVisible, let notesViewModel else { return }
        Task { [weak self, weak notesViewModel] in
            guard let self, let notesViewModel else { return }
            await self.loadNotesForVisibleTab(using: notesViewModel)
        }
    }

    // MARK: - View model

    func resolveNotesViewModel(config: NotesConfig? = nil) -> NotesViewModel {
        if let notesViewModel { return notesViewModel }
        let viewModel = makeNotesViewModel(config: config ?? configService?.current.notes ?? .defaults)
        notesViewModel = viewModel
        return viewModel
    }

    private func makeNotesViewModel(config: NotesConfig) -> NotesViewModel {
        let storageRoot = Self.expandedNotesStorageURL(config.storageDir)
        let store = NoteStore(
            storageRoot: storageRoot,
            format: config.format,
            autoSaveInterval: config.autoSaveIntervalSeconds
        )
        let viewModel = NotesViewModel(
            store: store,
            resolver: DefaultNoteWorkspaceResolver(),
            searchEngine: NoteSearchEngineFactory.make(
                kind: config.searchEngine,
                store: store,
                storageRoot: storageRoot
            ),
            autoSaveEnabled: config.autoSave
        )

        // Bridge note CRUD into the Aurora chrome so the sidebar's
        // per-workspace notes section refreshes counts and recent
        // titles after creates / deletes / saves. Skipping the very
        // first emission avoids a redundant fetch right after the
        // controller already requested its initial refresh; subsequent
        // changes pass through. Cancel any prior subscription so a
        // config-driven view-model swap does not stack listeners.
        notesChangeCancellable?.cancel()
        notesChangeCancellable = viewModel.$notes
            .dropFirst()
            .sink { [weak self] _ in
                self?.auroraChromeController?.refreshNotesSummaries()
            }

        return viewModel
    }

    func currentNotesWorkingDirectory() -> URL? {
        if let tabID = visibleTabID ?? tabManager.activeTabID,
           let tab = tabManager.tab(for: tabID) {
            return tab.worktreeRoot ?? tab.workingDirectory
        }
        return nil
    }

    func loadNotesForVisibleTab(using viewModel: NotesViewModel) async {
        guard let directory = currentNotesWorkingDirectory() else { return }
        await viewModel.load(directory: directory)
    }

    nonisolated static func expandedNotesStorageURL(_ rawPath: String) -> URL {
        let expanded: String
        if rawPath == "~" {
            expanded = FileManager.default.homeDirectoryForCurrentUser.path
        } else if rawPath.hasPrefix("~/") {
            expanded = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(rawPath.dropFirst(2)))
                .path
        } else {
            expanded = rawPath
        }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    // MARK: - Layout

    func clampedNotesPanelWidth(containerWidth: CGFloat) -> CGFloat {
        min(
            max(NotesOverlayView.defaultPanelWidth, NotesOverlayView.minimumPanelWidth),
            min(NotesOverlayView.maximumPanelWidth, max(NotesOverlayView.minimumPanelWidth, containerWidth * 0.75))
        )
    }

    func syncNotesRootView(panelWidth: CGFloat? = nil) {
        guard isNotesVisible,
              let hostingView = notesHostingView,
              let viewModel = notesViewModel else {
            return
        }
        let width = panelWidth ?? clampedNotesPanelWidth(
            containerWidth: overlayContainerView?.bounds.width ?? NotesOverlayView.defaultPanelWidth
        )
        let swiftUIView = makeNotesOverlayView(viewModel: viewModel, panelWidth: width)
        hostingView.appearance = Design.appearance(for: swiftUIView.themeIdentity)
        hostingView.rootView = swiftUIView
    }

    private func makeNotesOverlayView(
        viewModel: NotesViewModel,
        panelWidth: CGFloat
    ) -> NotesOverlayView {
        NotesOverlayView(
            viewModel: viewModel,
            panelWidth: panelWidth,
            themeIdentity: currentAuroraThemeIdentity(),
            onDismiss: { [weak self] in
                self?.dismissNotes()
            }
        )
    }

    // MARK: - Aurora sidebar Notes section bridge

    /// Provider closure used by `AuroraChromeController` to refresh
    /// per-workspace notes summaries. Returns counts + recent titles
    /// keyed by `NoteWorkspaceID.rawValue` so the sidebar can render
    /// its expandable section without coupling to the Notes store.
    ///
    /// Reads the live config to honour `[notes].enabled` and the
    /// configured storage directory. Returns an empty map when notes
    /// are disabled so the sidebar hides every section the moment the
    /// preference flips off.
    func fetchAuroraNotesSummaries(
        for workspaceIDs: Set<String>
    ) async -> [String: Design.AuroraWorkspaceNotesSummary] {
        let config = configService?.current.notes ?? .defaults
        guard config.enabled, !workspaceIDs.isEmpty else { return [:] }

        let storageRoot = Self.expandedNotesStorageURL(config.storageDir)
        let store = NoteStore(storageRoot: storageRoot, format: config.format)
        let typedIDs = workspaceIDs.map { NoteWorkspaceID(rawValue: $0) }
        let summaries = await store.summaries(for: typedIDs, recentLimit: 5)

        var result: [String: Design.AuroraWorkspaceNotesSummary] = [:]
        for (id, summary) in summaries {
            let rows = summary.recent.map { note in
                Design.AuroraNoteRow(
                    id: note.id.uuidString,
                    title: note.derivedTitle,
                    updatedAt: note.updatedAt
                )
            }
            result[id.rawValue] = Design.AuroraWorkspaceNotesSummary(
                workspaceID: id.rawValue,
                count: summary.count,
                recentNotes: rows
            )
        }
        return result
    }

    /// Resolves the tab whose workspace identifier matches `rawID`.
    /// Walks the live tab list through the same resolver the Notes
    /// store uses on disk so the lookup follows the user's git-root
    /// grouping exactly. Returns `nil` when no tab matches (closed
    /// tab, stale sidebar fetch) so the caller can no-op silently.
    func tabForNotesWorkspace(rawID: String) -> Tab? {
        let resolver = DefaultNoteWorkspaceResolver()
        for tab in tabManager.tabs {
            let directory = tab.worktreeRoot ?? tab.workingDirectory
            guard let resolved = resolver.resolveWorkspace(for: directory) else {
                continue
            }
            if resolved.workspaceID.rawValue == rawID {
                return tab
            }
        }
        return nil
    }

    /// Opens the per-workspace overlay focused on the supplied note.
    /// Drives the same lifecycle the user-facing path uses — focus
    /// the owning tab if it is not already visible, mount the
    /// overlay (when `[notes].enabled = true`), wait for the
    /// asynchronous workspace load to finish, and then select the
    /// requested note. No-op when notes are disabled, the tab is
    /// gone, or the workspace cannot be resolved.
    func openNote(workspaceIDRaw: String, noteIDRaw: String) {
        let config = configService?.current.notes ?? .defaults
        guard config.enabled else { return }
        guard let targetTab = tabForNotesWorkspace(rawID: workspaceIDRaw) else { return }

        if visibleTabID != targetTab.id {
            _ = focusTab(id: targetTab.id)
        }

        if !isNotesVisible {
            showNotes()
        }

        let viewModel = resolveNotesViewModel(config: config)
        Task { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            await self.loadNotesForVisibleTab(using: viewModel)
            // The load above repopulates `notes` for the target
            // workspace. Selection runs on the main actor so it
            // observes the just-published listing without racing the
            // SwiftUI host.
            viewModel.selectNote(byRawID: noteIDRaw)
        }
    }
}
