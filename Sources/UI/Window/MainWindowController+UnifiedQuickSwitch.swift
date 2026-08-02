// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+UnifiedQuickSwitch.swift - Cross-surface QuickSwitch wiring.

import AppKit
import CocxyShared
import Foundation
import SwiftUI

@MainActor
extension MainWindowController {

    // MARK: - Presentation

    /// Presents a transient command-palette surface containing only
    /// switch targets gathered from the live window: terminal tabs,
    /// browser tabs, cocxy worktrees, and recent notes. Reuses the
    /// existing palette chrome and keyboard handling, but keeps the
    /// global command catalogue untouched so a cancelled QuickSwitch
    /// never pollutes command-palette recents.
    func showUnifiedQuickSwitchOverlay() {
        let actions = unifiedQuickSwitchActions()
        guard !actions.isEmpty else {
            if let result = quickSwitchController?.performQuickSwitch() {
                NSLog("[UnifiedQuickSwitch] Fell back to legacy unread-tab quick switch: %@", result.description)
            }
            return
        }

        showTransientCommandPaletteOverlay(engine: StaticCommandPaletteEngine(actions: actions))
    }

    /// Opens a project-only palette backed by the persistent registry.
    /// Both live and dormant projects remain available without Aurora chrome.
    func showProjectQuickSwitchOverlay() {
        let items = unifiedQuickSwitchProjectItems(localizer: appLocalizer())
        guard !items.isEmpty, projectActivationHandler != nil else {
            NSSound.beep()
            return
        }
        let actions = items.map { item in
            return CommandAction(
                id: "project.quickswitch.\(item.id)",
                name: item.title,
                description: item.subtitle ?? "",
                shortcut: nil,
                category: .navigation,
                handler: { [weak self, projectID = item.id] in
                    self?.dismissCommandPalette()
                    self?.projectActivationHandler?(ProjectID(rawValue: projectID))
                }
            )
        }
        showTransientCommandPaletteOverlay(
            engine: StaticCommandPaletteEngine(actions: actions)
        )
    }

    /// Executes the user-configured QuickSwitch mode.
    ///
    /// The default `.unified` mode opens the cross-surface switcher.
    /// `.tabsOnly` is a rollback lever for users who want the legacy
    /// unread-tab rotation bound to the same shortcut/menu command.
    func performConfiguredQuickSwitch() {
        let mode = configService?.current.appearance.quickSwitchMode ?? .unified
        switch mode {
        case .unified:
            showUnifiedQuickSwitchOverlay()
        case .tabsOnly:
            if let result = quickSwitchController?.performQuickSwitch() {
                NSLog("[UnifiedQuickSwitch] Used legacy unread-tab quick switch: %@", result.description)
            }
        }
    }

    func showTransientCommandPaletteOverlay(engine: any CommandPaletteSearching) {
        guard let overlayContainer = overlayContainerView else { return }

        commandPaletteViewModel = CommandPaletteViewModel(
            engine: engine,
            localizer: appLocalizer()
        )
        guard let viewModel = commandPaletteViewModel else { return }
        viewModel.isVisible = true

        commandPaletteHostingView?.removeFromSuperview()
        var swiftUIView = CommandPaletteView(viewModel: viewModel)
        swiftUIView.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
        let hostingView = FocusableHostingView(rootView: swiftUIView)
        hostingView.onCancelOperation = { [weak self] in
            self?.dismissCommandPalette()
        }
        hostingView.frame = overlayContainer.bounds
        hostingView.autoresizingMask = [.width, .height]
        commandPaletteHostingView = hostingView

        overlayContainer.addSubview(hostingView)
        isCommandPaletteVisible = true
        window?.makeFirstResponder(hostingView)
    }

    // MARK: - Items

    func unifiedQuickSwitchActions(now: Date = Date()) -> [CommandAction] {
        let localizer = appLocalizer()
        let ranked = UnifiedQuickSwitchRanker.rank(
            query: "",
            items: unifiedQuickSwitchItems(now: now),
            now: now
        )

        return ranked.map { rankedItem in
            let item = rankedItem.item
            return CommandAction(
                id: "unified.quickswitch.\(item.kind.rawValue).\(item.id)",
                name: item.title,
                description: item.subtitle ?? item.kind.localizedDisplayName(using: localizer),
                shortcut: nil,
                category: .navigation,
                handler: { [weak self, item] in
                    self?.dismissCommandPalette()
                    self?.activateUnifiedQuickSwitchItem(item)
                }
            )
        }
    }

    func unifiedQuickSwitchItems(now: Date = Date()) -> [UnifiedQuickSwitchItem] {
        let localizer = appLocalizer()
        var items: [UnifiedQuickSwitchItem] = []
        items.append(contentsOf: unifiedQuickSwitchTabItems(localizer: localizer))
        items.append(contentsOf: unifiedQuickSwitchProjectItems(localizer: localizer))
        items.append(contentsOf: unifiedQuickSwitchBrowserItems(now: now, localizer: localizer))
        items.append(contentsOf: unifiedQuickSwitchWorktreeItems(localizer: localizer))
        items.append(contentsOf: unifiedQuickSwitchNoteItems(localizer: localizer))
        return items
    }

    private func unifiedQuickSwitchTabItems(localizer: AppLocalizer) -> [UnifiedQuickSwitchItem] {
        tabManager.tabs.map { tab in
            UnifiedQuickSwitchItem(
                id: tab.id.rawValue.uuidString,
                kind: .tab,
                title: Self.localizedUnifiedQuickSwitchTabTitle(tab.displayTitle, using: localizer),
                subtitle: tab.workingDirectory.path,
                keywords: [
                    tab.displayTitle,
                    tab.workingDirectory.lastPathComponent,
                    tab.gitBranch ?? "",
                    tab.processName ?? "",
                ],
                lastUsedAt: tab.lastActivityAt,
                priority: tab.isActive ? -20 : 0
            )
        }
    }

    private func unifiedQuickSwitchProjectItems(
        localizer: AppLocalizer
    ) -> [UnifiedQuickSwitchItem] {
        guard let projectRegistry else { return [] }
        let liveIDs = projectLiveIDsProvider?() ?? Set(tabManager.tabs.map {
            projectResolver.resolveProject(for: $0.workingDirectory).groupingID.rawValue
        })
        let projects = ProjectPresentationBuilder.makeItems(
            records: projectRegistry.records,
            aliases: auroraWorkspaceTitleStore.snapshot,
            liveProjectIDs: liveIDs,
            availability: { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
        )
        return projects.filter(\.isAvailable).map { project in
            UnifiedQuickSwitchItem(
                id: project.id,
                kind: .project,
                title: Self.localizedUnifiedQuickSwitchProjectTitle(
                    project.name,
                    using: localizer
                ),
                subtitle: project.id,
                keywords: [project.name, project.id, project.parentPath],
                lastUsedAt: project.lastOpenedAt,
                priority: project.isPinned ? 25 : (project.isLive ? 15 : 0)
            )
        }
    }

    private func unifiedQuickSwitchBrowserItems(now: Date, localizer: AppLocalizer) -> [UnifiedQuickSwitchItem] {
        guard let viewModel = browserViewModel else { return [] }
        return viewModel.browserTabs.map { tab in
            let title = tab.title == "New Tab" ? tab.url.absoluteString : tab.title
            return UnifiedQuickSwitchItem(
                id: tab.id.uuidString,
                kind: .browserTab,
                title: Self.localizedUnifiedQuickSwitchBrowserTitle(title, using: localizer),
                subtitle: tab.url.absoluteString,
                keywords: [title, tab.url.host ?? "", tab.url.absoluteString],
                lastUsedAt: tab.id == viewModel.activeTabID ? now : nil,
                priority: tab.id == viewModel.activeTabID ? -10 : 0
            )
        }
    }

    private func unifiedQuickSwitchWorktreeItems(localizer: AppLocalizer) -> [UnifiedQuickSwitchItem] {
        tabManager.tabs.compactMap { tab in
            guard let worktreeID = tab.worktreeID else { return nil }
            let branch = tab.worktreeBranch ?? tab.gitBranch ?? worktreeID
            return UnifiedQuickSwitchItem(
                id: worktreeID,
                kind: .worktree,
                title: Self.localizedUnifiedQuickSwitchWorktreeTitle(branch, using: localizer),
                subtitle: tab.worktreeRoot?.path ?? tab.workingDirectory.path,
                keywords: [
                    worktreeID,
                    branch,
                    tab.worktreeOriginRepo?.lastPathComponent ?? "",
                    tab.displayTitle,
                ],
                lastUsedAt: tab.lastActivityAt,
                priority: tab.id == (visibleTabID ?? tabManager.activeTabID) ? -20 : 5
            )
        }
    }

    private func unifiedQuickSwitchNoteItems(localizer: AppLocalizer) -> [UnifiedQuickSwitchItem] {
        let summaries = auroraChromeController?.notesByWorkspace ?? [:]
        return summaries.flatMap { workspaceID, summary in
            summary.recentNotes.map { note in
                UnifiedQuickSwitchItem(
                    id: "\(workspaceID)|\(note.id)",
                    kind: .note,
                    title: Self.localizedUnifiedQuickSwitchNoteTitle(note.title, using: localizer),
                    subtitle: Self.localizedUnifiedQuickSwitchNotesSubtitle(using: localizer),
                    keywords: [note.title, workspaceID],
                    lastUsedAt: note.updatedAt,
                    priority: 0
                )
            }
        }
    }

    // MARK: - Activation

    func activateUnifiedQuickSwitchItem(_ item: UnifiedQuickSwitchItem) {
        switch item.kind {
        case .tab:
            guard let uuid = UUID(uuidString: item.id) else { return }
            _ = focusTab(id: TabID(rawValue: uuid))
        case .project:
            projectActivationHandler?(ProjectID(rawValue: item.id))
        case .browserTab:
            guard let uuid = UUID(uuidString: item.id),
                  let viewModel = browserViewModel else { return }
            if !isBrowserVisible {
                showBrowserPanel()
            }
            viewModel.selectBrowserTab(uuid)
        case .worktree:
            guard let tab = tabManager.tabs.first(where: { $0.worktreeID == item.id }) else { return }
            _ = focusTab(id: tab.id)
        case .note:
            let pieces = item.id.split(separator: "|", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { return }
            openNote(workspaceIDRaw: pieces[0], noteIDRaw: pieces[1])
        }
    }

    static func localizedUnifiedQuickSwitchTabTitle(_ title: String, using localizer: AppLocalizer) -> String {
        String(format: localizer.string("quickSwitch.item.tab.title", fallback: "Tab: %@"), title)
    }

    static func localizedUnifiedQuickSwitchBrowserTitle(_ title: String, using localizer: AppLocalizer) -> String {
        String(format: localizer.string("quickSwitch.item.browser.title", fallback: "Browser: %@"), title)
    }

    static func localizedUnifiedQuickSwitchProjectTitle(_ title: String, using localizer: AppLocalizer) -> String {
        String(format: localizer.string("quickSwitch.item.project.title", fallback: "Project: %@"), title)
    }

    static func localizedUnifiedQuickSwitchWorktreeTitle(_ branch: String, using localizer: AppLocalizer) -> String {
        String(format: localizer.string("quickSwitch.item.worktree.title", fallback: "Worktree: %@"), branch)
    }

    static func localizedUnifiedQuickSwitchNoteTitle(_ title: String, using localizer: AppLocalizer) -> String {
        String(format: localizer.string("quickSwitch.item.note.title", fallback: "Note: %@"), title)
    }

    static func localizedUnifiedQuickSwitchNotesSubtitle(using localizer: AppLocalizer) -> String {
        localizer.string("quickSwitch.item.notes.subtitle", fallback: "Workspace notes")
    }
}

private extension UnifiedQuickSwitchItemKind {
    func localizedDisplayName(using localizer: AppLocalizer) -> String {
        switch self {
        case .tab:
            return localizer.string("quickSwitch.kind.tab", fallback: "Terminal tab")
        case .project:
            return localizer.string("quickSwitch.kind.project", fallback: "Project")
        case .browserTab:
            return localizer.string("quickSwitch.kind.browserTab", fallback: "Browser tab")
        case .worktree:
            return localizer.string("quickSwitch.kind.worktree", fallback: "Worktree")
        case .note:
            return localizer.string("quickSwitch.kind.note", fallback: "Note")
        }
    }
}
