// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+TabStrip.swift - Horizontal tab strip refresh logic.

import AppKit

// MARK: - Horizontal Tab Strip

/// Extension that manages the horizontal tab strip at the top of the
/// terminal area. Builds tab entries from the active tab's split panes
/// and updates the strip view.
extension MainWindowController {

    /// Updates the horizontal tab strip to reflect current workspace state.
    func refreshTabStrip() {
        guard let strip = horizontalTabStripView as? HorizontalTabStripView else { return }

        // Build tab entries from the active tab's split panes.
        var tabEntries: [(title: String, icon: String, isActive: Bool)] = []

        if let activeTabID = tabManager.activeTabID {
            let sm = tabSplitCoordinator.splitManager(for: activeTabID)
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
                    case .subagent: icon = "person.2"
                    }
                } else {
                    switch panelType {
                    case .terminal:
                        terminalIndex += 1
                        let dirName = tabManager.activeTab?.workingDirectory.lastPathComponent ?? "Terminal"
                        title = leaves.count > 1 ? "\(dirName) \(terminalIndex)" : dirName
                        icon = "terminal.fill"
                    case .browser:
                        title = "Browser"
                        icon = "globe"
                    case .markdown:
                        title = "Markdown"
                        icon = "doc.text"
                    case .subagent:
                        title = "Agent"
                        icon = "person.2"
                    }
                }

                tabEntries.append((title: title, icon: icon, isActive: leaf.leafID == focusedID))
            }
        }

        if tabEntries.isEmpty {
            let dirName = tabManager.activeTab?.workingDirectory.lastPathComponent ?? "Terminal"
            tabEntries = [(title: dirName, icon: "terminal.fill", isActive: true)]
        }

        strip.updateTabs(tabEntries)

        // Update contextual action icons based on the focused panel type.
        if let activeTabID = tabManager.activeTabID {
            let sm = tabSplitCoordinator.splitManager(for: activeTabID)
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
