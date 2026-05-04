// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+TabStrip.swift - Horizontal tab strip refresh logic.

import AppKit

// MARK: - Horizontal Tab Strip

/// Extension that manages the horizontal tab strip at the top of the
/// terminal area. Builds tab entries from the active tab's split panes
/// and updates the strip view.
extension MainWindowController {

    /// `tab-position = top` is a classic-chrome navigation mode: the left
    /// sidebar is collapsed and the horizontal strip must represent the
    /// window's real tabs. In every other layout the strip keeps its existing
    /// job as the active tab's split/panel selector.
    var usesTopLevelTabsInHorizontalStrip: Bool {
        configService?.current.appearance.auroraEnabled != true &&
            configService?.current.appearance.tabPosition == .top
    }

    /// Updates the horizontal tab strip to reflect current workspace state.
    func refreshTabStrip(syncFromFirstResponder: Bool = true) {
        guard let strip = horizontalTabStripView as? HorizontalTabStripView else { return }
        let localizer = appLocalizer()
        if syncFromFirstResponder {
            syncFocusedLeafSelectionFromFirstResponder()
        }

        if usesTopLevelTabsInHorizontalStrip {
            strip.setItemKind(.workspaceTab)
            let activeID = visibleTabID ?? tabManager.activeTabID
            let tabEntries = tabManager.tabs.map { tab in
                (
                    title: tab.displayTitle,
                    icon: "terminal.fill",
                    isActive: tab.id == activeID
                )
            }
            strip.updateTabs(tabEntries.isEmpty ? [(title: "Terminal", icon: "terminal.fill", isActive: true)] : tabEntries)
            updateHorizontalStripActionIcons(strip)
            return
        }

        strip.setItemKind(.panel)

        // Build tab entries from the visible tab's split panes.
        var tabEntries: [(title: String, icon: String, isActive: Bool)] = []

        if let targetTabID = visibleTabID ?? tabManager.activeTabID {
            let sm = tabSplitCoordinator.splitManager(for: targetTabID)
            let leaves = sm.rootNode.allLeafIDs()
            let focusedID = sm.focusedLeafID

            // Count terminals for fallback numbering.
            var terminalIndex = 0

            for leaf in leaves {
                let panelType = sm.panelType(for: leaf.terminalID)
                let customTitle = sm.panelTitle(for: leaf.terminalID)
                let title: String
                let icon: String

                if let custom = customTitle {
                    title = custom
                    switch panelType {
                    case .terminal: icon = "terminal.fill"
                    case .browser: icon = "globe"
                    case .markdown: icon = "doc.text"
                    case .editor: icon = "doc.plaintext"
                    case .notebook: icon = "book"
                    case .workflow: icon = "arrow.triangle.branch"
                    case .sessionReplay: icon = "record.circle"
                    case .aiEditHistory: icon = "clock.arrow.circlepath"
                    case .templates: icon = "square.grid.2x2"
                    case .macros: icon = "keyboard"
                    case .dbCloud: icon = "externaldrive.connected.to.line.below"
                    case .subagent: icon = "person.2"
                    }
                } else {
                    switch panelType {
                    case .terminal:
                        terminalIndex += 1
                        let dirName = tabManager.tab(for: targetTabID)?.workingDirectory.lastPathComponent ?? "Terminal"
                        title = leaves.count > 1 ? "\(dirName) \(terminalIndex)" : dirName
                        icon = "terminal.fill"
                    case .browser:
                        title = Self.localizedPanelTitle(.browser, using: localizer)
                        icon = "globe"
                    case .markdown:
                        title = Self.localizedPanelTitle(.markdown, using: localizer)
                        icon = "doc.text"
                    case .editor:
                        title = Self.localizedPanelTitle(.editor, using: localizer)
                        icon = "doc.plaintext"
                    case .notebook:
                        title = Self.localizedPanelTitle(.notebook, using: localizer)
                        icon = "book"
                    case .workflow:
                        title = Self.localizedPanelTitle(.workflow, using: localizer)
                        icon = "arrow.triangle.branch"
                    case .sessionReplay:
                        title = Self.localizedPanelTitle(.sessionReplay, using: localizer)
                        icon = "record.circle"
                    case .aiEditHistory:
                        title = Self.localizedPanelTitle(.aiEditHistory, using: localizer)
                        icon = "clock.arrow.circlepath"
                    case .templates:
                        title = Self.localizedPanelTitle(.templates, using: localizer)
                        icon = "square.grid.2x2"
                    case .macros:
                        title = Self.localizedPanelTitle(.macros, using: localizer)
                        icon = "keyboard"
                    case .dbCloud:
                        title = Self.localizedPanelTitle(.dbCloud, using: localizer)
                        icon = "externaldrive.connected.to.line.below"
                    case .subagent:
                        title = Self.localizedPanelTitle(.subagent, using: localizer)
                        icon = "person.2"
                    }
                }

                tabEntries.append((title: title, icon: icon, isActive: leaf.leafID == focusedID))
            }
        }

        if tabEntries.isEmpty {
            let dirName = visibleTabID.flatMap { tabManager.tab(for: $0)?.workingDirectory.lastPathComponent }
                ?? tabManager.activeTab?.workingDirectory.lastPathComponent
                ?? "Terminal"
            tabEntries = [(title: dirName, icon: "terminal.fill", isActive: true)]
        }

        strip.updateTabs(tabEntries)

        // Update contextual action icons based on the focused panel type.
        updateHorizontalStripActionIcons(strip)
    }

    static func localizedPanelTitle(_ panelType: PanelType, using localizer: AppLocalizer) -> String {
        switch panelType {
        case .terminal:
            let format = localizer.string("workspaceToolbar.panel.terminal", fallback: "Terminal %d")
            return String(format: format, 1)
        case .browser:
            return localizer.string("workspaceToolbar.panel.browser", fallback: "Browser")
        case .markdown:
            return localizer.string("workspaceToolbar.panel.markdown", fallback: "Markdown")
        case .editor:
            return localizer.string("workspaceToolbar.panel.editor", fallback: "Editor")
        case .notebook:
            return localizer.string("workspaceToolbar.panel.notebook", fallback: "Notebook")
        case .workflow:
            return localizer.string("workspaceToolbar.panel.workflow", fallback: "Workflow")
        case .sessionReplay:
            return localizer.string("workspaceToolbar.panel.sessionReplay", fallback: "Replay")
        case .aiEditHistory:
            return localizer.string("workspaceToolbar.panel.aiEditHistory", fallback: "Edit History")
        case .templates:
            return localizer.string("workspaceToolbar.panel.templates", fallback: "Templates")
        case .macros:
            return localizer.string("workspaceToolbar.panel.macros", fallback: "Macros")
        case .dbCloud:
            return localizer.string("workspaceToolbar.panel.dbCloud", fallback: "DB/Cloud")
        case .subagent:
            return localizer.string("workspaceToolbar.panel.subagent", fallback: "Agent")
        }
    }

    private func updateHorizontalStripActionIcons(_ strip: HorizontalTabStripView) {
        if let targetTabID = visibleTabID ?? tabManager.activeTabID {
            let sm = tabSplitCoordinator.splitManager(for: targetTabID)
            let leaves = sm.rootNode.allLeafIDs()
            let canClose = leaves.count > 1

            let focusedType: PanelType
            if let focusedID = sm.focusedLeafID,
               let focusedLeaf = leaves.first(where: { $0.leafID == focusedID }) {
                focusedType = sm.panelType(for: focusedLeaf.terminalID)
            } else {
                focusedType = .terminal
            }

            strip.updateActionIcons(panelType: focusedType, canClose: canClose)
        }
    }
}
