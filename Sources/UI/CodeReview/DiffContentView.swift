// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DiffContentView.swift - Native AppKit diff renderer for the review panel.

import AppKit
import SwiftUI

@MainActor
final class DiffContentView: NSView {
    private static let maximumRenderableLines = 4_000

    private let scrollView = NSScrollView()
    private let containerView = NSView()
    private let stackView = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "Select a changed file to review it here")
    private var hunkHeaderViewsByID: [String: HunkHeaderView] = [:]
    private var lineRowsByNumber: [Int: [DiffLineRowView]] = [:]
    private var appliedSelectedLineNumber: Int?
    private var appliedSelectedHunkID: String?

    var fileDiff: FileDiff? { didSet { if fileDiff != oldValue { renderContent() } } }
    var comments: [ReviewComment] = [] { didSet { if comments != oldValue { renderContent() } } }
    var selectedLineNumber: Int? { didSet { updateSelectionState() } }
    var selectedHunkID: String? { didSet { updateSelectionState() } }

    var onLineClicked: ((String, Int) -> Void)?
    var onAcceptHunk: ((DiffHunk) -> Void)?
    var onRejectHunk: ((DiffHunk) -> Void)?
    var onSelectHunk: ((DiffHunk) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DiffContentView does not support NSCoding")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = CocxyColors.base.cgColor

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.spacing = 6
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(stackView)
        scrollView.documentView = containerView

        emptyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        emptyLabel.textColor = CocxyColors.overlay1
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            containerView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func renderContent() {
        stackView.arrangedSubviews.forEach { subview in
            stackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        hunkHeaderViewsByID.removeAll()
        lineRowsByNumber.removeAll()
        appliedSelectedLineNumber = nil
        appliedSelectedHunkID = nil

        guard let fileDiff else {
            scrollView.isHidden = true
            emptyLabel.isHidden = false
            return
        }

        scrollView.isHidden = false
        emptyLabel.isHidden = true

        if let note = fileDiff.reviewNote {
            addArrangedSubviewFillingWidth(makeNoticeView(note))
        }

        if fileDiff.hunks.isEmpty {
            if fileDiff.reviewNote == nil {
                addArrangedSubviewFillingWidth(makeNoticeView("No textual hunks are available for this file."))
            }
            return
        }

        var renderedLines = 0
        var didTruncateLargeDiff = false
        for hunk in fileDiff.hunks {
            let header = makeHunkHeaderView(hunk)
            hunkHeaderViewsByID[hunk.id] = header
            addArrangedSubviewFillingWidth(header)

            for line in hunk.lines {
                if renderedLines >= Self.maximumRenderableLines {
                    didTruncateLargeDiff = true
                    break
                }
                let row = makeLineRow(filePath: fileDiff.filePath, line: line)
                if let displayLine = line.displayLineNumber {
                    lineRowsByNumber[displayLine, default: []].append(row)
                }
                addArrangedSubviewFillingWidth(row)
                renderedLines += 1

                if let displayLine = line.displayLineNumber {
                    let lineComments = comments
                        .filter { $0.filePath == fileDiff.filePath && $0.lineRange.contains(displayLine) }
                    for comment in lineComments {
                        addArrangedSubviewFillingWidth(makeCommentBubble(comment), inset: -50)
                    }
                }
            }

            if didTruncateLargeDiff {
                break
            }
        }

        if didTruncateLargeDiff {
            addArrangedSubviewFillingWidth(
                makeNoticeView(
                    "Large diff detected. Showing the first \(Self.maximumRenderableLines.formatted()) lines to keep review responsive."
                )
            )
        }

        updateSelectionState(force: true)
    }

    private func addArrangedSubviewFillingWidth(_ view: NSView, inset: CGFloat = 0) {
        stackView.addArrangedSubview(view)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: inset)
        ])
    }

    private func updateSelectionState(force: Bool = false) {
        if force || appliedSelectedHunkID != selectedHunkID {
            if let previousHunkID = appliedSelectedHunkID,
               let previousView = hunkHeaderViewsByID[previousHunkID] {
                previousView.setSelected(false)
            }
            if let selectedHunkID,
               let selectedView = hunkHeaderViewsByID[selectedHunkID] {
                selectedView.setSelected(true)
            }
            appliedSelectedHunkID = selectedHunkID
        }

        if force || appliedSelectedLineNumber != selectedLineNumber {
            if let previousLine = appliedSelectedLineNumber {
                lineRowsByNumber[previousLine]?.forEach { $0.setSelected(false) }
            }
            if let selectedLineNumber {
                lineRowsByNumber[selectedLineNumber]?.forEach { $0.setSelected(true) }
            }
            appliedSelectedLineNumber = selectedLineNumber
        }
    }

    private func makeNoticeView(_ text: String) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = CocxyColors.surface0.withAlphaComponent(0.8).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: nil)
        icon.contentTintColor = CocxyColors.yellow
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = CocxyColors.subtext0
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            icon.widthAnchor.constraint(equalToConstant: 12),
            icon.heightAnchor.constraint(equalToConstant: 12),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        return container
    }

    private func makeHunkHeaderView(_ hunk: DiffHunk) -> HunkHeaderView {
        let header = HunkHeaderView(hunk: hunk)
        header.setSelected(hunk.id == selectedHunkID)
        header.onAccept = { [weak self] in
            self?.onAcceptHunk?(hunk)
        }
        header.onReject = { [weak self] in
            self?.onRejectHunk?(hunk)
        }
        header.onSelect = { [weak self] in
            self?.onSelectHunk?(hunk)
        }
        return header
    }

    private func makeLineRow(filePath: String, line: DiffLine) -> DiffLineRowView {
        let row = DiffLineRowView()
        row.configure(
            filePath: filePath,
            line: line,
            isSelected: selectedLineNumber == line.displayLineNumber
        )
        row.onActivate = { [weak self] filePath, lineNumber in
            self?.onLineClicked?(filePath, lineNumber)
        }
        return row
    }

    private func makeCommentBubble(_ comment: ReviewComment) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = CocxyColors.surface0.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: nil)
        icon.contentTintColor = CocxyColors.yellow
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: comment.body)
        label.font = .systemFont(ofSize: 11)
        label.textColor = CocxyColors.text
        label.translatesAutoresizingMaskIntoConstraints = false
        label.maximumNumberOfLines = 0

        container.addSubview(icon)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            icon.widthAnchor.constraint(equalToConstant: 12),
            icon.heightAnchor.constraint(equalToConstant: 12),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        return container
    }
}

private final class ClosureButton: NSButton {
    private let handler: () -> Void

    init(symbolName: String, tintColor: NSColor, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        imagePosition = .imageOnly
        bezelStyle = .texturedRounded
        isBordered = false
        contentTintColor = tintColor
        translatesAutoresizingMaskIntoConstraints = false
        target = self
        action = #selector(handlePress)
        setAccessibilityLabel(symbolName == "checkmark.circle" ? "Accept hunk" : "Reject hunk")
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 18),
            heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ClosureButton does not support NSCoding")
    }

    @objc private func handlePress() {
        handler()
    }
}

private final class DiffLineRowView: NSView {
    var onActivate: ((String, Int) -> Void)?

    private let oldNumberLabel = NSTextField(labelWithString: "")
    private let newNumberLabel = NSTextField(labelWithString: "")
    private let prefixLabel = NSTextField(labelWithString: "")
    private let contentLabel = NSTextField(wrappingLabelWithString: "")
    private var filePath: String = ""
    private var lineNumber: Int?
    private var lineKind: DiffLine.Kind = .context

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DiffLineRowView does not support NSCoding")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 6

        [oldNumberLabel, newNumberLabel, prefixLabel, contentLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        oldNumberLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        newNumberLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        prefixLabel.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        contentLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        contentLabel.maximumNumberOfLines = 0

        NSLayoutConstraint.activate([
            oldNumberLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            oldNumberLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            oldNumberLabel.widthAnchor.constraint(equalToConstant: 38),

            newNumberLabel.leadingAnchor.constraint(equalTo: oldNumberLabel.trailingAnchor, constant: 4),
            newNumberLabel.topAnchor.constraint(equalTo: oldNumberLabel.topAnchor),
            newNumberLabel.widthAnchor.constraint(equalToConstant: 38),

            prefixLabel.leadingAnchor.constraint(equalTo: newNumberLabel.trailingAnchor, constant: 8),
            prefixLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            prefixLabel.widthAnchor.constraint(equalToConstant: 10),

            contentLabel.leadingAnchor.constraint(equalTo: prefixLabel.trailingAnchor, constant: 8),
            contentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            contentLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            contentLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])

        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(recognizer)
    }

    func configure(filePath: String, line: DiffLine, isSelected: Bool) {
        self.filePath = filePath
        self.lineNumber = line.displayLineNumber
        self.lineKind = line.kind

        oldNumberLabel.stringValue = line.oldLineNumber.map(String.init) ?? ""
        newNumberLabel.stringValue = line.newLineNumber.map(String.init) ?? ""
        oldNumberLabel.textColor = CocxyColors.overlay1
        newNumberLabel.textColor = CocxyColors.overlay1

        contentLabel.stringValue = line.content
        switch line.kind {
        case .context:
            prefixLabel.stringValue = " "
            prefixLabel.textColor = CocxyColors.overlay1
            contentLabel.textColor = CocxyColors.text
        case .addition:
            prefixLabel.stringValue = "+"
            prefixLabel.textColor = CocxyColors.green
            contentLabel.textColor = CocxyColors.green
        case .deletion:
            prefixLabel.stringValue = "-"
            prefixLabel.textColor = CocxyColors.red
            contentLabel.textColor = CocxyColors.red
        }
        setSelected(isSelected)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityDescription(for: line))
        setAccessibilityHelp("Select this diff line to anchor an inline comment")
    }

    func setSelected(_ isSelected: Bool) {
        switch lineKind {
        case .context:
            layer?.backgroundColor = (isSelected ? CocxyColors.surface0.withAlphaComponent(0.5) : NSColor.clear).cgColor
        case .addition:
            layer?.backgroundColor = (isSelected
                ? CocxyColors.green.withAlphaComponent(0.18)
                : CocxyColors.green.withAlphaComponent(0.08)).cgColor
        case .deletion:
            layer?.backgroundColor = (isSelected
                ? CocxyColors.red.withAlphaComponent(0.18)
                : CocxyColors.red.withAlphaComponent(0.08)).cgColor
        }
    }

    @objc private func handleTap() {
        guard let lineNumber else { return }
        onActivate?(filePath, lineNumber)
    }

    private func accessibilityDescription(for line: DiffLine) -> String {
        let lineLabel: String
        if let number = line.displayLineNumber {
            lineLabel = "line \(number)"
        } else {
            lineLabel = "non-commentable line"
        }

        let kindDescription: String
        switch line.kind {
        case .context:
            kindDescription = "context"
        case .addition:
            kindDescription = "addition"
        case .deletion:
            kindDescription = "deletion"
        }

        return "\(kindDescription.capitalized) \(lineLabel): \(line.content)"
    }
}

@MainActor
struct DiffContentBridge: NSViewRepresentable {
    let fileDiff: FileDiff?
    let comments: [ReviewComment]
    let selectedLineNumber: Int?
    let selectedHunkID: String?
    var onLineClicked: ((String, Int) -> Void)?
    var onSelectHunk: ((DiffHunk) -> Void)?
    var onAcceptHunk: ((DiffHunk) -> Void)?
    var onRejectHunk: ((DiffHunk) -> Void)?

    func makeNSView(context: Context) -> DiffContentView {
        DiffContentView()
    }

    func updateNSView(_ nsView: DiffContentView, context: Context) {
        nsView.fileDiff = fileDiff
        nsView.comments = comments
        nsView.selectedLineNumber = selectedLineNumber
        nsView.selectedHunkID = selectedHunkID
        nsView.onLineClicked = onLineClicked
        nsView.onSelectHunk = onSelectHunk
        nsView.onAcceptHunk = onAcceptHunk
        nsView.onRejectHunk = onRejectHunk
    }
}

private final class HunkHeaderView: NSView {
    var onAccept: (() -> Void)?
    var onReject: (() -> Void)?
    var onSelect: (() -> Void)?

    private let title = NSTextField(labelWithString: "")
    private let stats = NSTextField(labelWithString: "")
    private lazy var acceptButton = ClosureButton(symbolName: "checkmark.circle", tintColor: CocxyColors.green) { [weak self] in
        self?.onAccept?()
    }
    private lazy var rejectButton = ClosureButton(symbolName: "xmark.circle", tintColor: CocxyColors.red) { [weak self] in
        self?.onReject?()
    }

    init(hunk: DiffHunk) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false

        title.stringValue = hunk.header
        title.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        title.textColor = CocxyColors.blue
        title.translatesAutoresizingMaskIntoConstraints = false

        stats.stringValue = "+\(hunk.additions)  -\(hunk.deletions)"
        stats.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        stats.textColor = CocxyColors.overlay1
        stats.translatesAutoresizingMaskIntoConstraints = false

        addSubview(title)
        addSubview(stats)
        addSubview(acceptButton)
        addSubview(rejectButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 30),

            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),

            rejectButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rejectButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            acceptButton.trailingAnchor.constraint(equalTo: rejectButton.leadingAnchor, constant: -6),
            acceptButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            stats.trailingAnchor.constraint(equalTo: acceptButton.leadingAnchor, constant: -10),
            stats.centerYAnchor.constraint(equalTo: centerYAnchor),
            stats.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 12)
        ])

        let tap = NSClickGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Diff hunk \(hunk.header)")
        setAccessibilityHelp("Select this hunk, or use the accept and reject buttons")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HunkHeaderView does not support NSCoding")
    }

    func setSelected(_ isSelected: Bool) {
        layer?.backgroundColor = (
            isSelected
            ? CocxyColors.blue.withAlphaComponent(0.14)
            : CocxyColors.surface0.withAlphaComponent(0.55)
        ).cgColor
    }

    @objc private func handleTap() {
        onSelect?()
    }
}
