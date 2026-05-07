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
    private let fileNameLabel = NSTextField(labelWithString: "")
    private let modeSegmented = NSSegmentedControl()
    private let blameButton = NSButton()
    private let diffButton = NSButton()
    private let copyButton = NSButton()
    private let exportPDFButton = NSButton()
    private let exportHTMLButton = NSButton()
    private var exportSlidesButton: NSButton!
    private let outlineToggleButton = NSButton()
    private let reloadButton = NSButton()
    private let overflowButton = NSButton()
    private let rightControlsStack = NSStackView()
    private var localizer: AppLocalizer
    private var isUsingCompactToolbar = false

    /// Height of the toolbar.
    static let height: CGFloat = 34
    private static let compactToolbarWidth: CGFloat = 430

    /// Current file name displayed.
    var fileName: String = "" {
        didSet {
            fileNameLabel.stringValue = fileName
            fileNameLabel.toolTip = fileName
        }
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

    /// Invoked when Copy As > Markdown is selected.
    var onCopyMarkdown: (() -> Void)?

    /// Invoked when Copy As > HTML is selected.
    var onCopyHTML: (() -> Void)?

    /// Invoked when Copy As > Rich Text is selected.
    var onCopyRichText: (() -> Void)?

    /// Invoked when Copy As > Plain Text is selected.
    var onCopyPlainText: (() -> Void)?

    // MARK: - Init

    init(localizer: AppLocalizer = AppLocalizer(languagePreference: .system)) {
        self.localizer = localizer
        super.init(frame: .zero)
        setupUI()
        fileName = Self.localizedUntitledFileName(using: localizer)
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
        fileNameLabel.toolTip = fileName
        fileNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        fileNameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fileNameLabel)

        // Mode segmented
        modeSegmented.segmentStyle = .rounded
        modeSegmented.segmentCount = 3
        for (index, mode) in MarkdownViewMode.allCases.enumerated() {
            modeSegmented.setLabel(mode.localizedToolbarLabel(using: localizer), forSegment: index)
            modeSegmented.setWidth(60, forSegment: index)
            modeSegmented.setToolTip(mode.localizedLabel(using: localizer), forSegment: index)
        }
        modeSegmented.selectedSegment = 0
        modeSegmented.toolTip = Self.localizedModeTooltip(using: localizer)
        modeSegmented.target = self
        modeSegmented.action = #selector(modeChanged(_:))
        modeSegmented.setContentCompressionResistancePriority(.required, for: .horizontal)
        modeSegmented.setContentHuggingPriority(.required, for: .horizontal)
        modeSegmented.translatesAutoresizingMaskIntoConstraints = false
        addSubview(modeSegmented)

        // Blame
        configureIconButton(
            blameButton,
            systemName: "person.text.rectangle",
            accessibility: Self.localizedShowGitBlame(using: localizer),
            action: #selector(blameClicked)
        )

        // Diff
        configureIconButton(
            diffButton,
            systemName: "arrow.left.arrow.right",
            accessibility: Self.localizedShowGitDiff(using: localizer),
            action: #selector(diffClicked)
        )

        // Copy menu
        configureIconButton(
            copyButton,
            systemName: "doc.on.clipboard",
            accessibility: Self.localizedCopyAs(using: localizer),
            action: #selector(copyClicked(_:))
        )

        // Export PDF
        configureIconButton(
            exportPDFButton,
            systemName: "arrow.down.doc",
            accessibility: Self.localizedExportPDF(using: localizer),
            action: #selector(exportPDFClicked)
        )

        // Export HTML
        configureIconButton(
            exportHTMLButton,
            systemName: "globe",
            accessibility: Self.localizedExportHTML(using: localizer),
            action: #selector(exportHTMLClicked)
        )

        // Export Slides
        let exportSlidesButton = NSButton()
        configureIconButton(
            exportSlidesButton,
            systemName: "rectangle.split.3x1",
            accessibility: Self.localizedExportSlides(using: localizer),
            action: #selector(exportSlidesClicked)
        )
        self.exportSlidesButton = exportSlidesButton

        // Overflow for narrow split panes.
        configureIconButton(
            overflowButton,
            systemName: "ellipsis.circle",
            accessibility: Self.localizedMoreActions(using: localizer),
            action: #selector(overflowClicked(_:))
        )
        overflowButton.isHidden = true

        // Outline toggle
        configureIconButton(
            outlineToggleButton,
            systemName: "sidebar.left",
            accessibility: Self.localizedToggleSidebar(using: localizer),
            action: #selector(outlineToggleClicked)
        )

        // Reload
        configureIconButton(
            reloadButton,
            systemName: "arrow.clockwise",
            accessibility: Self.localizedReloadFile(using: localizer),
            action: #selector(reloadClicked)
        )

        rightControlsStack.orientation = .horizontal
        rightControlsStack.alignment = .centerY
        rightControlsStack.spacing = 4
        rightControlsStack.translatesAutoresizingMaskIntoConstraints = false
        rightControlsStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        [
            blameButton,
            diffButton,
            copyButton,
            exportPDFButton,
            exportHTMLButton,
            exportSlidesButton,
            overflowButton,
            outlineToggleButton,
            reloadButton
        ].forEach(rightControlsStack.addArrangedSubview)
        addSubview(rightControlsStack)

        let modeCenterX = modeSegmented.centerXAnchor.constraint(equalTo: centerXAnchor)
        modeCenterX.priority = .defaultHigh

        let allToolbarButtons = [
            blameButton,
            diffButton,
            copyButton,
            exportPDFButton,
            exportHTMLButton,
            exportSlidesButton,
            overflowButton,
            outlineToggleButton,
            reloadButton
        ]
        let buttonSizeConstraints = allToolbarButtons.flatMap { button in
            [
                button.widthAnchor.constraint(equalToConstant: 22),
                button.heightAnchor.constraint(equalToConstant: 22)
            ]
        }

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            fileNameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            fileNameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            fileNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: modeSegmented.leadingAnchor, constant: -10),

            modeCenterX,
            modeSegmented.leadingAnchor.constraint(greaterThanOrEqualTo: fileNameLabel.trailingAnchor, constant: 10),
            modeSegmented.trailingAnchor.constraint(lessThanOrEqualTo: rightControlsStack.leadingAnchor, constant: -8),
            modeSegmented.centerYAnchor.constraint(equalTo: centerYAnchor),

            rightControlsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            rightControlsStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ] + buttonSizeConstraints)
    }

    override func layout() {
        applyResponsiveToolbarLayout(for: bounds.width)
        super.layout()
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        let previousUntitledName = Self.localizedUntitledFileName(using: self.localizer)
        self.localizer = localizer
        if fileName.isEmpty || fileName == previousUntitledName {
            fileName = Self.localizedUntitledFileName(using: localizer)
        }
        for (index, mode) in MarkdownViewMode.allCases.enumerated() {
            modeSegmented.setLabel(mode.localizedToolbarLabel(using: localizer), forSegment: index)
            modeSegmented.setToolTip(mode.localizedLabel(using: localizer), forSegment: index)
        }
        modeSegmented.toolTip = Self.localizedModeTooltip(using: localizer)
        applyButtonCopy(blameButton, Self.localizedShowGitBlame(using: localizer))
        applyButtonCopy(diffButton, Self.localizedShowGitDiff(using: localizer))
        applyButtonCopy(copyButton, Self.localizedCopyAs(using: localizer))
        applyButtonCopy(exportPDFButton, Self.localizedExportPDF(using: localizer))
        applyButtonCopy(exportHTMLButton, Self.localizedExportHTML(using: localizer))
        applyButtonCopy(exportSlidesButton, Self.localizedExportSlides(using: localizer))
        applyButtonCopy(overflowButton, Self.localizedMoreActions(using: localizer))
        applyButtonCopy(outlineToggleButton, Self.localizedToggleSidebar(using: localizer))
        applyButtonCopy(reloadButton, Self.localizedReloadFile(using: localizer))
    }

    private func applyResponsiveToolbarLayout(for width: CGFloat) {
        let useCompact = width < Self.compactToolbarWidth
        guard useCompact != isUsingCompactToolbar else { return }
        isUsingCompactToolbar = useCompact
        [
            blameButton,
            diffButton,
            copyButton,
            exportPDFButton,
            exportHTMLButton,
            exportSlidesButton
        ].forEach { $0.isHidden = useCompact }
        overflowButton.isHidden = !useCompact
        rightControlsStack.needsLayout = true
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
        button.toolTip = accessibility
        button.setAccessibilityLabel(accessibility)
        button.contentTintColor = CocxyColors.subtext0
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func applyButtonCopy(_ button: NSButton, _ copy: String) {
        button.toolTip = copy
        button.setAccessibilityLabel(copy)
        button.image?.accessibilityDescription = copy
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

    @objc private func copyClicked(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(
            withTitle: Self.localizedCopyAsMarkdown(using: localizer),
            action: #selector(copyMarkdownClicked),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: Self.localizedCopyAsHTML(using: localizer),
            action: #selector(copyHTMLClicked),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: Self.localizedCopyAsRichText(using: localizer),
            action: #selector(copyRichTextClicked),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: Self.localizedCopyAsPlainText(using: localizer),
            action: #selector(copyPlainTextClicked),
            keyEquivalent: ""
        )
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func overflowClicked(_ sender: NSButton) {
        let menu = NSMenu()
        addMenuItem(menu, title: Self.localizedShowGitBlame(using: localizer), action: #selector(blameClicked))
        addMenuItem(menu, title: Self.localizedShowGitDiff(using: localizer), action: #selector(diffClicked))
        menu.addItem(.separator())

        let copyItem = NSMenuItem(title: Self.localizedCopyAs(using: localizer), action: nil, keyEquivalent: "")
        let copyMenu = NSMenu()
        addMenuItem(copyMenu, title: Self.localizedCopyAsMarkdown(using: localizer), action: #selector(copyMarkdownClicked))
        addMenuItem(copyMenu, title: Self.localizedCopyAsHTML(using: localizer), action: #selector(copyHTMLClicked))
        addMenuItem(copyMenu, title: Self.localizedCopyAsRichText(using: localizer), action: #selector(copyRichTextClicked))
        addMenuItem(copyMenu, title: Self.localizedCopyAsPlainText(using: localizer), action: #selector(copyPlainTextClicked))
        copyItem.submenu = copyMenu
        menu.addItem(copyItem)

        menu.addItem(.separator())
        addMenuItem(menu, title: Self.localizedExportPDF(using: localizer), action: #selector(exportPDFClicked))
        addMenuItem(menu, title: Self.localizedExportHTML(using: localizer), action: #selector(exportHTMLClicked))
        addMenuItem(menu, title: Self.localizedExportSlides(using: localizer), action: #selector(exportSlidesClicked))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    private func addMenuItem(_ menu: NSMenu, title: String, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
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

    @objc private func copyMarkdownClicked() {
        onCopyMarkdown?()
    }

    @objc private func copyHTMLClicked() {
        onCopyHTML?()
    }

    @objc private func copyRichTextClicked() {
        onCopyRichText?()
    }

    @objc private func copyPlainTextClicked() {
        onCopyPlainText?()
    }

    // MARK: - Helpers

    private func modeIndex(for mode: MarkdownViewMode) -> Int {
        MarkdownViewMode.allCases.firstIndex(of: mode) ?? 0
    }

    static func localizedModeTooltip(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.toolbar.mode.tooltip", fallback: "Switch between Source, Preview, and Split view")
    }

    static func localizedUntitledFileName(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.toolbar.untitledFile", fallback: "Untitled.md")
    }

    static func localizedShowGitBlame(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.toolbar.gitBlame", fallback: "Show Git Blame")
    }

    static func localizedShowGitDiff(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.toolbar.gitDiff", fallback: "Show Git Diff")
    }

    static func localizedCopyAs(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.toolbar.copyAs", fallback: "Copy As")
    }

    static func localizedExportPDF(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.toolbar.exportPDF", fallback: "Export PDF (Cmd+Shift+E)")
    }

    static func localizedExportHTML(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.toolbar.exportHTML", fallback: "Export HTML (Cmd+Shift+H)")
    }

    static func localizedExportSlides(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.toolbar.exportSlides", fallback: "Export Slides (Cmd+Shift+S)")
    }

    static func localizedMoreActions(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.toolbar.moreActions", fallback: "More Markdown actions")
    }

    static func localizedToggleSidebar(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.toolbar.toggleSidebar", fallback: "Toggle Sidebar (Cmd+Shift+O)")
    }

    static func localizedReloadFile(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.toolbar.reloadFile", fallback: "Reload File (Cmd+R)")
    }

    static func localizedCopyAsMarkdown(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.toolbar.copyAs.markdown", fallback: "Copy as Markdown")
    }

    static func localizedCopyAsHTML(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.toolbar.copyAs.html", fallback: "Copy as HTML")
    }

    static func localizedCopyAsRichText(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.toolbar.copyAs.richText", fallback: "Copy as Rich Text")
    }

    static func localizedCopyAsPlainText(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.toolbar.copyAs.plainText", fallback: "Copy as Plain Text")
    }
}
