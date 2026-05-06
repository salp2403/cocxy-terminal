// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownFileExplorerView.swift - File tree for browsing .md files in a workspace.

import AppKit

// MARK: - File Explorer View

/// NSOutlineView-based file browser that displays markdown files in a directory tree.
///
/// Shows only `.md` and `.markdown` files and the directories that contain them.
/// Clicking a file invokes `onFileSelected(url)` so the content panel can load it.
@MainActor
final class MarkdownFileExplorerView: NSView, NSMenuDelegate {

    // MARK: - Properties

    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private let contextMenu = NSMenu()
    private var dataSource: FileTreeDataSource?
    private var delegateObject: FileTreeDelegate?
    private var localizer: AppLocalizer
    private var pendingRootDirectoryForVisibleLoad: URL?

    /// Invoked when a file is clicked. The URL points to the selected .md file.
    var onFileSelected: ((URL) -> Void)?

    /// Invoked after a file or directory is renamed.
    var onFileRenamed: ((URL, URL) -> Void)?

    /// Invoked after a file or directory is deleted.
    var onFileDeleted: ((URL) -> Void)?

    /// The currently highlighted file path (used to show which file is open).
    var activeFilePath: URL? {
        didSet { outlineView.reloadData() }
    }

    /// Root directory to browse.
    private(set) var rootDirectory: URL?

    internal var rootNodesForTesting: [FileTreeNode] {
        dataSource?.rootNodes ?? []
    }

    // MARK: - Init

    init(localizer: AppLocalizer = AppLocalizer(languagePreference: .system)) {
        self.localizer = localizer
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MarkdownFileExplorerView does not support NSCoding")
    }

    // MARK: - Public API

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            loadPendingRootDirectoryIfNeeded()
        }
    }

    /// Sets the root directory and scans for markdown files.
    func setRootDirectory(_ url: URL, deferUntilVisible: Bool = false) {
        rootDirectory = url
        if deferUntilVisible, window == nil {
            pendingRootDirectoryForVisibleLoad = url
            dataSource?.rootNodes = []
            outlineView.reloadData()
            return
        }
        rebuildTree(from: url)
    }

    private func loadPendingRootDirectoryIfNeeded() {
        guard let pending = pendingRootDirectoryForVisibleLoad else { return }
        pendingRootDirectoryForVisibleLoad = nil
        rebuildTree(from: pending)
    }

    private func rebuildTree(from url: URL) {
        pendingRootDirectoryForVisibleLoad = nil
        let tree = FileTreeNode.buildTree(from: url)
        dataSource?.rootNodes = tree
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        outlineView.tableColumns.first?.title = localized("markdown.explorer.filesColumn", fallback: "Files")
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

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.width = 180
        column.title = localized("markdown.explorer.filesColumn", fallback: "Files")
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.backgroundColor = .clear
        outlineView.rowSizeStyle = .small
        outlineView.indentationPerLevel = 14
        outlineView.allowsEmptySelection = true
        outlineView.target = self
        outlineView.action = #selector(rowClicked)
        contextMenu.delegate = self
        outlineView.menu = contextMenu

        let ds = FileTreeDataSource(rootNodes: [])
        outlineView.dataSource = ds
        dataSource = ds

        let del = FileTreeDelegate(activePathProvider: { [weak self] in self?.activeFilePath })
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

    // MARK: - Actions

    @objc private func rowClicked() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileTreeNode else { return }
        if !node.isDirectory {
            onFileSelected?(node.url)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let node = contextualNode() else { return }

        let rename = NSMenuItem(
            title: localized("markdown.explorer.menu.rename", fallback: "Rename"),
            action: #selector(renameContextNode),
            keyEquivalent: ""
        )
        rename.target = self
        menu.addItem(rename)

        let delete = NSMenuItem(
            title: localized("markdown.explorer.menu.moveToTrash", fallback: "Move to Trash"),
            action: #selector(deleteContextNode),
            keyEquivalent: ""
        )
        delete.target = self
        menu.addItem(delete)

        menu.addItem(.separator())

        let reveal = NSMenuItem(
            title: localized("markdown.explorer.menu.revealInFinder", fallback: "Reveal in Finder"),
            action: #selector(revealContextNode),
            keyEquivalent: ""
        )
        reveal.target = self
        menu.addItem(reveal)

        if node.isDirectory {
            rename.title = localized("markdown.explorer.menu.renameFolder", fallback: "Rename Folder")
            delete.title = localized("markdown.explorer.menu.moveFolderToTrash", fallback: "Move Folder to Trash")
        }
    }

    internal func renameItem(at url: URL, to newName: String) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return url }

        let newURL = url.deletingLastPathComponent().appendingPathComponent(trimmed)
        guard newURL != url else { return url }

        try FileManager.default.moveItem(at: url, to: newURL)
        if activeFilePath == url {
            activeFilePath = newURL
        }
        refreshTree()
        onFileRenamed?(url, newURL)
        return newURL
    }

    internal func deleteItem(at url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        if activeFilePath == url {
            activeFilePath = nil
        }
        refreshTree()
        onFileDeleted?(url)
    }

    internal func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func refreshTree() {
        if let rootDirectory {
            setRootDirectory(rootDirectory)
        }
    }

    private func contextualNode() -> FileTreeNode? {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? FileTreeNode
    }

    @objc private func renameContextNode() {
        guard let node = contextualNode() else { return }

        let alert = NSAlert()
        let copy = Self.localizedRenameCopy(localizer: localizer, itemName: node.name)
        alert.messageText = copy.messageText
        alert.informativeText = copy.informativeText
        alert.alertStyle = .informational
        alert.addButton(withTitle: copy.primaryButton)
        alert.addButton(withTitle: copy.secondaryButton)

        let field = NSTextField(string: node.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            _ = try renameItem(at: node.url, to: field.stringValue)
        } catch {
            NSLog("MarkdownFileExplorerView rename failed: %@", String(describing: error))
        }
    }

    @objc private func deleteContextNode() {
        guard let node = contextualNode() else { return }

        let alert = NSAlert()
        let copy = Self.localizedMoveToTrashCopy(localizer: localizer, itemName: node.name)
        alert.messageText = copy.messageText
        alert.informativeText = copy.informativeText
        alert.alertStyle = .warning
        alert.addButton(withTitle: copy.primaryButton)
        alert.addButton(withTitle: copy.secondaryButton)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try deleteItem(at: node.url)
        } catch {
            NSLog("MarkdownFileExplorerView delete failed: %@", String(describing: error))
        }
    }

    @objc private func revealContextNode() {
        guard let node = contextualNode() else { return }
        revealInFinder(node.url)
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }

    static func localizedRenameCopy(localizer: AppLocalizer, itemName: String) -> AppAlertCopy {
        AppAlertCopy(
            messageText: String(
                format: localizer.string("markdown.explorer.rename.title", fallback: "Rename \"%@\""),
                itemName
            ),
            informativeText: localizer.string("markdown.explorer.rename.message", fallback: "Enter a new name."),
            primaryButton: localizer.string("markdown.explorer.rename.button", fallback: "Rename"),
            secondaryButton: localizer.string("common.cancel", fallback: "Cancel")
        )
    }

    static func localizedMoveToTrashCopy(localizer: AppLocalizer, itemName: String) -> AppAlertCopy {
        AppAlertCopy(
            messageText: String(
                format: localizer.string("markdown.explorer.trash.title", fallback: "Move \"%@\" to Trash?"),
                itemName
            ),
            informativeText: localizer.string(
                "markdown.explorer.trash.message",
                fallback: "This can be undone from the Trash."
            ),
            primaryButton: localizer.string("markdown.explorer.trash.button", fallback: "Move to Trash"),
            secondaryButton: localizer.string("common.cancel", fallback: "Cancel")
        )
    }
}

// MARK: - File Tree Node

/// A node in the file tree. Either a directory (with children) or a file.
final class FileTreeNode {
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileTreeNode]

    init(url: URL, name: String, isDirectory: Bool, children: [FileTreeNode] = []) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.children = children
    }

    struct BuildOptions: Sendable {
        var maxScannedEntries: Int
        var maxMarkdownFiles: Int
        var maxDirectoryDepth: Int
        var skippedDirectoryNames: Set<String>

        static let `default` = BuildOptions(
            maxScannedEntries: 4_000,
            maxMarkdownFiles: 800,
            maxDirectoryDepth: 8,
            skippedDirectoryNames: [
                "node_modules",
                "build",
                "dist",
                "target",
                "deriveddata",
                "pods",
                "carthage",
                "vendor",
                "venv",
                ".venv",
                "__pycache__"
            ]
        )
    }

    /// Builds a filtered tree from a root directory, keeping only directories
    /// that contain .md/.markdown files (recursively) and the files themselves.
    static func buildTree(from root: URL, options: BuildOptions = .default) -> [FileTreeNode] {
        let fm = FileManager.default
        let root = root.standardizedFileURL
        var isRootDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isRootDirectory),
              isRootDirectory.boolValue,
              let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
              ) else { return [] }

        var markdownFiles: [URL] = []
        var scannedEntries = 0

        while let next = enumerator.nextObject() as? URL {
            scannedEntries += 1
            if scannedEntries > options.maxScannedEntries {
                break
            }

            let url = next.standardizedFileURL
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                if values?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            if values?.isDirectory == true {
                if shouldSkipDirectory(url, root: root, options: options) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile != false,
                  isMarkdownFile(url) else {
                continue
            }

            markdownFiles.append(url)
            if markdownFiles.count >= options.maxMarkdownFiles {
                break
            }
        }

        return sortedTree(from: markdownFiles, root: root)
    }

    private static func isMarkdownFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    private static func shouldSkipDirectory(
        _ url: URL,
        root: URL,
        options: BuildOptions
    ) -> Bool {
        if directoryDepth(url, relativeTo: root) >= options.maxDirectoryDepth {
            return true
        }

        if options.skippedDirectoryNames.contains(url.lastPathComponent.lowercased()) {
            return true
        }

        let homeLibrary = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .standardizedFileURL
        if url == homeLibrary {
            return true
        }

        return false
    }

    private static func sortedTree(from markdownFiles: [URL], root: URL) -> [FileTreeNode] {
        var nodes: [FileTreeNode] = []
        for file in markdownFiles {
            let components = relativeComponents(for: file, root: root)
            guard !components.isEmpty else { continue }
            insertFile(
                file,
                components: components,
                root: root,
                into: &nodes
            )
        }
        return sort(nodes)
    }

    private static func insertFile(
        _ file: URL,
        components: [String],
        root: URL,
        into nodes: inout [FileTreeNode]
    ) {
        guard let first = components.first else { return }
        if components.count == 1 {
            nodes.append(FileTreeNode(
                url: file,
                name: first,
                isDirectory: false
            ))
            return
        }

        let directoryURL = root.appendingPathComponent(first, isDirectory: true)
        let directoryNode: FileTreeNode
        if let existing = nodes.first(where: { $0.isDirectory && $0.name == first }) {
            directoryNode = existing
        } else {
            directoryNode = FileTreeNode(
                url: directoryURL,
                name: first,
                isDirectory: true
            )
            nodes.append(directoryNode)
        }

        insertFile(
            file,
            components: Array(components.dropFirst()),
            root: directoryURL,
            into: &directoryNode.children
        )
    }

    private static func relativeComponents(for url: URL, root: URL) -> [String] {
        let rootComponents = root.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.count > rootComponents.count else { return [] }
        return Array(urlComponents.dropFirst(rootComponents.count))
    }

    private static func directoryDepth(_ url: URL, relativeTo root: URL) -> Int {
        relativeComponents(for: url, root: root).count
    }

    private static func sort(_ nodes: [FileTreeNode]) -> [FileTreeNode] {
        let sortedNodes = nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        for node in sortedNodes where node.isDirectory {
            node.children = sort(node.children)
        }
        return sortedNodes
    }
}

// MARK: - Data Source

@MainActor
private final class FileTreeDataSource: NSObject, NSOutlineViewDataSource {

    var rootNodes: [FileTreeNode]

    init(rootNodes: [FileTreeNode]) {
        self.rootNodes = rootNodes
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let node = item as? FileTreeNode {
            return node.children.count
        }
        return rootNodes.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? FileTreeNode {
            return node.children[index]
        }
        return rootNodes[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileTreeNode)?.isDirectory ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        (item as? FileTreeNode)?.name
    }
}

// MARK: - Delegate

@MainActor
private final class FileTreeDelegate: NSObject, NSOutlineViewDelegate {

    private let activePathProvider: () -> URL?

    init(activePathProvider: @escaping () -> URL?) {
        self.activePathProvider = activePathProvider
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("MarkdownFileCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
            ?? makeNewCell(identifier: identifier)

        guard let node = item as? FileTreeNode else { return cell }

        cell.textField?.stringValue = node.name

        let isActive = node.url == activePathProvider()
        cell.textField?.textColor = isActive ? CocxyColors.blue : CocxyColors.text
        cell.textField?.font = isActive
            ? .systemFont(ofSize: 12, weight: .semibold)
            : .systemFont(ofSize: 12, weight: .regular)

        cell.imageView?.image = iconForNode(node)
        cell.imageView?.contentTintColor = node.isDirectory
            ? CocxyColors.yellow
            : (isActive ? CocxyColors.blue : CocxyColors.subtext0)

        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        22
    }

    private func makeNewCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(imageView)
        cell.imageView = imageView

        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = CocxyColors.text
        label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label)
        cell.textField = label

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 14),
            imageView.heightAnchor.constraint(equalToConstant: 14),

            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])

        return cell
    }

    private func iconForNode(_ node: FileTreeNode) -> NSImage? {
        let name = node.isDirectory ? "folder" : "doc.text"
        return NSImage(systemSymbolName: name, accessibilityDescription: node.name)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
    }
}
