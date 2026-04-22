// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HorizontalTabStripView.swift - Custom horizontal tab strip for workspace panels.

import AppKit

// MARK: - Horizontal Tab Strip View

/// Custom horizontal tab bar displayed above the terminal content area.
///
/// Styled to match the Catppuccin Mocha theme with rounded tab buttons.
/// Each tab shows an icon and title. The active tab is highlighted.
///
/// ## Layout
///
/// ```
/// +----------------------------------------------+
/// | [icon Terminal] [icon Browser] ...        [+] |
/// +----------------------------------------------+
/// ```
@MainActor
final class HorizontalTabStripView: NSView {

    /// The strip can represent either top-level workspace tabs or the
    /// focused tab's split/panel leaves. Labels and context menus need to
    /// match the active mode so `tab-position = top` does not look like a
    /// pane toolbar.
    enum ItemKind {
        case workspaceTab
        case panel
    }

    // MARK: - Properties

    /// Callback when "Terminal (Side by Side)" is selected from the add menu.
    var onAddTab: (() -> Void)?

    /// Callback when "Terminal (Stacked)" is selected from the add menu.
    var onAddStackedTerminal: (() -> Void)?

    /// Callback when "Browser" is selected from the add menu.
    var onAddBrowser: (() -> Void)?

    /// Callback when "Markdown" is selected from the add menu.
    var onAddMarkdown: (() -> Void)?

    /// Callback when the close button is clicked on a tab by index.
    var onCloseTab: ((Int) -> Void)?

    /// Callback when a tab is clicked by index.
    var onSelectTab: ((Int) -> Void)?

    /// Callback to swap two tab positions by their indices.
    var onSwapTabs: ((Int, Int) -> Void)?

    /// Callback when the "Split Side by Side" action icon is clicked.
    var onSplitSideBySide: (() -> Void)?

    /// Callback when the "Split Stacked" action icon is clicked.
    var onSplitStacked: (() -> Void)?

    /// Callback when the "Open Browser" action icon is clicked.
    var onOpenBrowser: (() -> Void)?

    /// Callback when the "Open Markdown" action icon is clicked.
    var onOpenMarkdown: (() -> Void)?

    /// Callback when the "Reload" action icon is clicked.
    var onReload: (() -> Void)?

    /// Callback when the "Back" action icon is clicked in a browser panel.
    var onGoBack: (() -> Void)?

    /// Callback when the "Forward" action icon is clicked in a browser panel.
    var onGoForward: (() -> Void)?

    /// Callback when the "Close Focused Pane" action icon is clicked.
    var onClosePanel: (() -> Void)?

    /// Callback when the one-click light/dark theme toggle is clicked.
    var onToggleThemeMode: (() -> Void)?

    /// Callback when a tab is renamed by double-click. Parameters: (index, newTitle).
    var onRenameTab: ((Int, String) -> Void)?

    /// Current tab items.
    private(set) var tabs: [(title: String, icon: String, isActive: Bool)] = []

    /// Current semantic mode for close labels, context menus and rename UI.
    private var itemKind: ItemKind = .panel

    /// Leading inset used by the split/panel toolbar variant.
    private static let panelLeadingInset: CGFloat = 8

    /// Leading inset used when the strip becomes the classic top-level tab bar.
    ///
    /// In `tab-position = top` the strip spans the full width of the content
    /// view and sits under the window's traffic-light buttons. Without this
    /// reserve, the first tab starts at x=0 and is partially hidden by the
    /// red/yellow/green controls.
    private static let workspaceTabLeadingInset: CGFloat = 150

    /// Stored so `setItemKind(_:)` can move only the tab content while keeping
    /// the right-side action buttons anchored to the window edge.
    private var tabStackLeadingConstraint: NSLayoutConstraint?

    /// The stack view holding tab buttons.
    private let tabStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// The "+" add button.
    private let addButton: NSButton = {
        let btn = NSButton()
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        if let img = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Panel") {
            btn.image = img.withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        }
        btn.contentTintColor = CocxyColors.overlay1
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.toolTip = "Add Panel"
        return btn
    }()

    /// Stack view holding contextual action icon buttons on the right side.
    private let actionStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// One-click light/dark toggle that lives next to the split/action
    /// controls instead of crowding the workspace sidebar header.
    private let themeModeButton: NSButton = {
        let btn = NSButton()
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        btn.wantsLayer = true
        btn.contentTintColor = CocxyColors.overlay1
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setAccessibilityLabel("Toggle light or dark theme")
        return btn
    }()

    /// Vibrancy background for glass effect when transparency is enabled.
    private let vibrancyView: NSVisualEffectView = {
        let vev = NSVisualEffectView()
        vev.material = .headerView
        vev.blendingMode = .behindWindow
        vev.state = .active
        vev.translatesAutoresizingMaskIntoConstraints = false
        return vev
    }()

    /// Opaque overlay that covers the vibrancy view when transparency is off.
    private let solidOverlay: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = CocxyColors.mantle.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    /// Bottom border line.
    private let borderLine: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = CocxyColors.surface0.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: - Initialization

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
        // Show a default "Terminal" tab.
        updateTabs([(title: "Terminal", icon: "terminal.fill", isActive: true)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HorizontalTabStripView does not support NSCoding")
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true

        // Background layers: vibrancy underneath, solid overlay on top.
        // The solid overlay is shown by default (opaque mode).
        addSubview(vibrancyView)
        addSubview(solidOverlay)

        addSubview(tabStack)
        addSubview(actionStack)
        addSubview(themeModeButton)
        addSubview(addButton)
        addSubview(borderLine)

        addButton.target = self
        addButton.action = #selector(addButtonClicked)
        themeModeButton.target = self
        themeModeButton.action = #selector(themeModeButtonClicked)
        setThemeMode(isLight: false)

        let tabStackLeadingConstraint = tabStack.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: Self.panelLeadingInset
        )
        self.tabStackLeadingConstraint = tabStackLeadingConstraint

        NSLayoutConstraint.activate([
            // Background layers fill the entire view.
            vibrancyView.leadingAnchor.constraint(equalTo: leadingAnchor),
            vibrancyView.trailingAnchor.constraint(equalTo: trailingAnchor),
            vibrancyView.topAnchor.constraint(equalTo: topAnchor),
            vibrancyView.bottomAnchor.constraint(equalTo: bottomAnchor),

            solidOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            solidOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            solidOverlay.topAnchor.constraint(equalTo: topAnchor),
            solidOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),

            tabStackLeadingConstraint,
            tabStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            tabStack.trailingAnchor.constraint(lessThanOrEqualTo: actionStack.leadingAnchor, constant: -8),

            actionStack.trailingAnchor.constraint(equalTo: themeModeButton.leadingAnchor, constant: -6),
            actionStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            themeModeButton.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -4),
            themeModeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            themeModeButton.widthAnchor.constraint(equalToConstant: 22),
            themeModeButton.heightAnchor.constraint(equalToConstant: 22),

            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 24),
            addButton.heightAnchor.constraint(equalToConstant: 24),

            borderLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            borderLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            borderLine.bottomAnchor.constraint(equalTo: bottomAnchor),
            borderLine.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    // MARK: - Public API

    /// Toggles between vibrancy (glass) and solid background modes.
    ///
    /// When transparent, the solid overlay is hidden and the underlying
    /// `NSVisualEffectView` provides a native blur-behind-window effect.
    /// When opaque, the solid overlay covers the vibrancy view.
    ///
    /// - Parameter transparent: `true` for glass effect, `false` for solid.
    func setTransparent(_ transparent: Bool) {
        solidOverlay.isHidden = transparent
    }

    /// Forces a specific `NSAppearance` on the vibrancy view.
    ///
    /// - Parameter appearance: The forced appearance, or `nil` to follow the
    ///   system / window chain.
    ///
    /// Has no visible effect in opaque mode — the solid overlay hides the
    /// vibrancy view entirely.
    func setVibrancyAppearanceOverride(_ appearance: NSAppearance?) {
        vibrancyView.appearance = appearance
    }

    /// Updates the theme toggle affordance without invoking the action.
    ///
    /// - Parameter isLight: `true` when the active theme is light. The
    ///   icon points at the next action: moon = switch back to dark,
    ///   sun = switch to light.
    func setThemeMode(isLight: Bool) {
        let symbol = isLight ? "moon.fill" : "sun.max.fill"
        let tooltip = isLight ? "Switch to dark theme" : "Switch to light theme"
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
            themeModeButton.image = img.withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        }
        themeModeButton.toolTip = tooltip
    }

    /// Updates the tab strip with the given tab items.
    func updateTabs(_ newTabs: [(title: String, icon: String, isActive: Bool)]) {
        self.tabs = newTabs
        let hasMultipleTabs = newTabs.count > 1

        // Remove old tab containers.
        tabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Create new tab containers with close buttons.
        for (index, tab) in newTabs.enumerated() {
            let container = createTabContainer(
                title: tab.title,
                icon: tab.icon,
                isActive: tab.isActive,
                index: index,
                showCloseButton: hasMultipleTabs
            )
            tabStack.addArrangedSubview(container)
        }
    }

    /// Updates the semantic meaning of the strip items.
    ///
    /// `workspaceTab` is used when classic tabs live at the top of the
    /// window. `panel` is used everywhere else, where the strip controls
    /// panes inside the active tab.
    func setItemKind(_ itemKind: ItemKind) {
        let inset = itemKind == .workspaceTab
            ? Self.workspaceTabLeadingInset
            : Self.panelLeadingInset
        tabStackLeadingConstraint?.constant = inset

        guard self.itemKind != itemKind else { return }
        self.itemKind = itemKind
        updateTabs(tabs)
    }

    /// Exposes the active leading reserve to regression tests without making
    /// the stack view itself part of the public surface area.
    var tabContentLeadingInsetForTesting: CGFloat {
        tabStackLeadingConstraint?.constant ?? Self.panelLeadingInset
    }

    // MARK: - Tab Container Creation

    private func createTabContainer(
        title: String,
        icon: String,
        isActive: Bool,
        index: Int,
        showCloseButton: Bool
    ) -> NSView {
        let container = DraggableTabContainer()
        container.wantsLayer = true
        container.translatesAutoresizingMaskIntoConstraints = false
        container.tabIndex = index
        container.itemKind = itemKind
        container.onReorder = { [weak self] fromIndex, toIndex in
            self?.onSwapTabs?(fromIndex, toIndex)
        }
        container.onRename = { [weak self] tabIndex, newTitle in
            self?.onRenameTab?(tabIndex, newTitle)
        }

        // Tab label button.
        let btn = createTabButton(title: title, icon: icon, isActive: isActive, index: index)
        container.addSubview(btn)

        // Close button.
        let closeBtn = createCloseButton(index: index)
        closeBtn.isHidden = !showCloseButton
        container.addSubview(closeBtn)

        // Context menu for reordering.
        if showCloseButton {
            container.menu = buildTabContextMenu(
                index: index,
                isFirst: index == 0,
                isLast: index == tabs.count - 1
            )
        }

        // Styling for the container background.
        if isActive {
            container.layer?.backgroundColor = CocxyColors.surface0.cgColor
            container.layer?.cornerRadius = 6
            container.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        } else {
            container.layer?.backgroundColor = NSColor.clear.cgColor
        }

        NSLayoutConstraint.activate([
            btn.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            btn.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            closeBtn.leadingAnchor.constraint(equalTo: btn.trailingAnchor, constant: 2),
            closeBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            closeBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 20),
            closeBtn.heightAnchor.constraint(equalToConstant: 20),

            container.heightAnchor.constraint(equalToConstant: 28),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: showCloseButton ? 110 : 90),
        ])

        return container
    }

    /// Builds a context menu for reordering a horizontal tab or panel.
    private func buildTabContextMenu(index: Int, isFirst: Bool, isLast: Bool) -> NSMenu {
        let menu = NSMenu()

        let moveLeftItem = NSMenuItem(
            title: "Move Left",
            action: #selector(handleMoveTabLeft(_:)),
            keyEquivalent: ""
        )
        moveLeftItem.target = self
        moveLeftItem.tag = index
        moveLeftItem.isEnabled = !isFirst
        if let img = NSImage(systemSymbolName: "arrow.left", accessibilityDescription: nil) {
            moveLeftItem.image = img
        }
        menu.addItem(moveLeftItem)

        let moveRightItem = NSMenuItem(
            title: "Move Right",
            action: #selector(handleMoveTabRight(_:)),
            keyEquivalent: ""
        )
        moveRightItem.target = self
        moveRightItem.tag = index
        moveRightItem.isEnabled = !isLast
        if let img = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil) {
            moveRightItem.image = img
        }
        menu.addItem(moveRightItem)

        menu.addItem(NSMenuItem.separator())

        let closeItem = NSMenuItem(
            title: itemKind == .workspaceTab ? "Close Tab" : "Close Panel",
            action: #selector(closeTabClicked(_:)),
            keyEquivalent: ""
        )
        closeItem.target = self
        closeItem.tag = index
        if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil) {
            closeItem.image = img
        }
        menu.addItem(closeItem)

        return menu
    }

    @objc private func handleMoveTabLeft(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index > 0 else { return }
        onSwapTabs?(index, index - 1)
    }

    @objc private func handleMoveTabRight(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < tabs.count - 1 else { return }
        onSwapTabs?(index, index + 1)
    }

    private func createTabButton(title: String, icon: String, isActive: Bool, index: Int) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        btn.wantsLayer = true

        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            btn.image = img.withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
        }
        btn.title = " \(title)"
        btn.imagePosition = .imageLeading
        btn.font = .systemFont(ofSize: 11, weight: isActive ? .semibold : .regular)
        btn.tag = index
        btn.focusRingType = .exterior
        btn.setAccessibilityLabel(title)
        btn.setAccessibilityRole(.radioButton)
        btn.target = self
        btn.action = #selector(tabClicked(_:))

        if isActive {
            btn.contentTintColor = CocxyColors.text
        } else {
            btn.contentTintColor = CocxyColors.subtext0
        }

        // No background on the button itself; the container handles it.
        btn.layer?.backgroundColor = NSColor.clear.cgColor
        btn.translatesAutoresizingMaskIntoConstraints = false

        return btn
    }

    private func createCloseButton(index: Int) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        btn.wantsLayer = true
        if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab") {
            btn.image = img.withSymbolConfiguration(.init(pointSize: 8, weight: .medium))
        }
        btn.contentTintColor = CocxyColors.overlay0
        btn.tag = index
        btn.target = self
        btn.action = #selector(closeTabClicked(_:))
        btn.translatesAutoresizingMaskIntoConstraints = false
        let label = itemKind == .workspaceTab ? "Close tab" : "Close panel"
        btn.setAccessibilityLabel(label)
        btn.toolTip = label
        return btn
    }

    // MARK: - Actions

    @objc private func tabClicked(_ sender: NSButton) {
        onSelectTab?(sender.tag)
    }

    @objc private func closeTabClicked(_ sender: NSButton) {
        onCloseTab?(sender.tag)
    }

    @objc private func addButtonClicked(_ sender: Any?) {
        guard let button = sender as? NSButton else {
            onAddTab?()
            return
        }

        let menu = NSMenu()

        let sideBySideItem = NSMenuItem(
            title: "Terminal (Side by Side)",
            action: #selector(addTerminal),
            keyEquivalent: "d"
        )
        sideBySideItem.keyEquivalentModifierMask = [.command]
        sideBySideItem.target = self
        if let img = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil) {
            sideBySideItem.image = img
        }
        menu.addItem(sideBySideItem)

        let stackedItem = NSMenuItem(
            title: "Terminal (Stacked)",
            action: #selector(addStackedTerminal),
            keyEquivalent: "d"
        )
        stackedItem.keyEquivalentModifierMask = [.command, .shift]
        stackedItem.target = self
        if let img = NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: nil) {
            stackedItem.image = img
        }
        menu.addItem(stackedItem)

        menu.addItem(NSMenuItem.separator())

        let browserItem = NSMenuItem(title: "Browser", action: #selector(addBrowser), keyEquivalent: "")
        browserItem.target = self
        if let img = NSImage(systemSymbolName: "globe", accessibilityDescription: nil) {
            browserItem.image = img
        }
        menu.addItem(browserItem)

        let markdownItem = NSMenuItem(title: "Markdown", action: #selector(addMarkdown), keyEquivalent: "")
        markdownItem.target = self
        if let img = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil) {
            markdownItem.image = img
        }
        menu.addItem(markdownItem)

        let point = NSPoint(x: button.bounds.minX, y: button.bounds.maxY + 4)
        menu.popUp(positioning: nil, at: point, in: button)
    }

    @objc private func addTerminal() { onAddTab?() }
    @objc private func addStackedTerminal() { onAddStackedTerminal?() }
    @objc private func addBrowser() { onAddBrowser?() }
    @objc private func addMarkdown() { onAddMarkdown?() }

    // MARK: - Contextual Action Icons

    /// Updates the action icon toolbar for the currently focused panel type.
    ///
    /// Shows contextual buttons on the right side of the tab strip that change
    /// based on the focused panel. Terminal panels get split + browser + markdown
    /// actions; browser panels get split + reload; markdown panels get split only.
    /// A close button is appended when `canClose` is true (multiple panels).
    ///
    /// - Parameters:
    ///   - panelType: The type of the currently focused panel.
    ///   - canClose: Whether the close action should be shown (requires > 1 panel).
    func updateActionIcons(panelType: PanelType, canClose: Bool) {
        actionStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Split actions are available for all panel types.
        actionStack.addArrangedSubview(
            createActionButton(
                icon: "rectangle.split.2x1",
                tooltip: "Split Side by Side",
                accessibilityID: "action:splitSideBySide",
                action: #selector(handleSplitSideBySide)
            )
        )
        actionStack.addArrangedSubview(
            createActionButton(
                icon: "rectangle.split.1x2",
                tooltip: "Split Stacked",
                accessibilityID: "action:splitStacked",
                action: #selector(handleSplitStacked)
            )
        )

        switch panelType {
        case .terminal:
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "globe",
                    tooltip: "Open Browser Here",
                    accessibilityID: "action:openBrowser",
                    action: #selector(handleOpenBrowser)
                )
            )
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "doc.text",
                    tooltip: "Open Markdown",
                    accessibilityID: "action:openMarkdown",
                    action: #selector(handleOpenMarkdown)
                )
            )
        case .browser:
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "chevron.left",
                    tooltip: "Back",
                    accessibilityID: "action:goBack",
                    action: #selector(handleGoBack)
                )
            )
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "chevron.right",
                    tooltip: "Forward",
                    accessibilityID: "action:goForward",
                    action: #selector(handleGoForward)
                )
            )
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "arrow.clockwise",
                    tooltip: "Reload",
                    accessibilityID: "action:reload",
                    action: #selector(handleReload)
                )
            )
        case .markdown, .subagent:
            break
        }

        if canClose {
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "rectangle.badge.xmark",
                    tooltip: "Close Focused Pane",
                    accessibilityID: "action:closePanel",
                    action: #selector(handleClosePanel)
                )
            )
        }
    }

    private func createActionButton(
        icon: String,
        tooltip: String,
        accessibilityID: String,
        action: Selector
    ) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        btn.wantsLayer = true
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip) {
            btn.image = img.withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        }
        btn.contentTintColor = CocxyColors.overlay1
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.toolTip = tooltip
        btn.setAccessibilityLabel(accessibilityID)
        btn.target = self
        btn.action = action

        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 22),
            btn.heightAnchor.constraint(equalToConstant: 22),
        ])

        return btn
    }

    @objc private func handleSplitSideBySide() { onSplitSideBySide?() }
    @objc private func handleSplitStacked() { onSplitStacked?() }
    @objc private func handleOpenBrowser() { onOpenBrowser?() }
    @objc private func handleOpenMarkdown() { onOpenMarkdown?() }
    @objc private func handleReload() { onReload?() }
    @objc private func handleGoBack() { onGoBack?() }
    @objc private func handleGoForward() { onGoForward?() }
    @objc private func handleClosePanel() { onClosePanel?() }
    @objc private func themeModeButtonClicked() { onToggleThemeMode?() }

    // MARK: - Drag-and-Drop Pasteboard Type

    /// Custom pasteboard type for tab reorder drag-and-drop.
    static let tabReorderPasteboardType = NSPasteboard.PasteboardType("com.cocxy.terminal.horizontalTabReorder")

    // MARK: - Double-Click Titlebar Zoom

    override func mouseDown(with event: NSEvent) {
        // Forward double-click on the empty area to the standard titlebar zoom behavior.
        if event.clickCount == 2 {
            let hitView = hitTest(convert(event.locationInWindow, from: nil))
            let isEmptyArea = hitView === self || hitView == nil
                || hitView === vibrancyView || hitView === solidOverlay
            if isEmptyArea {
                if let w = window, w.styleMask.contains(.fullScreen) {
                    w.toggleFullScreen(nil)
                } else {
                    window?.zoom(nil)
                }
                return
            }
        }
        super.mouseDown(with: event)
    }
}

// MARK: - Draggable Tab Container

/// A tab container view that supports drag-and-drop reordering
/// within the horizontal tab strip.
///
/// Acts as both an `NSDraggingSource` (can be dragged) and an
/// `NSDraggingDestination` (can receive drops). The tab index is
/// stored in the pasteboard to identify source and destination.
@MainActor
final class DraggableTabContainer: NSView, NSDraggingSource {

    /// The index of this tab in the strip.
    var tabIndex: Int = 0

    /// Semantic meaning of the item represented by this container.
    var itemKind: HorizontalTabStripView.ItemKind = .panel

    /// Callback invoked when a tab is dropped onto this container.
    /// Parameters: (sourceIndex, destinationIndex).
    var onReorder: ((Int, Int) -> Void)?

    /// Callback invoked when the user renames this tab via double-click.
    /// Parameters: (tabIndex, newTitle).
    var onRename: ((Int, String) -> Void)?

    /// Whether the tab is currently in rename editing mode.
    private(set) var isEditing: Bool = false

    /// Drop indicator shown during drag-over.
    private let dropIndicator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = CocxyColors.blue.withAlphaComponent(0.6).cgColor
        view.layer?.cornerRadius = 1
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([HorizontalTabStripView.tabReorderPasteboardType])
        addSubview(dropIndicator)
        NSLayoutConstraint.activate([
            dropIndicator.leadingAnchor.constraint(equalTo: leadingAnchor),
            dropIndicator.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            dropIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            dropIndicator.widthAnchor.constraint(equalToConstant: 2),
        ])
    }

    /// Override hitTest so the container receives mouse events instead of
    /// child buttons. Without this, the NSButton captures mouseDown and
    /// drag detection never fires. Close buttons (identified by their
    /// accessibility label) still handle their own clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }

        // Let the close button handle its own clicks.
        for subview in subviews where subview is NSButton {
            let btnPoint = subview.convert(point, from: superview)
            if subview.bounds.contains(btnPoint),
               Self.isCloseButtonLabel(subview.accessibilityLabel()) {
                return subview
            }
        }

        return self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DraggableTabContainer does not support NSCoding")
    }

    /// Minimum horizontal distance in points before a mouse-down is
    /// considered a drag rather than a click. Exposed as a static
    /// constant so tests can verify its value.
    static let dragThreshold: CGFloat = 5

    /// Both semantic modes use a close affordance, but the accessibility label
    /// changes from "Close tab" to "Close panel". Keeping this predicate shared
    /// prevents panel close clicks from being swallowed by the drag/select
    /// container.
    static func isCloseButtonLabel(_ label: String?) -> Bool {
        label == "Close tab" || label == "Close panel"
    }

    // MARK: - Click vs Drag Detection

    /// Intercepts `mouseDown` to distinguish clicks from drags.
    ///
    /// The nested NSButton normally captures `mouseDown`, preventing
    /// the container's `mouseDragged` from ever firing. This override
    /// enters a local event loop: if the user moves beyond
    /// `dragThreshold` before releasing, a drag session starts;
    /// otherwise the event is forwarded to the button as a normal click.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            startEditing()
            return
        }
        if isEditing { return }

        let startLocation = convert(event.locationInWindow, from: nil)

        var isDragging = false
        while true {
            guard let nextEvent = window?.nextEvent(
                matching: [.leftMouseUp, .leftMouseDragged]
            ) else {
                break
            }

            if nextEvent.type == .leftMouseUp {
                // Short click — find the tab button and trigger its action.
                for subview in subviews where subview is NSButton {
                    if let btn = subview as? NSButton,
                       !Self.isCloseButtonLabel(btn.accessibilityLabel()) {
                        btn.performClick(nil)
                        return
                    }
                }
                return
            }

            // Check if horizontal movement exceeds the drag threshold.
            let currentLocation = convert(nextEvent.locationInWindow, from: nil)
            let horizontalDistance = abs(currentLocation.x - startLocation.x)
            if horizontalDistance > Self.dragThreshold {
                isDragging = true
                break
            }
        }

        if isDragging {
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(
                String(tabIndex),
                forType: HorizontalTabStripView.tabReorderPasteboardType
            )

            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            draggingItem.setDraggingFrame(bounds, contents: snapshot())

            beginDraggingSession(with: [draggingItem], event: event, source: self)
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropIndicator.isHidden = false
        return .move
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dropIndicator.isHidden = true
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        .move
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dropIndicator.isHidden = true

        guard let pasteboardItem = sender.draggingPasteboard.pasteboardItems?.first,
              let indexString = pasteboardItem.string(
                forType: HorizontalTabStripView.tabReorderPasteboardType
              ),
              let sourceIndex = Int(indexString) else {
            return false
        }

        guard sourceIndex != tabIndex else { return false }

        onReorder?(sourceIndex, tabIndex)
        return true
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        dropIndicator.isHidden = true
    }

    // MARK: - Inline Rename

    /// Enters rename mode via a floating rename sheet.
    func startEditing() {
        guard !isEditing, let parentWindow = window else { return }
        isEditing = true

        let currentTitle = currentTabButtonTitle()
        let index = tabIndex
        RenameSheetController.present(
            on: parentWindow,
            currentName: currentTitle,
            placeholder: itemKind == .workspaceTab ? "Tab name" : "Panel name",
            icon: itemKind == .workspaceTab ? "terminal.fill" : "rectangle.split.2x1"
        ) { [weak self] newTitle in
            self?.isEditing = false
            if let newTitle {
                self?.onRename?(index, newTitle)
            }
        }
    }

    /// Returns the title text from the tab button inside this container.
    private func currentTabButtonTitle() -> String {
        for subview in subviews where subview is NSButton {
            if let btn = subview as? NSButton,
               !Self.isCloseButtonLabel(btn.accessibilityLabel()) {
                return btn.title.trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    // MARK: - Snapshot

    /// Creates a bitmap snapshot of this view for the drag image.
    private func snapshot() -> NSImage {
        let image = NSImage(size: bounds.size)
        guard let bitmapRep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return image
        }
        cacheDisplay(in: bounds, to: bitmapRep)
        image.addRepresentation(bitmapRep)
        return image
    }
}
