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

    /// Callback when a panel tab is clicked.
    var onPanelSelected: ((UUID) -> Void)?

    /// Callback when the "add panel" button is clicked.
    var onAddPanel: (() -> Void)?

    /// Whether the toolbar is currently visible.
    private(set) var isVisible: Bool = false

    // MARK: - Initialization

    init(window: NSWindow) {
        self.window = window
        super.init()
        setupToolbar()
    }

    isolated deinit {
        toolbar?.delegate = nil
        toolbar = nil
        onPanelSelected = nil
        onAddPanel = nil
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
            let title: String
            switch type {
            case .terminal: title = "Terminal \(index + 1)"
            case .browser: title = "Browser"
            case .markdown: title = "Markdown"
            case .subagent: title = "Agent"
            }
            return PanelTabInfo(
                leafID: leaf.leafID,
                contentID: leaf.terminalID,
                panelType: type,
                title: title,
                isFocused: leaf.leafID == focusedID
            )
        }

        // Always show the toolbar — even with 1 panel, show the tab.
        if !isVisible {
            showToolbar()
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

        // Style based on focus state.
        if tab.isFocused {
            button.contentTintColor = CocxyColors.blue
        } else {
            button.contentTintColor = CocxyColors.subtext0
        }

        item.view = button
        item.minSize = NSSize(width: 80, height: 24)
        item.maxSize = NSSize(width: 160, height: 24)

        return item
    }

    private func createAddPanelItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .addPanel)
        item.label = "Add Panel"
        item.toolTip = "Split with a new panel"

        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        if let image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add panel") {
            button.image = image.withSymbolConfiguration(
                .init(pointSize: 11, weight: .medium)
            )
        }
        button.contentTintColor = CocxyColors.overlay0
        button.target = self
        button.action = #selector(addPanelClicked(_:))

        item.view = button
        item.minSize = NSSize(width: 28, height: 24)
        item.maxSize = NSSize(width: 28, height: 24)

        return item
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
