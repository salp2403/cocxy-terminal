// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownToolbarView.swift - Header toolbar for the markdown panel: file name, mode switcher, outline toggle.

import AppKit

// MARK: - Toolbar View

/// Horizontal toolbar sitting above the markdown content area.
///
/// Shows (left → right):
/// - A document icon + the current file name
/// - A segmented control to switch between Source / Preview / Split
/// - An outline toggle button
/// - A reload button
@MainActor
final class MarkdownToolbarView: NSView {

    // MARK: - Properties

    private let iconView = NSImageView()
    private let fileNameLabel = NSTextField(labelWithString: "Untitled.md")
    private let modeSegmented = NSSegmentedControl()
    private let blameButton = NSButton()
    private let diffButton = NSButton()
    private let exportPDFButton = NSButton()
    private let exportHTMLButton = NSButton()
    private var exportSlidesButton: NSButton!
    private let outlineToggleButton = NSButton()
    private let reloadButton = NSButton()

    /// Height of the toolbar.
    static let height: CGFloat = 34

    /// Current file name displayed.
    var fileName: String = "Untitled.md" {
        didSet { fileNameLabel.stringValue = fileName }
    }

    /// Current mode. Setting updates the segmented control selection.
    var mode: MarkdownViewMode = .source {
        didSet { modeSegmented.selectedSegment = modeIndex(for: mode) }
    }

    /// Whether the outline toggle is currently "on".
    var isOutlineVisible: Bool = false {
        didSet {
            outlineToggleButton.state = isOutlineVisible ? .on : .off
            outlineToggleButton.contentTintColor = isOutlineVisible
                ? CocxyColors.blue
                : CocxyColors.subtext0
        }
    }

    /// Invoked when the mode segmented control changes selection.
    var onModeChanged: ((MarkdownViewMode) -> Void)?

    /// Invoked when the outline toggle is clicked.
    var onOutlineToggle: (() -> Void)?

    /// Invoked when the reload button is clicked.
    var onReload: (() -> Void)?

    /// Invoked when Blame toggle is clicked.
    var onBlameToggle: (() -> Void)?

    /// Invoked when Diff toggle is clicked.
    var onDiffToggle: (() -> Void)?

    /// Invoked when Export PDF is clicked.
    var onExportPDF: (() -> Void)?

    /// Invoked when Export HTML is clicked.
    var onExportHTML: (() -> Void)?

    /// Invoked when Export Slides is clicked.
    var onExportSlides: (() -> Void)?

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MarkdownToolbarView does not support NSCoding")
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = CocxyColors.mantle.cgColor

        // Icon
        if let image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Markdown") {
            iconView.image = image.withSymbolConfiguration(
                .init(pointSize: 13, weight: .medium)
            )
        }
        iconView.contentTintColor = CocxyColors.blue
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // File name
        fileNameLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        fileNameLabel.textColor = CocxyColors.text
        fileNameLabel.lineBreakMode = .byTruncatingMiddle
        fileNameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fileNameLabel)

        // Mode segmented
        modeSegmented.segmentStyle = .rounded
        modeSegmented.segmentCount = 3
        for (index, mode) in MarkdownViewMode.allCases.enumerated() {
            modeSegmented.setLabel(mode.label, forSegment: index)
            modeSegmented.setWidth(60, forSegment: index)
        }
        modeSegmented.selectedSegment = 0
        modeSegmented.target = self
        modeSegmented.action = #selector(modeChanged(_:))
        modeSegmented.translatesAutoresizingMaskIntoConstraints = false
        addSubview(modeSegmented)

        // Blame
        configureIconButton(
            blameButton,
            systemName: "person.text.rectangle",
            accessibility: "Git Blame",
            action: #selector(blameClicked)
        )
        addSubview(blameButton)

        // Diff
        configureIconButton(
            diffButton,
            systemName: "arrow.left.arrow.right",
            accessibility: "Git Diff",
            action: #selector(diffClicked)
        )
        addSubview(diffButton)

        // Export PDF
        configureIconButton(
            exportPDFButton,
            systemName: "arrow.down.doc",
            accessibility: "Export PDF",
            action: #selector(exportPDFClicked)
        )
        addSubview(exportPDFButton)

        // Export HTML
        configureIconButton(
            exportHTMLButton,
            systemName: "globe",
            accessibility: "Export HTML",
            action: #selector(exportHTMLClicked)
        )
        addSubview(exportHTMLButton)

        // Export Slides
        let exportSlidesButton = NSButton()
        configureIconButton(
            exportSlidesButton,
            systemName: "rectangle.split.3x1",
            accessibility: "Export Slides",
            action: #selector(exportSlidesClicked)
        )
        addSubview(exportSlidesButton)
        self.exportSlidesButton = exportSlidesButton

        // Outline toggle
        configureIconButton(
            outlineToggleButton,
            systemName: "sidebar.left",
            accessibility: "Toggle outline",
            action: #selector(outlineToggleClicked)
        )
        addSubview(outlineToggleButton)

        // Reload
        configureIconButton(
            reloadButton,
            systemName: "arrow.clockwise",
            accessibility: "Reload file",
            action: #selector(reloadClicked)
        )
        addSubview(reloadButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            fileNameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            fileNameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            fileNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: modeSegmented.leadingAnchor, constant: -10),

            modeSegmented.centerXAnchor.constraint(equalTo: centerXAnchor),
            modeSegmented.centerYAnchor.constraint(equalTo: centerYAnchor),

            reloadButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            reloadButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 22),
            reloadButton.heightAnchor.constraint(equalToConstant: 22),

            exportSlidesButton.trailingAnchor.constraint(equalTo: outlineToggleButton.leadingAnchor, constant: -4),
            exportSlidesButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            exportSlidesButton.widthAnchor.constraint(equalToConstant: 22),
            exportSlidesButton.heightAnchor.constraint(equalToConstant: 22),

            outlineToggleButton.trailingAnchor.constraint(equalTo: reloadButton.leadingAnchor, constant: -4),
            outlineToggleButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            outlineToggleButton.widthAnchor.constraint(equalToConstant: 22),
            outlineToggleButton.heightAnchor.constraint(equalToConstant: 22),

            exportHTMLButton.trailingAnchor.constraint(equalTo: exportSlidesButton.leadingAnchor, constant: -4),
            exportHTMLButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            exportHTMLButton.widthAnchor.constraint(equalToConstant: 22),
            exportHTMLButton.heightAnchor.constraint(equalToConstant: 22),

            exportPDFButton.trailingAnchor.constraint(equalTo: exportHTMLButton.leadingAnchor, constant: -4),
            exportPDFButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            exportPDFButton.widthAnchor.constraint(equalToConstant: 22),
            exportPDFButton.heightAnchor.constraint(equalToConstant: 22),

            diffButton.trailingAnchor.constraint(equalTo: exportPDFButton.leadingAnchor, constant: -4),
            diffButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            diffButton.widthAnchor.constraint(equalToConstant: 22),
            diffButton.heightAnchor.constraint(equalToConstant: 22),

            blameButton.trailingAnchor.constraint(equalTo: diffButton.leadingAnchor, constant: -4),
            blameButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            blameButton.widthAnchor.constraint(equalToConstant: 22),
            blameButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    private func configureIconButton(
        _ button: NSButton,
        systemName: String,
        accessibility: String,
        action: Selector
    ) {
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        if let image = NSImage(systemSymbolName: systemName, accessibilityDescription: accessibility) {
            button.image = image.withSymbolConfiguration(
                .init(pointSize: 12, weight: .medium)
            )
        }
        button.contentTintColor = CocxyColors.subtext0
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Actions

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        let newMode = MarkdownViewMode.allCases[sender.selectedSegment]
        onModeChanged?(newMode)
    }

    @objc private func outlineToggleClicked() {
        onOutlineToggle?()
    }

    @objc private func reloadClicked() {
        onReload?()
    }

    @objc private func blameClicked() {
        onBlameToggle?()
    }

    @objc private func diffClicked() {
        onDiffToggle?()
    }

    @objc private func exportPDFClicked() {
        onExportPDF?()
    }

    @objc private func exportHTMLClicked() {
        onExportHTML?()
    }

    @objc private func exportSlidesClicked() {
        onExportSlides?()
    }

    // MARK: - Helpers

    private func modeIndex(for mode: MarkdownViewMode) -> Int {
        MarkdownViewMode.allCases.firstIndex(of: mode) ?? 0
    }
}
