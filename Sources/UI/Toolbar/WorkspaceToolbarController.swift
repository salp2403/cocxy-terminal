// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorkspaceToolbarController.swift - Horizontal panel tabs in the window toolbar.

import AppKit

// MARK: - Toolbar Item Identifier

private extension NSToolbarItem.Identifier {
    static let panelPrefix = "com.cocxy.panel."
    static func panel(_ index: Int) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("\(panelPrefix)\(index)")
    }
    static let flexibleSpace = NSToolbarItem.Identifier.flexibleSpace
    static let addPanel = NSToolbarItem.Identifier("com.cocxy.addPanel")
}

// MARK: - Panel Tab Info

/// Display information for a panel tab in the toolbar.
struct PanelTabInfo: Equatable {
    let leafID: UUID
    let contentID: UUID
    let panelType: PanelType
    let title: String
    let isFocused: Bool

    var symbolName: String {
        switch panelType {
        case .terminal: return "terminal"
        case .browser: return "globe"
        case .markdown: return "doc.text"
        case .editor: return "doc.plaintext"
        case .notebook: return "book"
        case .workflow: return "arrow.triangle.branch"
        case .sessionReplay: return "record.circle"
        case .aiEditHistory: return "clock.arrow.circlepath"
        case .templates: return "square.grid.2x2"
        case .macros: return "keyboard"
        case .dbCloud: return "externaldrive.connected.to.line.below"
        case .subagent: return "person.2"
        }
    }
}

// MARK: - Workspace Toolbar Controller

/// Manages an NSToolbar that displays horizontal panel tabs for the active workspace.
///
/// The toolbar shows one tab per panel (split pane) in the current workspace.
/// When only a single panel exists, the toolbar is hidden to save space.
/// Clicking a tab focuses that panel. The active panel is highlighted.
///
/// ## Integration
///
/// The controller observes the `SplitManager` for the active tab and updates
/// toolbar items when panels are added, removed, or focused.
///
/// - SeeAlso: `SplitManager` for panel state.
/// - SeeAlso: `MainWindowController` for window integration.
@MainActor
final class WorkspaceToolbarController: NSObject {

    // MARK: - Properties

    /// The window this toolbar belongs to.
    private weak var window: NSWindow?

    /// The NSToolbar instance.
    private var toolbar: NSToolbar?

    /// Current panel tab items.
    private(set) var panelTabs: [PanelTabInfo] = []

    /// Custom titles supplied by `SplitManager`, keyed by panel content id.
    private var customPanelTitles: [UUID: String] = [:]

    /// Callback when a panel tab is clicked.
    var onPanelSelected: ((UUID) -> Void)?

    /// Callback when the "add panel" button is clicked.
    var onAddPanel: (() -> Void)?

    /// Whether the toolbar is currently visible.
    private(set) var isVisible: Bool = false

    private var localizer: AppLocalizer

    // MARK: - Initialization

    init(
        window: NSWindow,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.window = window
        self.localizer = localizer
        super.init()
        setupToolbar()
    }

    // MARK: - Setup

    private func setupToolbar() {
        let tb = NSToolbar(identifier: "CocxyWorkspaceToolbar")
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.allowsUserCustomization = false
        tb.showsBaselineSeparator = false
        self.toolbar = tb
    }

    // MARK: - Public API

    /// Updates the toolbar with the current panel state.
    ///
    /// Reads panel layout and focus from `splitManager` directly; panel types
    /// are resolved via `SplitManager.panelType(for:)`.
    ///
    /// - Parameter splitManager: The split manager for the active tab.
    func update(splitManager: SplitManager) {
        let leaves = splitManager.rootNode.allLeafIDs()
        let focusedID = splitManager.focusedLeafID

        panelTabs = leaves.enumerated().map { index, leaf in
            let type = splitManager.panelType(for: leaf.terminalID)
            let title = splitManager.panelTitle(for: leaf.terminalID)
                ?? Self.localizedPanelTitle(for: type, index: index, using: localizer)
            return PanelTabInfo(
                leafID: leaf.leafID,
                contentID: leaf.terminalID,
                panelType: type,
                title: title,
                isFocused: leaf.leafID == focusedID
            )
        }
        customPanelTitles = Dictionary(uniqueKeysWithValues: leaves.compactMap { leaf in
            guard let title = splitManager.panelTitle(for: leaf.terminalID) else { return nil }
            return (leaf.terminalID, title)
        })

        // Always show the toolbar — even with 1 panel, show the tab.
        if !isVisible {
            showToolbar()
        }
        rebuildToolbarItems()
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        panelTabs = panelTabs.enumerated().map { index, tab in
            PanelTabInfo(
                leafID: tab.leafID,
                contentID: tab.contentID,
                panelType: tab.panelType,
                title: customPanelTitles[tab.contentID]
                    ?? Self.localizedPanelTitle(for: tab.panelType, index: index, using: localizer),
                isFocused: tab.isFocused
            )
        }
        rebuildToolbarItems()
    }

    /// Forces the toolbar to hide.
    func hide() {
        hideToolbar()
    }

    // MARK: - Visibility

    private func showToolbar() {
        guard let window else { return }
        window.toolbar = toolbar
        window.titleVisibility = .hidden
        isVisible = true
    }

    private func hideToolbar() {
        guard let window else { return }
        window.toolbar = nil
        isVisible = false
    }

    // MARK: - Toolbar Rebuild

    private func rebuildToolbarItems() {
        guard let toolbar, window?.toolbar === toolbar else { return }

        // Remove existing items safely.
        while toolbar.items.count > 0 {
            toolbar.removeItem(at: 0)
        }

        // Insert panel items.
        for i in 0..<panelTabs.count {
            toolbar.insertItem(withItemIdentifier: .panel(i), at: i)
        }

        // Add flexible space and add-panel button.
        toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: panelTabs.count)
        toolbar.insertItem(withItemIdentifier: .addPanel, at: panelTabs.count + 1)
    }

    // MARK: - Item Creation

    private func createPanelItem(at index: Int) -> NSToolbarItem {
        guard index < panelTabs.count else {
            return NSToolbarItem(itemIdentifier: .panel(index))
        }

        let tab = panelTabs[index]
        let item = NSToolbarItem(itemIdentifier: .panel(index))
        item.label = tab.title
        item.toolTip = tab.title
        item.tag = index

        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.setButtonType(.toggle)
        button.state = tab.isFocused ? .on : .off
        button.title = tab.title
        button.tag = index
        button.target = self
        button.action = #selector(panelTabClicked(_:))

        if let image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.title) {
            button.image = image.withSymbolConfiguration(
                .init(pointSize: 11, weight: .medium)
            )
        }
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 11, weight: tab.isFocused ? .semibold : .regular)
        button.translatesAutoresizingMaskIntoConstraints = false

        // Style based on focus state.
        if tab.isFocused {
            button.contentTintColor = CocxyColors.blue
        } else {
            button.contentTintColor = CocxyColors.subtext0
        }

        item.view = button
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 24),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            button.widthAnchor.constraint(lessThanOrEqualToConstant: 160),
        ])

        return item
    }

    private func createAddPanelItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .addPanel)
        let label = Self.localizedAddPanel(using: localizer)
        item.label = label
        item.toolTip = Self.localizedAddPanelTooltip(using: localizer)

        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        if let image = NSImage(systemSymbolName: "plus", accessibilityDescription: label) {
            button.image = image.withSymbolConfiguration(
                .init(pointSize: 11, weight: .medium)
            )
        }
        button.contentTintColor = CocxyColors.overlay0
        button.target = self
        button.action = #selector(addPanelClicked(_:))
        button.translatesAutoresizingMaskIntoConstraints = false

        item.view = button
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])

        return item
    }

    static func localizedPanelTitle(
        for panelType: PanelType,
        index: Int,
        using localizer: AppLocalizer
    ) -> String {
        switch panelType {
        case .terminal:
            return String(
                format: localizer.string("workspaceToolbar.panel.terminal", fallback: "Terminal %d"),
                index + 1
            )
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

    static func localizedAddPanel(using localizer: AppLocalizer) -> String {
        localizer.string("workspaceToolbar.addPanel.label", fallback: "Add Panel")
    }

    static func localizedAddPanelTooltip(using localizer: AppLocalizer) -> String {
        localizer.string("workspaceToolbar.addPanel.tooltip", fallback: "Split with a new panel")
    }

    // MARK: - Actions

    @objc private func panelTabClicked(_ sender: NSButton) {
        let index = sender.tag
        guard index < panelTabs.count else { return }
        onPanelSelected?(panelTabs[index].leafID)
    }

    @objc private func addPanelClicked(_ sender: Any?) {
        onAddPanel?()
    }
}

// MARK: - NSToolbarDelegate

extension WorkspaceToolbarController: NSToolbarDelegate {

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == .addPanel {
            return createAddPanelItem()
        }
        // Parse panel index from identifier.
        let prefix = NSToolbarItem.Identifier.panelPrefix
        if itemIdentifier.rawValue.hasPrefix(prefix),
           let indexStr = itemIdentifier.rawValue.components(separatedBy: prefix).last,
           let index = Int(indexStr) {
            return createPanelItem(at: index)
        }
        return nil
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var identifiers: [NSToolbarItem.Identifier] = []
        for i in 0..<panelTabs.count {
            identifiers.append(.panel(i))
        }
        identifiers.append(.flexibleSpace)
        identifiers.append(.addPanel)
        return identifiers
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarAllowedItemIdentifiers(toolbar)
    }
}
