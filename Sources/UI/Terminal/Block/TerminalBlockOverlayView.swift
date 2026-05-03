// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalBlockOverlayView.swift - Command block overlay for CocxyCore terminal surfaces.

import AppKit

struct TerminalBlockOverlayLayoutEntry: Equatable {
    let block: TerminalCommandBlock
    let frame: NSRect
    let railFrame: NSRect
}

enum TerminalBlockOverlayLayout {
    static let horizontalInset: CGFloat = 8
    static let headerHeight: CGFloat = 26

    static func entries(
        blocks: [TerminalCommandBlock],
        visibleStartRow: UInt32,
        visibleRowCount: UInt16,
        cellHeight: CGFloat,
        padding: CGPoint,
        width: CGFloat
    ) -> [TerminalBlockOverlayLayoutEntry] {
        guard visibleRowCount > 0, cellHeight > 0, width > 0 else { return [] }

        let visibleEndExclusive = visibleStartRow + UInt32(visibleRowCount)
        let x = padding.x + horizontalInset
        let resolvedWidth = max(0, width - x * 2)
        let railX = max(0, padding.x + 2)

        return blocks.compactMap { block in
            guard block.endRow >= visibleStartRow,
                  block.startRow < visibleEndExclusive else {
                return nil
            }

            let clampedStart = max(block.startRow, visibleStartRow)
            let blockEndExclusive = block.endRow == UInt32.max ? UInt32.max : block.endRow + 1
            let clampedEndExclusive = min(blockEndExclusive, visibleEndExclusive)
            let visibleRow = CGFloat(clampedStart - visibleStartRow)
            let y = padding.y + visibleRow * cellHeight
            let frame = NSRect(
                x: x,
                y: y,
                width: resolvedWidth,
                height: headerHeight
            )
            let railFrame = NSRect(
                x: railX,
                y: y,
                width: 3,
                height: max(headerHeight, CGFloat(clampedEndExclusive - clampedStart) * cellHeight)
            )
            return TerminalBlockOverlayLayoutEntry(block: block, frame: frame, railFrame: railFrame)
        }
    }
}

@MainActor
final class TerminalBlockOverlayView: NSView {
    var onCopyBlockOutput: ((TerminalCommandBlock) -> Void)?
    var onRerunBlock: ((TerminalCommandBlock) -> Void)?
    var onShareBlock: ((TerminalCommandBlock, NSView) -> Void)?
    var onToggleBookmark: ((TerminalCommandBlock) -> Void)?

    private var blocks: [TerminalCommandBlock] = []
    private var visibleStartRow: UInt32 = 0
    private var visibleRowCount: UInt16 = 0
    private var cellHeight: CGFloat = 0
    private var contentPadding: CGPoint = .zero

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TerminalBlockOverlayView does not support NSCoding")
    }

    func update(
        blocks: [TerminalCommandBlock],
        visibleStartRow: UInt32,
        visibleRowCount: UInt16,
        cellHeight: CGFloat,
        padding: CGPoint
    ) {
        self.blocks = blocks
        self.visibleStartRow = visibleStartRow
        self.visibleRowCount = visibleRowCount
        self.cellHeight = cellHeight
        self.contentPadding = padding
        rebuildRows()
    }

    func clear() {
        blocks = []
        subviews.forEach { $0.removeFromSuperview() }
    }

    override func layout() {
        super.layout()
        rebuildRows()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0 else { return nil }
        return buttonHit(at: point, in: self)
    }

    private func rebuildRows() {
        subviews.forEach { $0.removeFromSuperview() }

        let entries = TerminalBlockOverlayLayout.entries(
            blocks: blocks,
            visibleStartRow: visibleStartRow,
            visibleRowCount: visibleRowCount,
            cellHeight: cellHeight,
            padding: contentPadding,
            width: bounds.width
        )

        isHidden = entries.isEmpty

        for entry in entries {
            let rail = TerminalBlockRailView(block: entry.block)
            rail.frame = entry.railFrame
            rail.autoresizingMask = [.height]
            addSubview(rail)

            let row = TerminalBlockHeaderView(block: entry.block)
            row.frame = entry.frame
            row.autoresizingMask = [.width]
            row.onCopy = { [weak self] block in
                self?.onCopyBlockOutput?(block)
            }
            row.onRerun = { [weak self] block in
                self?.onRerunBlock?(block)
            }
            row.onShare = { [weak self] block, sourceView in
                self?.onShareBlock?(block, sourceView)
            }
            row.onBookmark = { [weak self] block in
                self?.onToggleBookmark?(block)
            }
            addSubview(row)
            row.layoutSubtreeIfNeeded()
        }
    }

    private func buttonHit(at pointInOverlay: NSPoint, in root: NSView) -> NSButton? {
        for subview in root.subviews.reversed() {
            let converted = subview.convert(pointInOverlay, from: self)
            if let button = subview as? NSButton,
               subview.bounds.contains(converted) {
                return button
            }
            if let nested = buttonHit(at: pointInOverlay, in: subview) {
                return nested
            }
        }
        return nil
    }
}

@MainActor
private final class TerminalBlockRailView: NSView {
    private let block: TerminalCommandBlock

    init(block: TerminalCommandBlock) {
        self.block = block
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 1.5
        layer?.backgroundColor = block.exitCode == 0
            ? NSColor.systemGreen.withAlphaComponent(0.70).cgColor
            : NSColor.systemRed.withAlphaComponent(0.70).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TerminalBlockRailView does not support NSCoding")
    }
}

@MainActor
private final class TerminalBlockHeaderView: NSView {
    var onCopy: ((TerminalCommandBlock) -> Void)?
    var onRerun: ((TerminalCommandBlock) -> Void)?
    var onShare: ((TerminalCommandBlock, NSView) -> Void)?
    var onBookmark: ((TerminalCommandBlock) -> Void)?

    private let block: TerminalCommandBlock
    private let commandLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let bookmarkButton = NSButton()
    private let shareButton = NSButton()
    private let copyButton = NSButton()
    private let rerunButton = NSButton()

    override var isFlipped: Bool { true }

    init(block: TerminalCommandBlock) {
        self.block = block
        super.init(frame: .zero)
        wantsLayer = true
        configureLayer()
        configureLabels()
        configureButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TerminalBlockHeaderView does not support NSCoding")
    }

    override func layout() {
        super.layout()

        let buttonSize = NSSize(width: 22, height: 22)
        let y = (bounds.height - buttonSize.height) / 2
        let rerunX = bounds.width - buttonSize.width - 6
        let copyX = rerunX - buttonSize.width - 4
        let shareX = copyX - buttonSize.width - 4
        let bookmarkX = shareX - buttonSize.width - 4
        rerunButton.frame = NSRect(origin: CGPoint(x: rerunX, y: y), size: buttonSize)
        copyButton.frame = NSRect(origin: CGPoint(x: copyX, y: y), size: buttonSize)
        shareButton.frame = NSRect(origin: CGPoint(x: shareX, y: y), size: buttonSize)
        bookmarkButton.frame = NSRect(origin: CGPoint(x: bookmarkX, y: y), size: buttonSize)

        let statusWidth: CGFloat = 46
        statusLabel.frame = NSRect(
            x: 8,
            y: 4,
            width: statusWidth,
            height: bounds.height - 8
        )
        commandLabel.frame = NSRect(
            x: statusLabel.frame.maxX + 8,
            y: 4,
            width: max(0, bookmarkButton.frame.minX - statusLabel.frame.maxX - 16),
            height: bounds.height - 8
        )
    }

    private func configureLayer() {
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.88).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.32).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 4
        layer?.shadowOffset = NSSize(width: 0, height: 1)
    }

    private func configureLabels() {
        let statusText = block.exitCode.map { $0 == 0 ? "ok" : "exit \($0)" } ?? "run"
        statusLabel.stringValue = statusText
        statusLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        statusLabel.textColor = block.exitCode == 0
            ? NSColor.systemGreen
            : NSColor.systemRed
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingTail

        commandLabel.stringValue = block.command.isEmpty ? "(command)" : block.command
        commandLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        commandLabel.textColor = .labelColor
        commandLabel.lineBreakMode = .byTruncatingMiddle

        addSubview(statusLabel)
        addSubview(commandLabel)
    }

    private func configureButtons() {
        configureIconButton(
            bookmarkButton,
            symbolName: block.isBookmarked ? "bookmark.fill" : "bookmark",
            accessibilityLabel: block.isBookmarked ? "Remove block bookmark" : "Bookmark command block",
            identifier: "command-block-bookmark-\(block.id)",
            action: #selector(toggleBookmark)
        )
        configureIconButton(
            shareButton,
            symbolName: "square.and.arrow.up",
            accessibilityLabel: "Share command block",
            identifier: "command-block-share-\(block.id)",
            action: #selector(shareBlock)
        )
        configureIconButton(
            copyButton,
            symbolName: "doc.on.doc",
            accessibilityLabel: "Copy block output",
            identifier: "command-block-copy-\(block.id)",
            action: #selector(copyBlockOutput)
        )
        configureIconButton(
            rerunButton,
            symbolName: "arrow.clockwise",
            accessibilityLabel: "Rerun command block",
            identifier: "command-block-rerun-\(block.id)",
            action: #selector(rerunBlock)
        )
        addSubview(bookmarkButton)
        addSubview(shareButton)
        addSubview(copyButton)
        addSubview(rerunButton)
    }

    private func configureIconButton(
        _ button: NSButton,
        symbolName: String,
        accessibilityLabel: String,
        identifier: String,
        action: Selector
    ) {
        button.isBordered = false
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityLabel
        )
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityIdentifier(identifier)
    }

    @objc private func copyBlockOutput() {
        onCopy?(block)
    }

    @objc private func rerunBlock() {
        onRerun?(block)
    }

    @objc private func shareBlock() {
        onShare?(block, shareButton)
    }

    @objc private func toggleBookmark() {
        onBookmark?(block)
    }
}
