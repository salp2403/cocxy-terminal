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

    /// Workspace root directory for the file explorer and multi-file search.
    /// Set once at creation time by the caller. If nil, falls back to the
    /// file's parent directory.
    private(set) var workspaceDirectory: URL?

    // MARK: - Properties (new)

    private let toolbar = MarkdownToolbarView()
    private let sidebar = MarkdownSidebarView()
    let sourceView: MarkdownSourceView
    let previewView: MarkdownPreviewView
    let diffView = MarkdownDiffView()
    private let splitContainer = NSSplitView()
    let contentContainer = NSView()
    let statusBar = MarkdownStatusBarView()

    /// Whether the diff view is currently shown instead of the normal content.
    var isDiffVisible = false

    /// Whether the blame view is currently shown instead of the normal content.
    var isBlameVisible = false

    /// Monotonically increasing counter invalidating in-flight git requests.
    /// Each call to toggleBlame/toggleDiff bumps this; callbacks whose captured
    /// generation doesn't match are discarded.
    var gitRequestGeneration: UInt64 = 0

    /// File-system watcher that reloads the document when the source file
    /// changes on disk.
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var pendingSaveWorkItem: DispatchWorkItem?

    /// Current view mode. Setting updates the displayed subview and toolbar.
    var mode: MarkdownViewMode = .source {
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

    /// Sidebar column width constraint (toggled between fixed value and 0).
    private var sidebarWidthConstraint: NSLayoutConstraint!

    /// Fixed width applied when the sidebar is visible.
    private static let sidebarWidth: CGFloat = 210

    // MARK: - Init

    /// Image file extensions accepted for drag-and-drop insertion.
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "tiff"]

    init(filePath: URL? = nil, workspaceDirectory: URL? = nil) {
        self.filePath = filePath
        self.workspaceDirectory = workspaceDirectory
        self.sourceView = MarkdownSourceView()
        self.previewView = MarkdownPreviewView()
        super.init(frame: .zero)
        setupUI()
        wireToolbarCallbacks()
        wireOutlineCallback()
        wireSourceCallbacks()
        registerForDraggedTypes([.fileURL])

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

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        if newSuperview == nil {
            tearDownTransientState()
        }
    }

    deinit {}

    private func tearDownTransientState() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    // MARK: - Public API (preserved)

    /// Loads and displays a markdown file. Preserved API.
    func loadFile(_ url: URL) {
        self.filePath = url
        toolbar.fileName = url.lastPathComponent

        // Invalidate any in-flight git blame/diff from the previous file
        gitRequestGeneration &+= 1

        // If blame or diff was visible, return to normal content mode
        if isBlameVisible || isDiffVisible {
            isBlameVisible = false
            isDiffVisible = false
            applyMode()
        }

        // Determine the sidebar root. Use the workspace directory if the file
        // is inside it; otherwise fall back to the file's parent directory so
        // files opened from outside the workspace still get a useful tree.
        let fileDir = url.deletingLastPathComponent()
        let effectiveRoot: URL
        if let wsDir = workspaceDirectory,
           url.standardizedFileURL.path.hasPrefix(wsDir.standardizedFileURL.path + "/") {
            effectiveRoot = wsDir
        } else {
            effectiveRoot = fileDir
        }
        if sidebar.fileExplorer.rootDirectory != effectiveRoot {
            sidebar.fileExplorer.setRootDirectory(effectiveRoot)
            sidebar.searchView.rootDirectory = effectiveRoot
        }
        sidebar.fileExplorer.activeFilePath = url
        previewView.baseDirectory = url.deletingLastPathComponent()

        reloadFromDisk(url, force: true)
    }

    internal var sourceViewForTesting: MarkdownSourceView { sourceView }

    // MARK: - Loading / Saving

    private func reloadFromDisk(_ url: URL, force: Bool) {
        // Concurrency guard: if a save is in flight, the file watcher event
        // was triggered by our own write. Skip the reload to avoid
        // overwriting in-progress local edits with the file we just saved.
        if !force, pendingSaveWorkItem != nil {
            return
        }

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

        if force || rawContent != document.source {
            document = MarkdownDocument.parse(rawContent)
        }
        watchFileChanges(url)
    }

    private func scheduleSave(for source: String) {
        guard let filePath else { return }
        pendingSaveWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.saveSource(source, to: filePath)
        }
        pendingSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func saveSource(_ source: String, to url: URL) {
        do {
            try source.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("MarkdownContentView failed to save %@: %@", url.path, String(describing: error))
        }
        // Clear the work item after save completes so future file watcher
        // events from external editors are not blocked by the guard.
        pendingSaveWorkItem = nil
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = CocxyColors.base.cgColor

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)

        sidebar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sidebar)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)

        statusBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusBar)

        sidebarWidthConstraint = sidebar.widthAnchor.constraint(equalToConstant: Self.sidebarWidth)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: MarkdownToolbarView.height),

            statusBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: MarkdownStatusBarView.height),

            sidebar.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            sidebarWidthConstraint,

            contentContainer.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: statusBar.topAnchor)
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
        toolbar.onBlameToggle = { [weak self] in
            self?.toggleBlame()
        }
        toolbar.onDiffToggle = { [weak self] in
            self?.toggleDiff()
        }
        toolbar.onExportPDF = { [weak self] in
            self?.exportPDF()
        }
        toolbar.onExportHTML = { [weak self] in
            self?.exportHTML()
        }
        toolbar.onExportSlides = { [weak self] in
            self?.exportSlides()
        }
        toolbar.isOutlineVisible = isOutlineVisible
        toolbar.mode = mode
    }

    private func wireOutlineCallback() {
        sidebar.outlineView.onSelect = { [weak self] entry in
            self?.scrollToOutlineEntry(entry)
        }
        sidebar.fileExplorer.onFileSelected = { [weak self] url in
            self?.loadFile(url)
        }
        sidebar.searchView.onResultSelected = { [weak self] url, lineNumber in
            guard let self else { return }
            if self.filePath != url {
                self.loadFile(url)
            }
            self.sourceView.scrollToSourceLine(lineNumber)
            if self.mode == .preview {
                self.mode = .split
            }
        }
    }

    private func wireSourceCallbacks() {
        sourceView.onSourceChanged = { [weak self] source in
            self?.handleSourceEdited(source)
        }
        sourceView.onScrollChanged = { [weak self] fraction in
            guard let self, self.mode == .split else { return }
            self.previewView.scrollToFraction(fraction)
        }
        sourceView.onShortcutCommand = { [weak self] command in
            self?.handleSourceShortcut(command) ?? false
        }
    }

    // MARK: - Mode Switching

    func applyMode() {
        isDiffVisible = false
        isBlameVisible = false
        gitRequestGeneration &+= 1

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

    func embed(_ subview: NSView, in container: NSView) {
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
        sidebarWidthConstraint.constant = isOutlineVisible ? Self.sidebarWidth : 0
        sidebar.isHidden = !isOutlineVisible
        needsLayout = true
    }

    // MARK: - Document Propagation

    private func propagateDocument() {
        sourceView.document = document
        previewView.document = document
        sidebar.outlineView.outline = document.outline
        sidebar.fileExplorer.activeFilePath = filePath
        statusBar.wordCount = MarkdownWordCount.count(body: document.body)
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

    private func handleSourceEdited(_ source: String) {
        document = MarkdownDocument.parse(source)
        scheduleSave(for: source)
    }

    private func handleSourceShortcut(_ command: MarkdownSourceShortcutCommand) -> Bool {
        switch command {
        case .setMode(let newMode):
            mode = newMode
            return true
        case .toggleOutline:
            isOutlineVisible.toggle()
            return true
        case .reload:
            if let path = filePath {
                reloadFromDisk(path, force: true)
                return true
            }
            return false
        }
    }

    // MARK: - Outline Navigation

    private func scrollToOutlineEntry(_ entry: MarkdownOutlineEntry) {
        let sourceLine = document.sourceLine(forBodyLine: entry.sourceLine)
        sourceView.scrollToSourceLine(sourceLine)
        previewView.scrollToHeading(title: entry.title)
    }

    // MARK: - Keyboard Shortcuts

    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleGlobalShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleGlobalShortcut(event) {
            return
        }
        super.keyDown(with: event)
    }

    private func handleGlobalShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = (event.charactersIgnoringModifiers ?? "").lowercased()

        if flags.contains(.command) && !flags.contains(.shift) {
            switch characters {
            case "1":
                mode = .source
                return true
            case "2":
                mode = .preview
                return true
            case "3":
                mode = .split
                return true
            case "r":
                if let path = filePath {
                    reloadFromDisk(path, force: true)
                    return true
                }
                return false
            default:
                break
            }
        }
        if flags.contains(.command) && flags.contains(.shift) {
            switch characters {
            case "o":
                isOutlineVisible.toggle()
                return true
            case "e":
                exportPDF()
                return true
            case "h":
                exportHTML()
                return true
            case "s":
                exportSlides()
                return true
            default:
                break
            }
        }
        return false
    }

    // MARK: - File Watching

    private func watchFileChanges(_ url: URL) {
        fileMonitor?.cancel()

        let fd = open(url.path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.rename) || flags.contains(.delete) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.reloadFromDisk(url, force: false)
                }
            } else {
                self.reloadFromDisk(url, force: false)
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.fileMonitor = source
    }
}
