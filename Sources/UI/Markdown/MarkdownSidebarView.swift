// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownSidebarView.swift - Tabbed sidebar with Files and Outline panels.

import AppKit

// MARK: - Sidebar Tab

/// Tabs available in the markdown sidebar.
enum MarkdownSidebarTab: String, CaseIterable {
    case files = "Files"
    case outline = "Outline"
    case search = "Search"

    var iconName: String {
        switch self {
        case .files: return "folder"
        case .outline: return "list.bullet"
        case .search: return "magnifyingglass"
        }
    }
}

// MARK: - Sidebar View

/// Tabbed sidebar for the markdown panel.
///
/// Contains two panels selectable via tab buttons at the top:
/// - **Files**: Workspace file explorer showing .md files
/// - **Outline**: Document heading tree (delegates to `MarkdownOutlineView`)
///
/// The sidebar width is managed by the parent `MarkdownContentView` via its
/// width constraint. This view only handles the tab switching and content display.
@MainActor
final class MarkdownSidebarView: NSView {

    // MARK: - Properties

    private let tabBar = NSView()
    private var tabButtons: [NSButton] = []
    private let contentContainer = NSView()

    let fileExplorer = MarkdownFileExplorerView()
    let outlineView = MarkdownOutlineView()
    let searchView = MarkdownSearchView()

    /// Current active tab.
    private(set) var activeTab: MarkdownSidebarTab = .outline {
        didSet {
            if oldValue != activeTab {
                applyActiveTab()
            }
        }
    }

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        setupUI()
        applyActiveTab()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MarkdownSidebarView does not support NSCoding")
    }

    // MARK: - Public API

    /// Switches to the specified tab.
    func selectTab(_ tab: MarkdownSidebarTab) {
        activeTab = tab
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = CocxyColors.mantle.cgColor

        // Tab bar at the top
        tabBar.wantsLayer = true
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabBar)

        // Create tab buttons
        for (index, tab) in MarkdownSidebarTab.allCases.enumerated() {
            let button = makeTabButton(for: tab, tag: index)
            tabButtons.append(button)
            tabBar.addSubview(button)
        }

        // Content container
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)

        // Separator between tab bar and content
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = CocxyColors.surface0.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 28),

            separator.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            contentContainer.topAnchor.constraint(equalTo: separator.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Layout tab buttons evenly — works for any number of tabs
        guard let first = tabButtons.first, let last = tabButtons.last else { return }

        first.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor, constant: 4).isActive = true
        last.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: -4).isActive = true

        for button in tabButtons {
            button.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor).isActive = true
        }

        // Chain each button to its predecessor and enforce equal widths
        for i in 1..<tabButtons.count {
            tabButtons[i].leadingAnchor.constraint(equalTo: tabButtons[i - 1].trailingAnchor, constant: 2).isActive = true
            tabButtons[i].widthAnchor.constraint(equalTo: first.widthAnchor).isActive = true
        }
    }

    private func makeTabButton(for tab: MarkdownSidebarTab, tag: Int) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.setButtonType(.toggle)
        button.title = tab.rawValue
        button.font = .systemFont(ofSize: 10, weight: .medium)
        button.contentTintColor = CocxyColors.subtext0
        button.tag = tag
        button.target = self
        button.action = #selector(tabClicked(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // MARK: - Actions

    @objc private func tabClicked(_ sender: NSButton) {
        let tabs = MarkdownSidebarTab.allCases
        guard sender.tag >= 0, sender.tag < tabs.count else { return }
        activeTab = tabs[sender.tag]
    }

    // MARK: - Tab Switching

    private func applyActiveTab() {
        // Update button states
        for (index, button) in tabButtons.enumerated() {
            let tab = MarkdownSidebarTab.allCases[index]
            let isSelected = tab == activeTab
            button.state = isSelected ? .on : .off
            button.contentTintColor = isSelected ? CocxyColors.blue : CocxyColors.subtext0
        }

        // Switch content
        contentContainer.subviews.forEach { $0.removeFromSuperview() }

        let targetView: NSView
        switch activeTab {
        case .files:
            targetView = fileExplorer
        case .outline:
            targetView = outlineView
        case .search:
            targetView = searchView
        }

        targetView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(targetView)
        NSLayoutConstraint.activate([
            targetView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            targetView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            targetView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            targetView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }
}
