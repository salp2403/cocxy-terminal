// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownOutlineView.swift - Sidebar outline of headings in a MarkdownDocument.

import AppKit
import CocxyMarkdownLib

// MARK: - Outline View

/// NSOutlineView-based sidebar that displays the heading tree of a
/// `MarkdownDocument`. Clicking a heading invokes `onSelect(entry)` so the
/// content panel can scroll source and preview to the matching location.
@MainActor
final class MarkdownOutlineView: NSView {

    // MARK: - Properties

    private let scrollView = NSScrollView()
    private let outlineView = HoverTrackingOutlineView()
    private var dataSource: MarkdownOutlineDataSource?
    private var delegateObject: MarkdownOutlineDelegate?
    private var localizer: AppLocalizer

    /// Invoked when a heading is clicked. The parameter is the entry's
    /// source line (0-based, body-relative) plus its plain title so the
    /// host can decide whether to scroll source or preview.
    var onSelect: ((MarkdownOutlineEntry) -> Void)?

    /// Invoked when the pointer moves over a heading row. Nil clears the
    /// preview highlight when the pointer leaves the outline.
    var onHover: ((MarkdownOutlineEntry?) -> Void)?

    /// Current document's outline. Setting triggers a reload.
    var outline: MarkdownOutline = .empty {
        didSet { reload() }
    }

    // MARK: - Init

    init(localizer: AppLocalizer = AppLocalizer(languagePreference: .system)) {
        self.localizer = localizer
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MarkdownOutlineView does not support NSCoding")
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = CocxyColors.mantle.cgColor

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.width = 180
        column.title = Self.localizedTitle(using: localizer)
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.backgroundColor = .clear
        outlineView.rowSizeStyle = .small
        outlineView.indentationPerLevel = 12
        outlineView.allowsEmptySelection = true
        outlineView.target = self
        outlineView.action = #selector(rowClicked)
        outlineView.onHoveredRowChanged = { [weak self] row in
            guard let self else { return }
            guard let row,
                  row >= 0,
                  let node = self.outlineView.item(atRow: row) as? MarkdownOutlineNode
            else {
                self.onHover?(nil)
                return
            }
            self.onHover?(node.entry)
        }

        let ds = MarkdownOutlineDataSource(nodes: [])
        outlineView.dataSource = ds
        dataSource = ds

        let del = MarkdownOutlineDelegate()
        outlineView.delegate = del
        delegateObject = del

        scrollView.documentView = outlineView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        outlineView.tableColumns.first?.title = Self.localizedTitle(using: localizer)
    }

    static func localizedTitle(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.outline.title", fallback: "Outline")
    }

    // MARK: - Reload

    private func reload() {
        dataSource?.nodes = outline.tree()
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
        onHover?(nil)
    }

    // MARK: - Actions

    @objc private func rowClicked() {
        let row = outlineView.clickedRow
        guard row >= 0 else { return }
        if let node = outlineView.item(atRow: row) as? MarkdownOutlineNode {
            onSelect?(node.entry)
        }
    }
}

// MARK: - Hover Tracking

@MainActor
private final class HoverTrackingOutlineView: NSOutlineView {
    var onHoveredRowChanged: ((Int?) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private var hoveredRow: Int?

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        super.updateTrackingAreas()

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        updateHoveredRow(row >= 0 ? row : nil)
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        updateHoveredRow(nil)
        super.mouseExited(with: event)
    }

    private func updateHoveredRow(_ row: Int?) {
        guard hoveredRow != row else { return }
        hoveredRow = row
        onHoveredRowChanged?(row)
    }
}

// MARK: - Data Source

@MainActor
private final class MarkdownOutlineDataSource: NSObject, NSOutlineViewDataSource {

    var nodes: [MarkdownOutlineNode]

    init(nodes: [MarkdownOutlineNode]) {
        self.nodes = nodes
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let node = item as? MarkdownOutlineNode {
            return node.children.count
        }
        return nodes.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? MarkdownOutlineNode {
            return node.children[index]
        }
        return nodes[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let node = item as? MarkdownOutlineNode {
            return !node.children.isEmpty
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        (item as? MarkdownOutlineNode)?.entry.title
    }
}

// MARK: - Delegate

@MainActor
private final class MarkdownOutlineDelegate: NSObject, NSOutlineViewDelegate {

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("MarkdownOutlineCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
            ?? {
                let newCell = NSTableCellView()
                newCell.identifier = identifier
                let label = NSTextField(labelWithString: "")
                label.translatesAutoresizingMaskIntoConstraints = false
                label.font = .systemFont(ofSize: 12, weight: .regular)
                label.textColor = CocxyColors.subtext1
                label.lineBreakMode = .byTruncatingTail
                newCell.addSubview(label)
                newCell.textField = label
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: newCell.leadingAnchor, constant: 4),
                    label.trailingAnchor.constraint(equalTo: newCell.trailingAnchor, constant: -4),
                    label.centerYAnchor.constraint(equalTo: newCell.centerYAnchor)
                ])
                return newCell
            }()

        if let node = item as? MarkdownOutlineNode {
            cell.textField?.stringValue = node.entry.title
            cell.textField?.textColor = node.entry.level == 1
                ? CocxyColors.text
                : CocxyColors.subtext1
            cell.textField?.font = node.entry.level == 1
                ? .systemFont(ofSize: 12, weight: .semibold)
                : .systemFont(ofSize: 12, weight: .regular)
        }

        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        22
    }
}
