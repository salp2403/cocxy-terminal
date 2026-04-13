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
    private let outlineView = NSOutlineView()
    private var dataSource: MarkdownOutlineDataSource?
    private var delegateObject: MarkdownOutlineDelegate?

    /// Invoked when a heading is clicked. The parameter is the entry's
    /// source line (0-based, body-relative) plus its plain title so the
    /// host can decide whether to scroll source or preview.
    var onSelect: ((MarkdownOutlineEntry) -> Void)?

    /// Current document's outline. Setting triggers a reload.
    var outline: MarkdownOutline = .empty {
        didSet { reload() }
    }

    // MARK: - Init

    init() {
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
        column.title = "Outline"
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.backgroundColor = .clear
        outlineView.rowSizeStyle = .small
        outlineView.indentationPerLevel = 12
        outlineView.allowsEmptySelection = true
        outlineView.target = self
        outlineView.action = #selector(rowClicked)

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

    // MARK: - Reload

    private func reload() {
        dataSource?.nodes = outline.tree()
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
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
