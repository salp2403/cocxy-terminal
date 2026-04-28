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

    func showTransientCommandPaletteOverlay(engine: any CommandPaletteSearching) {
        guard let overlayContainer = overlayContainerView else { return }

        commandPaletteViewModel = CommandPaletteViewModel(engine: engine)
        guard let viewModel = commandPaletteViewModel else { return }
        viewModel.isVisible = true

        commandPaletteHostingView?.removeFromSuperview()
        var swiftUIView = CommandPaletteView(viewModel: viewModel)
        swiftUIView.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
        let hostingView = FocusableHostingView(rootView: swiftUIView)
        hostingView.frame = overlayContainer.bounds
        hostingView.autoresizingMask = [.width, .height]
        commandPaletteHostingView = hostingView

        overlayContainer.addSubview(hostingView)
        isCommandPaletteVisible = true
        window?.makeFirstResponder(hostingView)
    }

    // MARK: - Items

    func unifiedQuickSwitchActions(now: Date = Date()) -> [CommandAction] {
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
                description: item.subtitle ?? item.kind.displayName,
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
        var items: [UnifiedQuickSwitchItem] = []
        items.append(contentsOf: unifiedQuickSwitchTabItems())
        items.append(contentsOf: unifiedQuickSwitchBrowserItems(now: now))
        items.append(contentsOf: unifiedQuickSwitchWorktreeItems())
        items.append(contentsOf: unifiedQuickSwitchNoteItems())
        return items
    }

    private func unifiedQuickSwitchTabItems() -> [UnifiedQuickSwitchItem] {
        tabManager.tabs.map { tab in
            UnifiedQuickSwitchItem(
                id: tab.id.rawValue.uuidString,
                kind: .tab,
                title: "Tab: \(tab.displayTitle)",
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

    private func unifiedQuickSwitchBrowserItems(now: Date) -> [UnifiedQuickSwitchItem] {
        guard let viewModel = browserViewModel else { return [] }
        return viewModel.browserTabs.map { tab in
            let title = tab.title == "New Tab" ? tab.url.absoluteString : tab.title
            return UnifiedQuickSwitchItem(
                id: tab.id.uuidString,
                kind: .browserTab,
                title: "Browser: \(title)",
                subtitle: tab.url.absoluteString,
                keywords: [title, tab.url.host ?? "", tab.url.absoluteString],
                lastUsedAt: tab.id == viewModel.activeTabID ? now : nil,
                priority: tab.id == viewModel.activeTabID ? -10 : 0
            )
        }
    }

    private func unifiedQuickSwitchWorktreeItems() -> [UnifiedQuickSwitchItem] {
        tabManager.tabs.compactMap { tab in
            guard let worktreeID = tab.worktreeID else { return nil }
            let branch = tab.worktreeBranch ?? tab.gitBranch ?? worktreeID
            return UnifiedQuickSwitchItem(
                id: worktreeID,
                kind: .worktree,
                title: "Worktree: \(branch)",
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

    private func unifiedQuickSwitchNoteItems() -> [UnifiedQuickSwitchItem] {
        let summaries = auroraChromeController?.notesByWorkspace ?? [:]
        return summaries.flatMap { workspaceID, summary in
            summary.recentNotes.map { note in
                UnifiedQuickSwitchItem(
                    id: "\(workspaceID)|\(note.id)",
                    kind: .note,
                    title: "Note: \(note.title)",
                    subtitle: "Workspace notes",
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
}

private extension UnifiedQuickSwitchItemKind {
    var displayName: String {
        switch self {
        case .tab: return "Terminal tab"
        case .browserTab: return "Browser tab"
        case .worktree: return "Worktree"
        case .note: return "Note"
        }
    }
}
