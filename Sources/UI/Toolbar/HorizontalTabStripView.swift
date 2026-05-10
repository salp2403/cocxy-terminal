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

    /// Callback when "Editor" is selected from the add menu.
    var onAddEditor: (() -> Void)?

    /// Callback when "Notebook" is selected from the add menu.
    var onAddNotebook: (() -> Void)?

    /// Callback when "Workflow" is selected from the add menu.
    var onAddWorkflow: (() -> Void)?

    /// Callback when "Session Replay" is selected from the add menu.
    var onAddSessionReplay: (() -> Void)?

    /// Callback when "Edit History" is selected from the add menu.
    var onAddAIEditHistory: (() -> Void)?

    /// Callback when "Templates" is selected from the add menu.
    var onAddTemplates: (() -> Void)?

    /// Callback when "Macros" is selected from the add menu.
    var onAddMacros: (() -> Void)?

    /// Callback when "DB/Cloud Helpers" is selected from the add menu.
    var onAddDBCloud: (() -> Void)?

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

    /// Callback when the "Open Text Editor" action icon is clicked.
    var onOpenEditor: (() -> Void)?

    /// Callback when the "Open Notebook" action icon is clicked.
    var onOpenNotebook: (() -> Void)?

    /// Callback when the "Open Workflow" action icon is clicked.
    var onOpenWorkflow: (() -> Void)?

    /// Callback when the "Open Session Replay" action icon is clicked.
    var onOpenSessionReplay: (() -> Void)?

    /// Callback when the "Open Edit History" action icon is clicked.
    var onOpenAIEditHistory: (() -> Void)?

    /// Callback when the "Open Templates" action icon is clicked.
    var onOpenTemplates: (() -> Void)?

    /// Callback when the "Open Macros" action icon is clicked.
    var onOpenMacros: (() -> Void)?

    /// Callback when the "Open DB/Cloud Helpers" action icon is clicked.
    var onOpenDBCloud: (() -> Void)?

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

    /// Local app-language resolver for tooltips, menus, and accessibility copy.
    private var localizer = AppLocalizer(languagePreference: .english)

    /// Last rendered theme-toggle state so language changes can refresh
    /// the tooltip without flipping the requested action.
    private var lastThemeModeIsLight = false

    /// Last action-icon state so language changes can rebuild tooltips
    /// without waiting for the next focus change.
    private var lastActionIconState: (
        panelType: PanelType,
        canClose: Bool,
        canAddPane: Bool,
        maxPaneCount: Int?,
        paneCreationLimitMessage: String?
    )?

    /// Whether the focused workspace can accept another split/panel leaf.
    /// The window controller owns the real limit; the strip only reflects it
    /// so users do not get a silent no-op when the maximum pane count is hit.
    private var canAddPane = true

    /// Maximum pane count used for the disabled Add Panel tooltip, if known.
    private var maxPaneCountForAddPaneLimit: Int?

    /// Specific disabled-state copy when pane creation is blocked by layout
    /// constraints before the hard max pane count is reached.
    private var paneCreationLimitMessage: String?

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
        if let img = NSImage(systemSymbolName: "plus", accessibilityDescription: nil) {
            btn.image = img.withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        }
        btn.contentTintColor = CocxyColors.overlay1
        btn.translatesAutoresizingMaskIntoConstraints = false
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
        applyLocalizedChrome()
        updateTabs([(title: Self.localizedTerminalTitle(using: localizer), icon: "terminal.fill", isActive: true)])
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

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        applyLocalizedChrome()
        updateTabs(tabs)
        if let lastActionIconState {
            updateActionIcons(
                panelType: lastActionIconState.panelType,
                canClose: lastActionIconState.canClose,
                canAddPane: lastActionIconState.canAddPane,
                maxPaneCount: lastActionIconState.maxPaneCount,
                paneCreationLimitMessage: lastActionIconState.paneCreationLimitMessage
            )
        }
    }

    private func applyLocalizedChrome() {
        let addPanelTitle = Self.localizedAddPanel(using: localizer)
        let addPanelLimitTitle = paneCreationLimitMessage
            ?? Self.localizedAddPanelLimit(
                maxPaneCount: maxPaneCountForAddPaneLimit,
                using: localizer
            )
        addButton.isEnabled = canAddPane
        addButton.alphaValue = canAddPane ? 1.0 : 0.45
        addButton.toolTip = canAddPane ? addPanelTitle : addPanelLimitTitle
        addButton.setAccessibilityLabel(canAddPane ? addPanelTitle : addPanelLimitTitle)
        themeModeButton.setAccessibilityLabel(Self.localizedThemeToggleAccessibility(using: localizer))
        setThemeMode(isLight: lastThemeModeIsLight)
    }

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
        lastThemeModeIsLight = isLight
        let symbol = isLight ? "moon.fill" : "sun.max.fill"
        let tooltip = isLight
            ? Self.localizedSwitchToDarkTheme(using: localizer)
            : Self.localizedSwitchToLightTheme(using: localizer)
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
        container.localizer = localizer
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

        container.menu = buildTabContextMenu(
            index: index,
            isFirst: index == 0,
            isLast: index == tabs.count - 1,
            canClose: showCloseButton
        )

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
    private func buildTabContextMenu(index: Int, isFirst: Bool, isLast: Bool, canClose: Bool) -> NSMenu {
        let menu = NSMenu()

        let renameItem = NSMenuItem(
            title: itemKind == .workspaceTab
                ? Self.localizedRenameTabTitle(using: localizer)
                : Self.localizedRenamePanelTitle(using: localizer),
            action: #selector(handleRenameTab(_:)),
            keyEquivalent: ""
        )
        renameItem.target = self
        renameItem.tag = index
        if let img = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil) {
            renameItem.image = img
        }
        menu.addItem(renameItem)

        menu.addItem(NSMenuItem.separator())

        let moveLeftItem = NSMenuItem(
            title: Self.localizedMoveLeft(using: localizer),
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
            title: Self.localizedMoveRight(using: localizer),
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
            title: itemKind == .workspaceTab
                ? Self.localizedCloseTabTitle(using: localizer)
                : Self.localizedClosePanelTitle(using: localizer),
            action: #selector(closeTabClicked(_:)),
            keyEquivalent: ""
        )
        closeItem.target = self
        closeItem.tag = index
        closeItem.isEnabled = canClose
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

    @objc private func handleRenameTab(_ sender: NSMenuItem) {
        guard let container = tabStack.arrangedSubviews.compactMap({ $0 as? DraggableTabContainer })
            .first(where: { $0.tabIndex == sender.tag }) else { return }
        container.startEditing()
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
        if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil) {
            btn.image = img.withSymbolConfiguration(.init(pointSize: 8, weight: .medium))
        }
        btn.contentTintColor = CocxyColors.overlay0
        btn.tag = index
        btn.target = self
        btn.action = #selector(closeTabClicked(_:))
        btn.translatesAutoresizingMaskIntoConstraints = false
        let label = itemKind == .workspaceTab
            ? Self.localizedCloseTabControl(using: localizer)
            : Self.localizedClosePanelControl(using: localizer)
        btn.setAccessibilityLabel(label)
        btn.setAccessibilityIdentifier("horizontalTab.close")
        btn.toolTip = label
        return btn
    }

    static func localizedAddPanel(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.addPanel", fallback: "Add Panel")
    }

    static func localizedAddPanelLimit(maxPaneCount: Int?, using localizer: AppLocalizer) -> String {
        let format = localizer.string(
            "horizontalTab.addPanel.maxReached",
            fallback: "Maximum of %d panes reached"
        )
        return String(format: format, maxPaneCount ?? 4)
    }

    static func localizedAddPanelSpaceLimit(using localizer: AppLocalizer) -> String {
        localizer.string(
            "horizontalTab.addPanel.notEnoughRoom",
            fallback: "Not enough room for another pane"
        )
    }

    static func localizedThemeToggleAccessibility(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.themeToggle.accessibility", fallback: "Toggle light or dark theme")
    }

    static func localizedSwitchToDarkTheme(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.themeToggle.dark", fallback: "Switch to dark theme")
    }

    static func localizedSwitchToLightTheme(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.themeToggle.light", fallback: "Switch to light theme")
    }

    static func localizedMoveLeft(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.context.moveLeft", fallback: "Move Left")
    }

    static func localizedMoveRight(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.context.moveRight", fallback: "Move Right")
    }

    static func localizedCloseTabTitle(using localizer: AppLocalizer) -> String {
        localizer.string("tabbar.context.close", fallback: "Close Tab")
    }

    static func localizedClosePanelTitle(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.context.closePanel", fallback: "Close Panel")
    }

    static func localizedRenameTabTitle(using localizer: AppLocalizer) -> String {
        localizer.string("tabbar.context.rename", fallback: "Rename Tab...")
    }

    static func localizedRenamePanelTitle(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.context.renamePanel", fallback: "Rename Panel...")
    }

    static func localizedCloseTabControl(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.closeTab.control", fallback: "Close tab")
    }

    static func localizedClosePanelControl(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.closePanel.control", fallback: "Close panel")
    }

    static func localizedTerminalSideBySide(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.add.terminalSideBySide", fallback: "Terminal (Side by Side)")
    }

    static func localizedTerminalTitle(using localizer: AppLocalizer) -> String {
        localizer.string("workspaceToolbar.panel.terminal.default", fallback: "Terminal")
    }

    static func localizedTerminalStacked(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.add.terminalStacked", fallback: "Terminal (Stacked)")
    }

    static func localizedBrowser(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.add.browser", fallback: "Browser")
    }

    static func localizedMarkdown(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.add.markdown", fallback: "Markdown")
    }

    static func localizedTextEditor(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.add.textEditor", fallback: "Text Editor")
    }

    static func localizedNotebook(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.add.notebook", fallback: "Notebook")
    }

    static func localizedWorkflow(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.add.workflow", fallback: "Workflow")
    }

    static func localizedSessionReplay(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.add.sessionReplay", fallback: "Session Replay")
    }

    static func localizedEditHistory(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.add.editHistory", fallback: "Edit History")
    }

    static func localizedTemplates(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.add.templates", fallback: "Templates")
    }

    static func localizedMacros(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.add.macros", fallback: "Macros")
    }

    static func localizedDBCloudHelpers(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.add.dbCloudHelpers", fallback: "DB/Cloud Helpers")
    }

    static func localizedSplitSideBySide(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.action.splitSideBySide", fallback: "Split Side by Side")
    }

    static func localizedSplitStacked(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.action.splitStacked", fallback: "Split Stacked")
    }

    static func localizedOpenBrowserHere(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.action.openBrowserHere", fallback: "Open Browser Here")
    }

    static func localizedOpenMarkdown(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.action.openMarkdown", fallback: "Open Markdown")
    }

    static func localizedOpenTextEditor(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.action.openTextEditor", fallback: "Open Text Editor")
    }

    static func localizedOpenNotebook(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.action.openNotebook", fallback: "Open Notebook")
    }

    static func localizedOpenWorkflow(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.action.openWorkflow", fallback: "Open Workflow")
    }

    static func localizedOpenSessionReplay(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.action.openSessionReplay", fallback: "Open Session Replay")
    }

    static func localizedOpenEditHistory(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.action.openEditHistory", fallback: "Open Edit History")
    }

    static func localizedOpenTemplates(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.action.openTemplates", fallback: "Open Templates")
    }

    static func localizedOpenMacros(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.action.openMacros", fallback: "Open Macros")
    }

    static func localizedOpenDBCloudHelpers(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.action.openDBCloudHelpers", fallback: "Open DB/Cloud Helpers")
    }

    static func localizedBack(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.action.back", fallback: "Back")
    }

    static func localizedForward(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.action.forward", fallback: "Forward")
    }

    static func localizedReload(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.action.reload", fallback: "Reload")
    }

    static func localizedCloseFocusedPane(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.action.closeFocusedPane", fallback: "Close Focused Pane")
    }

    static func localizedTabRenamePlaceholder(using localizer: AppLocalizer) -> String {
        localizer.string("tabbar.tab.renamePlaceholder", fallback: "Tab name")
    }

    static func localizedPanelRenamePlaceholder(using localizer: AppLocalizer) -> String {
        localizer.string("horizontalTab.rename.panelPlaceholder", fallback: "Panel name")
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
            title: Self.localizedTerminalSideBySide(using: localizer),
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
            title: Self.localizedTerminalStacked(using: localizer),
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

        let browserItem = NSMenuItem(
            title: Self.localizedBrowser(using: localizer),
            action: #selector(addBrowser),
            keyEquivalent: ""
        )
        browserItem.target = self
        if let img = NSImage(systemSymbolName: "globe", accessibilityDescription: nil) {
            browserItem.image = img
        }
        menu.addItem(browserItem)

        let markdownItem = NSMenuItem(title: Self.localizedMarkdown(using: localizer), action: #selector(addMarkdown), keyEquivalent: "")
        markdownItem.target = self
        if let img = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil) {
            markdownItem.image = img
        }
        menu.addItem(markdownItem)

        let editorItem = NSMenuItem(title: Self.localizedTextEditor(using: localizer), action: #selector(addEditor), keyEquivalent: "")
        editorItem.target = self
        if let img = NSImage(systemSymbolName: "doc.plaintext", accessibilityDescription: nil) {
            editorItem.image = img
        }
        menu.addItem(editorItem)

        let notebookItem = NSMenuItem(title: Self.localizedNotebook(using: localizer), action: #selector(addNotebook), keyEquivalent: "")
        notebookItem.target = self
        if let img = NSImage(systemSymbolName: "book", accessibilityDescription: nil) {
            notebookItem.image = img
        }
        menu.addItem(notebookItem)

        let workflowItem = NSMenuItem(title: Self.localizedWorkflow(using: localizer), action: #selector(addWorkflow), keyEquivalent: "")
        workflowItem.target = self
        if let img = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil) {
            workflowItem.image = img
        }
        menu.addItem(workflowItem)

        let replayItem = NSMenuItem(title: Self.localizedSessionReplay(using: localizer), action: #selector(addSessionReplay), keyEquivalent: "")
        replayItem.target = self
        if let img = NSImage(systemSymbolName: "record.circle", accessibilityDescription: nil) {
            replayItem.image = img
        }
        menu.addItem(replayItem)

        let historyItem = NSMenuItem(title: Self.localizedEditHistory(using: localizer), action: #selector(addAIEditHistory), keyEquivalent: "")
        historyItem.target = self
        if let img = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil) {
            historyItem.image = img
        }
        menu.addItem(historyItem)

        let templatesItem = NSMenuItem(title: Self.localizedTemplates(using: localizer), action: #selector(addTemplates), keyEquivalent: "")
        templatesItem.target = self
        if let img = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil) {
            templatesItem.image = img
        }
        menu.addItem(templatesItem)

        let macrosItem = NSMenuItem(title: Self.localizedMacros(using: localizer), action: #selector(addMacros), keyEquivalent: "")
        macrosItem.target = self
        if let img = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil) {
            macrosItem.image = img
        }
        menu.addItem(macrosItem)

        let dbCloudItem = NSMenuItem(title: Self.localizedDBCloudHelpers(using: localizer), action: #selector(addDBCloud), keyEquivalent: "")
        dbCloudItem.target = self
        if let img = NSImage(systemSymbolName: "externaldrive.connected.to.line.below", accessibilityDescription: nil) {
            dbCloudItem.image = img
        }
        menu.addItem(dbCloudItem)

        let point = NSPoint(x: button.bounds.minX, y: button.bounds.maxY + 4)
        menu.popUp(positioning: nil, at: point, in: button)
    }

    @objc private func addTerminal() { onAddTab?() }
    @objc private func addStackedTerminal() { onAddStackedTerminal?() }
    @objc private func addBrowser() { onAddBrowser?() }
    @objc private func addMarkdown() { onAddMarkdown?() }
    @objc private func addEditor() { onAddEditor?() }
    @objc private func addNotebook() { onAddNotebook?() }
    @objc private func addWorkflow() { onAddWorkflow?() }
    @objc private func addSessionReplay() { onAddSessionReplay?() }
    @objc private func addAIEditHistory() { onAddAIEditHistory?() }
    @objc private func addTemplates() { onAddTemplates?() }
    @objc private func addMacros() { onAddMacros?() }
    @objc private func addDBCloud() { onAddDBCloud?() }

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
    ///   - canAddPane: Whether split/open/add actions can create another pane.
    ///   - maxPaneCount: Maximum pane count for disabled-state copy, if known.
    func updateActionIcons(
        panelType: PanelType,
        canClose: Bool,
        canAddPane: Bool = true,
        maxPaneCount: Int? = nil,
        paneCreationLimitMessage: String? = nil
    ) {
        self.canAddPane = canAddPane
        maxPaneCountForAddPaneLimit = maxPaneCount
        self.paneCreationLimitMessage = paneCreationLimitMessage
        applyLocalizedChrome()
        lastActionIconState = (panelType, canClose, canAddPane, maxPaneCount, paneCreationLimitMessage)
        actionStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Split actions are available for all panel types.
        let createPaneTooltip = canAddPane
            ? nil
            : paneCreationLimitMessage
                ?? Self.localizedAddPanelLimit(maxPaneCount: maxPaneCount, using: localizer)
        actionStack.addArrangedSubview(
            createActionButton(
                icon: "rectangle.split.2x1",
                tooltip: Self.localizedSplitSideBySide(using: localizer),
                accessibilityID: "action:splitSideBySide",
                action: #selector(handleSplitSideBySide),
                isEnabled: canAddPane,
                disabledTooltip: createPaneTooltip
            )
        )
        actionStack.addArrangedSubview(
            createActionButton(
                icon: "rectangle.split.1x2",
                tooltip: Self.localizedSplitStacked(using: localizer),
                accessibilityID: "action:splitStacked",
                action: #selector(handleSplitStacked),
                isEnabled: canAddPane,
                disabledTooltip: createPaneTooltip
            )
        )

        switch panelType {
        case .terminal:
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "globe",
                    tooltip: Self.localizedOpenBrowserHere(using: localizer),
                    accessibilityID: "action:openBrowser",
                    action: #selector(handleOpenBrowser),
                    isEnabled: canAddPane,
                    disabledTooltip: createPaneTooltip
                )
            )
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "doc.text",
                    tooltip: Self.localizedOpenMarkdown(using: localizer),
                    accessibilityID: "action:openMarkdown",
                    action: #selector(handleOpenMarkdown),
                    isEnabled: canAddPane,
                    disabledTooltip: createPaneTooltip
                )
            )
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "doc.plaintext",
                    tooltip: Self.localizedOpenTextEditor(using: localizer),
                    accessibilityID: "action:openEditor",
                    action: #selector(handleOpenEditor),
                    isEnabled: canAddPane,
                    disabledTooltip: createPaneTooltip
                )
            )
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "book",
                    tooltip: Self.localizedOpenNotebook(using: localizer),
                    accessibilityID: "action:openNotebook",
                    action: #selector(handleOpenNotebook),
                    isEnabled: canAddPane,
                    disabledTooltip: createPaneTooltip
                )
            )
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "arrow.triangle.branch",
                    tooltip: Self.localizedOpenWorkflow(using: localizer),
                    accessibilityID: "action:openWorkflow",
                    action: #selector(handleOpenWorkflow),
                    isEnabled: canAddPane,
                    disabledTooltip: createPaneTooltip
                )
            )
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "record.circle",
                    tooltip: Self.localizedOpenSessionReplay(using: localizer),
                    accessibilityID: "action:openSessionReplay",
                    action: #selector(handleOpenSessionReplay),
                    isEnabled: canAddPane,
                    disabledTooltip: createPaneTooltip
                )
            )
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "clock.arrow.circlepath",
                    tooltip: Self.localizedOpenEditHistory(using: localizer),
                    accessibilityID: "action:openAIEditHistory",
                    action: #selector(handleOpenAIEditHistory),
                    isEnabled: canAddPane,
                    disabledTooltip: createPaneTooltip
                )
            )
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "square.grid.2x2",
                    tooltip: Self.localizedOpenTemplates(using: localizer),
                    accessibilityID: "action:openTemplates",
                    action: #selector(handleOpenTemplates),
                    isEnabled: canAddPane,
                    disabledTooltip: createPaneTooltip
                )
            )
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "keyboard",
                    tooltip: Self.localizedOpenMacros(using: localizer),
                    accessibilityID: "action:openMacros",
                    action: #selector(handleOpenMacros),
                    isEnabled: canAddPane,
                    disabledTooltip: createPaneTooltip
                )
            )
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "externaldrive.connected.to.line.below",
                    tooltip: Self.localizedOpenDBCloudHelpers(using: localizer),
                    accessibilityID: "action:openDBCloud",
                    action: #selector(handleOpenDBCloud),
                    isEnabled: canAddPane,
                    disabledTooltip: createPaneTooltip
                )
            )
        case .browser:
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "chevron.left",
                    tooltip: Self.localizedBack(using: localizer),
                    accessibilityID: "action:goBack",
                    action: #selector(handleGoBack)
                )
            )
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "chevron.right",
                    tooltip: Self.localizedForward(using: localizer),
                    accessibilityID: "action:goForward",
                    action: #selector(handleGoForward)
                )
            )
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "arrow.clockwise",
                    tooltip: Self.localizedReload(using: localizer),
                    accessibilityID: "action:reload",
                    action: #selector(handleReload)
                )
            )
        case .markdown, .editor, .notebook, .workflow, .sessionReplay, .aiEditHistory, .templates, .macros, .dbCloud, .subagent:
            break
        }

        if canClose {
            actionStack.addArrangedSubview(
                createActionButton(
                    icon: "rectangle.badge.xmark",
                    tooltip: Self.localizedCloseFocusedPane(using: localizer),
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
        action: Selector,
        isEnabled: Bool = true,
        disabledTooltip: String? = nil
    ) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        btn.wantsLayer = true
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            btn.image = img.withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        }
        btn.contentTintColor = CocxyColors.overlay1
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isEnabled = isEnabled
        btn.alphaValue = isEnabled ? 1.0 : 0.35
        btn.toolTip = isEnabled ? tooltip : (disabledTooltip ?? tooltip)
        btn.setAccessibilityLabel(tooltip)
        btn.setAccessibilityIdentifier(accessibilityID)
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
    @objc private func handleOpenEditor() { onOpenEditor?() }
    @objc private func handleOpenNotebook() { onOpenNotebook?() }
    @objc private func handleOpenWorkflow() { onOpenWorkflow?() }
    @objc private func handleOpenSessionReplay() { onOpenSessionReplay?() }
    @objc private func handleOpenAIEditHistory() { onOpenAIEditHistory?() }
    @objc private func handleOpenTemplates() { onOpenTemplates?() }
    @objc private func handleOpenMacros() { onOpenMacros?() }
    @objc private func handleOpenDBCloud() { onOpenDBCloud?() }
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

    /// Localizer copied from the owning strip when the container is created.
    var localizer = AppLocalizer(languagePreference: .english)

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
               Self.isCloseButton(subview) {
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

    static func isCloseButton(_ view: NSView) -> Bool {
        view.accessibilityIdentifier() == "horizontalTab.close"
            || isCloseButtonLabel(view.accessibilityLabel())
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
                       !Self.isCloseButton(btn) {
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
            placeholder: itemKind == .workspaceTab
                ? HorizontalTabStripView.localizedTabRenamePlaceholder(using: localizer)
                : HorizontalTabStripView.localizedPanelRenamePlaceholder(using: localizer),
            icon: itemKind == .workspaceTab ? "terminal.fill" : "rectangle.split.2x1",
            localizer: localizer
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
               !Self.isCloseButton(btn) {
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
