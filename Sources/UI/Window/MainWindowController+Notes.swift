// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+Notes.swift - Notes overlay wiring.

import AppKit
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
        return NotesViewModel(
            store: store,
            resolver: DefaultNoteWorkspaceResolver(),
            searchEngine: NoteSearchEngineFactory.make(
                kind: config.searchEngine,
                store: store,
                storageRoot: storageRoot
            ),
            autoSaveEnabled: config.autoSave
        )
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
        hostingView.rootView = makeNotesOverlayView(viewModel: viewModel, panelWidth: width)
    }

    private func makeNotesOverlayView(
        viewModel: NotesViewModel,
        panelWidth: CGFloat
    ) -> NotesOverlayView {
        NotesOverlayView(
            viewModel: viewModel,
            panelWidth: panelWidth,
            onDismiss: { [weak self] in
                self?.dismissNotes()
            }
        )
    }
}
