// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabBarView.swift - Vertical tab bar with rich workspace info.

import AppKit
import Combine

// MARK: - Tab Bar View

/// Vertical sidebar that displays all open tabs with rich workspace context.
///
/// ## Layout
///
/// - Header with app name and notification bell.
/// - `NSScrollView` wrapping an `NSStackView` for tab items.
/// - "+" button at the bottom to create a new tab.
///
/// ## Interaction
///
/// - Click: select tab.
/// - Right-click: context menu (Close Tab, New Tab, Close Other Tabs).
/// - Hover: elevated surface effect.
///
/// ## Dimensions
///
/// - Default width: 220pt.
/// - Minimum width: 180pt.
/// - Maximum width: 350pt.
@MainActor
final class TabBarView: NSView {

    // MARK: - Constants

    static let defaultWidth: CGFloat = 240
    static let minimumWidth: CGFloat = 200
    static let maximumWidth: CGFloat = 380

    private static let tabItemHeight: CGFloat = 64
    private static let sidebarPadding: CGFloat = 8
    private static let headerHeight: CGFloat = 36

    // MARK: - Subviews

    /// Background view — supports solid or vibrancy mode.
    /// Toggle via `setSidebarTransparent(_:)`.
    private let backgroundView: NSView = {
        let effectView = NSVisualEffectView()
        effectView.material = .sidebar
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        return effectView
    }()

    /// Solid overlay on top of the vibrancy view, hidden when transparent mode is on.
    private let solidOverlay: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = CocxyColors.mantle.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true // Transparent by default — user can disable in Settings.
        return view
    }()

    /// Header: app name + notification badge.
    ///
    /// Uses a custom subclass that returns `false` from `mouseDownCanMoveWindow`
    /// so that clicks on header buttons are not intercepted by the window's
    /// `isMovableByWindowBackground` drag behavior.
    private let headerView: NSView = {
        let view = NonDraggableView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let headerTitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "WORKSPACES")
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = CocxyColors.overlay1
        let attributes: [NSAttributedString.Key: Any] = [
            .kern: 1.5,
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: CocxyColors.overlay1,
        ]
        label.attributedStringValue = NSAttributedString(string: "WORKSPACES", attributes: attributes)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let notificationBellImage: ClickableImageView = {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Notifications")?
            .withSymbolConfiguration(config)
        let imageView = ClickableImageView(image: image ?? NSImage())
        imageView.contentTintColor = CocxyColors.overlay1
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let notificationCountLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        label.textColor = CocxyColors.crust
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.wantsLayer = true
        label.layer?.cornerRadius = 7
        label.layer?.backgroundColor = CocxyColors.blue.cgColor
        return label
    }()

    /// Command palette button in the header — shows magnifying glass icon.
    private let commandPaletteButton: NSButton = {
        let button = NSButton()
        button.bezelStyle = .inline
        button.isBordered = false
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        if let image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Command Palette") {
            button.image = image.withSymbolConfiguration(config)
        }
        button.contentTintColor = CocxyColors.overlay1
        button.translatesAutoresizingMaskIntoConstraints = false
        button.toolTip = "Command Palette (Cmd+Shift+P)"
        button.setAccessibilityLabel("Command Palette")
        button.setAccessibilityHelp("Open the command palette (Cmd+Shift+P)")
        return button
    }()

    private let headerSeparator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = CocxyColors.surface0.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let scrollView: NSScrollView = {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    /// Flipped document view so tab items start from the top.
    private let documentView: FlippedDocumentView = {
        let view = FlippedDocumentView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let tabStackView: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let newTabButton: NSButton = {
        let button = NSButton()
        button.bezelStyle = .inline
        button.isBordered = false
        if let image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab") {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
            button.title = " New Tab"
            button.imagePosition = .imageLeading
            button.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        } else {
            button.title = "+ New Tab"
            button.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        }
        button.contentTintColor = CocxyColors.subtext0
        button.wantsLayer = true
        button.layer?.backgroundColor = CocxyColors.surface0.withAlphaComponent(0.4).cgColor
        button.layer?.cornerRadius = 6
        button.translatesAutoresizingMaskIntoConstraints = false
        button.toolTip = "New Tab (Cmd+T)"
        button.setAccessibilityLabel("New Tab")
        button.setAccessibilityHelp("Create a new terminal tab (Cmd+T)")
        return button
    }()

    // MARK: - Configuration

    /// When true, shows a confirmation alert before closing a tab.
    /// Set by the window controller from `configService.current.general.confirmCloseProcess`.
    var confirmCloseProcess: Bool = false

    /// When true, attention borders and glow effects are applied on unread tabs.
    /// Set by the window controller from `configService.current.notifications.flashTab`.
    var flashTabEnabled: Bool = true

    /// When true, unread notification count badges are shown on inactive tabs.
    /// Set by the window controller from `configService.current.notifications.badgeOnTab`.
    var badgeOnTabEnabled: Bool = true

    // MARK: - Callbacks

    /// Invoked when the command palette button is clicked.
    var onCommandPalette: (() -> Void)?
    var onNotificationPanel: (() -> Void)?

    // MARK: - State

    private let viewModel: TabBarViewModel
    private var cancellables = Set<AnyCancellable>()
    private var tabItemViews: [TabID: TabItemView] = [:]

    // MARK: - Initialization

    init(viewModel: TabBarViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        setupAccessibility()
        setupLayout()
        setupActions()
        subscribeToChanges()
        rebuildTabItems()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TabBarView does not support NSCoding")
    }

    // MARK: - Accessibility

    private func setupAccessibility() {
        setAccessibilityRole(.list)
        setAccessibilityLabel("Terminal tabs")
    }

    // MARK: - Layout

    private func setupLayout() {
        addSubview(backgroundView)
        addSubview(solidOverlay)

        // Header (added on top of both background layers)
        addSubview(headerView)
        headerView.addSubview(headerTitleLabel)
        headerView.addSubview(commandPaletteButton)
        // Make bell clickeable for notification panel toggle.
        let bellClick = NSClickGestureRecognizer(target: self, action: #selector(bellClicked))
        notificationBellImage.addGestureRecognizer(bellClick)
        headerView.addSubview(notificationBellImage)
        headerView.addSubview(notificationCountLabel)
        addSubview(headerSeparator)

        // Scroll area
        addSubview(scrollView)
        addSubview(newTabButton)

        // Use flipped clip view so content starts from the top.
        let clipView = FlippedClipView()
        clipView.drawsBackground = false
        documentView.addSubview(tabStackView)
        clipView.documentView = documentView
        scrollView.contentView = clipView

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            solidOverlay.topAnchor.constraint(equalTo: topAnchor),
            solidOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            solidOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            solidOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Header
            headerView.topAnchor.constraint(equalTo: topAnchor, constant: 44),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            headerView.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            headerTitleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            headerTitleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            commandPaletteButton.trailingAnchor.constraint(equalTo: notificationBellImage.leadingAnchor, constant: -10),
            commandPaletteButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            commandPaletteButton.widthAnchor.constraint(equalToConstant: 20),
            commandPaletteButton.heightAnchor.constraint(equalToConstant: 20),

            notificationBellImage.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            notificationBellImage.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            notificationCountLabel.centerXAnchor.constraint(equalTo: notificationBellImage.trailingAnchor, constant: 2),
            notificationCountLabel.centerYAnchor.constraint(equalTo: notificationBellImage.topAnchor, constant: 2),
            notificationCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 14),
            notificationCountLabel.heightAnchor.constraint(equalToConstant: 14),

            headerSeparator.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 4),
            headerSeparator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            headerSeparator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            headerSeparator.heightAnchor.constraint(equalToConstant: 1),

            // Scroll view
            scrollView.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: newTabButton.topAnchor, constant: -4),

            // Tab stack inside the flipped document view.
            tabStackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            tabStackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: Self.sidebarPadding),
            tabStackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -Self.sidebarPadding),
            tabStackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),

            // Document view fills the clip view width.
            documentView.widthAnchor.constraint(equalTo: clipView.widthAnchor),

            // New tab button
            newTabButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            newTabButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            newTabButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    // MARK: - Sidebar Transparency

    /// Toggles the sidebar between transparent (vibrancy) and solid background.
    ///
    /// - Parameter transparent: `true` for macOS vibrancy, `false` for solid dark.
    func setSidebarTransparent(_ transparent: Bool) {
        solidOverlay.isHidden = transparent
    }

    /// Whether the sidebar is currently in transparent mode.
    var isSidebarTransparent: Bool {
        solidOverlay.isHidden
    }

    // MARK: - Notification Badge

    /// Updates the notification bell badge count.
    func updateNotificationCount(_ count: Int) {
        if count > 0 {
            notificationCountLabel.isHidden = false
            notificationCountLabel.stringValue = count > 9 ? "9+" : "\(count)"
            notificationBellImage.contentTintColor = CocxyColors.blue
        } else {
            notificationCountLabel.isHidden = true
            notificationBellImage.contentTintColor = CocxyColors.overlay1
        }
    }

    // MARK: - Actions

    private func setupActions() {
        newTabButton.target = self
        newTabButton.action = #selector(handleNewTabButton)
        commandPaletteButton.target = self
        commandPaletteButton.action = #selector(handleCommandPaletteButton)

    }

    @objc private func handleNewTabButton() {
        viewModel.addNewTab()
    }

    @objc private func handleCommandPaletteButton() {
        onCommandPalette?()
    }

    @objc private func bellClicked() {
        onNotificationPanel?()
    }

    // MARK: - Context Menu

    func buildContextMenu(for tabID: TabID) -> NSMenu {
        let menu = NSMenu()

        let isPinned = viewModel.tabItems.first(where: { $0.id == tabID })?.isPinned ?? false

        // Pin / Unpin toggle.
        let pinTitle = isPinned ? "Unpin Tab" : "Pin Tab"
        let pinItem = NSMenuItem(
            title: pinTitle,
            action: #selector(handleTogglePin(_:)),
            keyEquivalent: ""
        )
        pinItem.target = self
        pinItem.representedObject = tabID.rawValue
        if let img = NSImage(systemSymbolName: isPinned ? "pin.slash" : "pin", accessibilityDescription: pinTitle) {
            pinItem.image = img
        }
        menu.addItem(pinItem)

        menu.addItem(NSMenuItem.separator())

        let closeItem = NSMenuItem(
            title: "Close Tab",
            action: #selector(handleCloseTab(_:)),
            keyEquivalent: "w"
        )
        closeItem.target = self
        closeItem.representedObject = tabID.rawValue
        // Pinned tabs cannot be closed.
        closeItem.isEnabled = !isPinned
        menu.addItem(closeItem)

        let newTabItem = NSMenuItem(
            title: "New Tab",
            action: #selector(handleNewTabButton),
            keyEquivalent: "t"
        )
        newTabItem.target = self
        menu.addItem(newTabItem)

        menu.addItem(NSMenuItem.separator())

        let closeOthersItem = NSMenuItem(
            title: "Close Other Tabs",
            action: #selector(handleCloseOtherTabs(_:)),
            keyEquivalent: ""
        )
        closeOthersItem.target = self
        closeOthersItem.representedObject = tabID.rawValue
        menu.addItem(closeOthersItem)

        menu.addItem(NSMenuItem.separator())

        let moveUpItem = NSMenuItem(
            title: "Move Tab Up",
            action: #selector(handleMoveTabUp(_:)),
            keyEquivalent: ""
        )
        moveUpItem.target = self
        moveUpItem.representedObject = tabID.rawValue
        menu.addItem(moveUpItem)

        let moveDownItem = NSMenuItem(
            title: "Move Tab Down",
            action: #selector(handleMoveTabDown(_:)),
            keyEquivalent: ""
        )
        moveDownItem.target = self
        moveDownItem.representedObject = tabID.rawValue
        menu.addItem(moveDownItem)

        return menu
    }

    /// Extracts the TabID from a menu item's representedObject (stored as UUID).
    private func tabIDFromMenuItem(_ sender: NSMenuItem) -> TabID? {
        guard let uuid = sender.representedObject as? UUID else { return nil }
        return TabID(rawValue: uuid)
    }

    @objc private func handleTogglePin(_ sender: NSMenuItem) {
        guard let tabID = tabIDFromMenuItem(sender) else { return }
        viewModel.togglePin(id: tabID)
    }

    @objc private func handleCloseTab(_ sender: NSMenuItem) {
        guard let tabID = tabIDFromMenuItem(sender) else { return }
        viewModel.closeTab(id: tabID)
    }

    @objc private func handleCloseOtherTabs(_ sender: NSMenuItem) {
        guard let tabID = tabIDFromMenuItem(sender) else { return }
        viewModel.closeOtherTabs(except: tabID)
    }

    @objc private func handleMoveTabUp(_ sender: NSMenuItem) {
        guard let tabID = tabIDFromMenuItem(sender) else { return }
        let currentIndex = viewModel.tabItems.firstIndex { $0.id == tabID }
        guard let index = currentIndex, index > 0 else { return }
        viewModel.moveTab(from: index, to: index - 1)
    }

    @objc private func handleMoveTabDown(_ sender: NSMenuItem) {
        guard let tabID = tabIDFromMenuItem(sender) else { return }
        let currentIndex = viewModel.tabItems.firstIndex { $0.id == tabID }
        guard let index = currentIndex, index < viewModel.tabItems.count - 1 else { return }
        viewModel.moveTab(from: index, to: index + 1)
    }

    // MARK: - Tab Item Management

    private func subscribeToChanges() {
        viewModel.$tabItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildTabItems()
            }
            .store(in: &cancellables)
    }

    private func rebuildTabItems() {
        let newItems = viewModel.tabItems
        let newIDs = Set(newItems.map(\.id))
        let existingIDs = Set(tabItemViews.keys)

        // Remove views for tabs that no longer exist.
        for id in existingIDs where !newIDs.contains(id) {
            if let view = tabItemViews.removeValue(forKey: id) {
                tabStackView.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        }

        // Update existing views and create new ones.
        for (index, item) in newItems.enumerated() {
            if let existingView = tabItemViews[item.id] {
                existingView.update(with: item)
                existingView.shouldConfirmClose = confirmCloseProcess
                existingView.flashTabEnabled = flashTabEnabled
                existingView.badgeOnTabEnabled = badgeOnTabEnabled

                let currentIndex = tabStackView.arrangedSubviews.firstIndex(of: existingView)
                if currentIndex != index {
                    tabStackView.removeArrangedSubview(existingView)
                    tabStackView.insertArrangedSubview(existingView, at: index)
                }
            } else {
                let itemView = TabItemView(displayItem: item)
                itemView.shouldConfirmClose = confirmCloseProcess
                itemView.flashTabEnabled = flashTabEnabled
                itemView.badgeOnTabEnabled = badgeOnTabEnabled
                itemView.onSelect = { [weak self] in
                    self?.viewModel.selectTab(id: item.id)
                }
                itemView.onClose = { [weak self] in
                    self?.viewModel.closeTab(id: item.id)
                }
                itemView.onContextMenu = { [weak self] in
                    guard let self = self else { return nil }
                    return self.buildContextMenu(for: item.id)
                }
                itemView.onRename = { [weak self] tabID, newTitle in
                    self?.viewModel.renameTab(id: tabID, newTitle: newTitle)
                }

                tabStackView.insertArrangedSubview(itemView, at: index)
                tabItemViews[item.id] = itemView

                itemView.translatesAutoresizingMaskIntoConstraints = false
                itemView.heightAnchor.constraint(
                    equalToConstant: Self.tabItemHeight
                ).isActive = true
                itemView.widthAnchor.constraint(
                    equalTo: tabStackView.widthAnchor
                ).isActive = true
            }
        }

        // Update notification badge
        let notifCount = newItems.filter {
            !$0.isActive && ($0.agentState == .waitingInput || $0.hasUnreadNotification)
        }.count
        updateNotificationCount(notifCount)
    }
}

// MARK: - Non-Draggable View

/// A plain NSView that opts out of `isMovableByWindowBackground`.
///
/// When a window has `isMovableByWindowBackground = true`, plain NSView
/// containers report `mouseDownCanMoveWindow = true` by default, causing
/// clicks on their child controls to start a window drag instead.
/// This subclass overrides that behavior so that buttons and gesture
/// recognizers inside the view work correctly.
@MainActor
final class NonDraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

// MARK: - Clickable Image View

/// An NSImageView that opts out of `isMovableByWindowBackground` and
/// accepts mouse events. Standard NSImageView is non-interactive
/// and gets treated as window-draggable background.
@MainActor
final class ClickableImageView: NSImageView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

