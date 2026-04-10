// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownContentView.swift - Embeddable markdown viewer for workspace splits.
//
// This is the Clearly+ rewrite of the original panel:
// - Real GFM parser in `MarkdownParser` (Swift, zero deps)
// - Syntax-highlighted source view via `MarkdownSyntaxHighlighter`
// - Rendered preview view via `MarkdownRenderer`
// - Side-by-side split mode backed by `NSSplitView`
// - Outline sidebar (`MarkdownOutlineView`) for heading navigation
// - Toolbar mode switcher + outline toggle + reload button
// - Frontmatter YAML extraction, GFM tables, task lists, strike, code fences
//
// The public constructor and `loadFile(_:)` signatures are preserved so
// `MainWindowController+SplitActions` keeps working without modification.

import AppKit

// MARK: - Markdown Content View

/// NSView that renders a markdown file for embedding in workspace splits.
///
/// ## Layout
///
/// ```
/// +--------------------------------------------+
/// | [doc] filename.md   [ Src|Pre|Split ] [O][R]|  <- toolbar
/// +----+---------------------------------------+
/// |    |                                       |
/// | Ol |     Source / Preview / Split          |
/// | ine|                                       |
/// +----+---------------------------------------+
/// ```
///
/// The outline column collapses to zero width when hidden.
///
/// - SeeAlso: `PanelType.markdown`
@MainActor
final class MarkdownContentView: NSView {

    // MARK: - Properties (preserved API)

    /// The file being displayed. Preserved from the previous implementation.
    private(set) var filePath: URL?

    // MARK: - Properties (new)

    private let toolbar = MarkdownToolbarView()
    private let outlineView = MarkdownOutlineView()
    private let sourceView: MarkdownSourceView
    private let previewView: MarkdownPreviewView
    private let splitContainer = NSSplitView()
    private let contentContainer = NSView()

    /// File-system watcher that reloads the document when the source file
    /// changes on disk.
    private var fileMonitor: DispatchSourceFileSystemObject?

    /// Current view mode. Setting updates the displayed subview and toolbar.
    private(set) var mode: MarkdownViewMode = .source {
        didSet {
            if oldValue != mode {
                applyMode()
                toolbar.mode = mode
            }
        }
    }

    /// Whether the outline sidebar is currently visible.
    private(set) var isOutlineVisible: Bool = true {
        didSet {
            if oldValue != isOutlineVisible {
                applyOutlineVisibility()
                toolbar.isOutlineVisible = isOutlineVisible
            }
        }
    }

    /// The currently loaded document. Exposed for tests.
    private(set) var document: MarkdownDocument = .empty {
        didSet { propagateDocument() }
    }

    /// Outline column width constraint (toggled between fixed value and 0).
    private var outlineWidthConstraint: NSLayoutConstraint!

    /// Fixed width applied when the outline is visible.
    private static let outlineWidth: CGFloat = 200

    // MARK: - Init

    init(filePath: URL? = nil) {
        self.filePath = filePath
        self.sourceView = MarkdownSourceView()
        self.previewView = MarkdownPreviewView()
        super.init(frame: .zero)
        setupUI()
        wireToolbarCallbacks()
        wireOutlineCallback()

        if let path = filePath {
            loadFile(path)
        } else {
            showEmptyState()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MarkdownContentView does not support NSCoding")
    }

    deinit {
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    // MARK: - Public API (preserved)

    /// Loads and displays a markdown file. Preserved API.
    func loadFile(_ url: URL) {
        self.filePath = url
        toolbar.fileName = url.lastPathComponent

        guard let rawContent = try? String(contentsOf: url, encoding: .utf8) else {
            let errorText = "Failed to load file: \(url.lastPathComponent)"
            document = MarkdownDocument(
                source: errorText,
                frontmatter: MarkdownFrontmatter(),
                body: errorText,
                parseResult: MarkdownParser().parse(errorText),
                outline: .empty,
                bodyLineOffset: 0
            )
            return
        }

        document = MarkdownDocument.parse(rawContent)
        watchFileChanges(url)
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = CocxyColors.base.cgColor

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)

        outlineView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outlineView)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)

        outlineWidthConstraint = outlineView.widthAnchor.constraint(equalToConstant: Self.outlineWidth)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: MarkdownToolbarView.height),

            outlineView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            outlineView.leadingAnchor.constraint(equalTo: leadingAnchor),
            outlineView.bottomAnchor.constraint(equalTo: bottomAnchor),
            outlineWidthConstraint,

            contentContainer.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: outlineView.trailingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        applyMode()
    }

    private func wireToolbarCallbacks() {
        toolbar.onModeChanged = { [weak self] newMode in
            self?.mode = newMode
        }
        toolbar.onOutlineToggle = { [weak self] in
            guard let self else { return }
            self.isOutlineVisible.toggle()
        }
        toolbar.onReload = { [weak self] in
            guard let self, let path = self.filePath else { return }
            self.loadFile(path)
        }
        toolbar.isOutlineVisible = isOutlineVisible
        toolbar.mode = mode
    }

    private func wireOutlineCallback() {
        outlineView.onSelect = { [weak self] entry in
            self?.scrollToOutlineEntry(entry)
        }
    }

    // MARK: - Mode Switching

    private func applyMode() {
        // Clear current content
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        for arranged in splitContainer.arrangedSubviews {
            splitContainer.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }

        switch mode {
        case .source:
            embed(sourceView, in: contentContainer)
        case .preview:
            embed(previewView, in: contentContainer)
        case .split:
            splitContainer.isVertical = true
            splitContainer.dividerStyle = .thin
            sourceView.translatesAutoresizingMaskIntoConstraints = true
            previewView.translatesAutoresizingMaskIntoConstraints = true
            splitContainer.addArrangedSubview(sourceView)
            splitContainer.addArrangedSubview(previewView)
            embed(splitContainer, in: contentContainer)
        }
    }

    private func embed(_ subview: NSView, in container: NSView) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(subview)
        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: container.topAnchor),
            subview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            subview.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    private func applyOutlineVisibility() {
        outlineWidthConstraint.constant = isOutlineVisible ? Self.outlineWidth : 0
        outlineView.isHidden = !isOutlineVisible
        needsLayout = true
    }

    // MARK: - Document Propagation

    private func propagateDocument() {
        sourceView.document = document
        previewView.document = document
        outlineView.outline = document.outline
    }

    private func showEmptyState() {
        toolbar.fileName = "No file"
        let placeholder = "Drop a .md file here or open one from the Command Palette."
        document = MarkdownDocument(
            source: placeholder,
            frontmatter: MarkdownFrontmatter(),
            body: placeholder,
            parseResult: MarkdownParser().parse(placeholder),
            outline: .empty,
            bodyLineOffset: 0
        )
    }

    // MARK: - Outline Navigation

    private func scrollToOutlineEntry(_ entry: MarkdownOutlineEntry) {
        let sourceLine = document.sourceLine(forBodyLine: entry.sourceLine)
        sourceView.scrollToSourceLine(sourceLine)
        previewView.scrollToHeading(title: entry.title)
    }

    // MARK: - Keyboard Shortcuts

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers ?? ""

        if flags.contains(.command) && !flags.contains(.shift) {
            switch characters {
            case "1": mode = .source; return
            case "2": mode = .preview; return
            case "3": mode = .split; return
            case "r":
                if let path = filePath { loadFile(path) }
                return
            default:
                break
            }
        }
        if flags.contains(.command) && flags.contains(.shift), characters.lowercased() == "o" {
            isOutlineVisible.toggle()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - File Watching

    private func watchFileChanges(_ url: URL) {
        fileMonitor?.cancel()

        let fd = open(url.path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.loadFile(url)
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.fileMonitor = source
    }
}
