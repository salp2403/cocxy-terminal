// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownSearchView.swift - Search panel for finding text across markdown files.

import AppKit
import CocxyMarkdownLib

// MARK: - Search View

/// Search panel embedded in the sidebar that searches across workspace .md files.
///
/// Contains a search field at the top and a table of results below. Each result
/// shows the file name, line number, and matching line text.
@MainActor
final class MarkdownSearchView: NSView, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {

    // MARK: - Properties

    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")

    private var results: [MarkdownSearchResult] = []
    private var searchWorkItem: DispatchWorkItem?
    private var searchGeneration: UInt64 = 0
    private var localizer: AppLocalizer
    private var isSearching = false

    /// Root directory to search in. Changing clears stale results and
    /// re-runs the active query against the new root.
    var rootDirectory: URL? {
        didSet {
            if oldValue != rootDirectory {
                searchWorkItem?.cancel()
                searchGeneration &+= 1
                isSearching = false
                results = []
                statusLabel.stringValue = ""
                tableView.reloadData()
                // Re-run the current query against the new root
                if !searchField.stringValue.isEmpty {
                    scheduleSearch()
                }
            }
        }
    }

    /// Invoked when a result is selected. Provides the file URL and line number.
    var onResultSelected: ((URL, Int) -> Void)?

    // MARK: - Init

    init(localizer: AppLocalizer = AppLocalizer(languagePreference: .system)) {
        self.localizer = localizer
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MarkdownSearchView does not support NSCoding")
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = CocxyColors.mantle.cgColor

        // Search field
        searchField.placeholderString = Self.localizedPlaceholder(using: localizer)
        searchField.font = .systemFont(ofSize: 11)
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchField)

        // Status label
        statusLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        statusLabel.textColor = CocxyColors.subtext0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        // Table
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        column.width = 180
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowSizeStyle = .custom
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)

        scrollView.documentView = tableView

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),

            statusLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        scheduleSearch()
    }

    // MARK: - Search Logic

    private func scheduleSearch() {
        searchWorkItem?.cancel()

        let query = searchField.stringValue
        guard !query.isEmpty, let root = rootDirectory else {
            searchGeneration &+= 1
            isSearching = false
            results = []
            statusLabel.stringValue = ""
            tableView.reloadData()
            return
        }

        searchGeneration &+= 1
        let generation = searchGeneration
        isSearching = true
        statusLabel.stringValue = Self.localizedSearching(using: localizer)

        let workItem = DispatchWorkItem { [weak self] in
            let found = MarkdownFileSearch.search(query: query, in: root)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Discard results from a stale search that was superseded
                guard self.searchGeneration == generation else { return }
                self.isSearching = false
                self.results = found
                self.updateResultStatus()
                self.tableView.reloadData()
            }
        }
        searchWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        searchField.placeholderString = Self.localizedPlaceholder(using: localizer)
        if isSearching {
            statusLabel.stringValue = Self.localizedSearching(using: localizer)
        } else {
            updateResultStatus()
        }
    }

    private func updateResultStatus() {
        guard !searchField.stringValue.isEmpty else {
            statusLabel.stringValue = ""
            return
        }
        if results.isEmpty {
            statusLabel.stringValue = Self.localizedNoResults(using: localizer)
        } else {
            let fileCount = Set(results.map(\.fileName)).count
            statusLabel.stringValue = Self.localizedMatches(
                matches: results.count,
                files: fileCount,
                using: localizer
            )
        }
    }

    static func localizedPlaceholder(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.search.placeholder", fallback: "Search in files...")
    }

    static func localizedSearching(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.search.searching", fallback: "Searching...")
    }

    static func localizedNoResults(using localizer: AppLocalizer) -> String {
        localizer.string("markdown.search.noResults", fallback: "No results")
    }

    static func localizedMatches(matches: Int, files: Int, using localizer: AppLocalizer) -> String {
        let matchSegment = matches == 1 ? "one" : "many"
        let fileSegment = files == 1 ? "oneFile" : "manyFiles"
        let matchFallback = matches == 1 ? "match" : "matches"
        let fileFallback = files == 1 ? "file" : "files"
        let matchKey = "markdown.search.matches.\(matchSegment).\(fileSegment)"
        let fallback = "%d \(matchFallback) in %d \(fileFallback)"
        return String(format: localizer.string(matchKey, fallback: fallback), matches, files)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < results.count else { return nil }
        let result = results[row]

        let identifier = NSUserInterfaceItemIdentifier("SearchResultCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? SearchResultCell
            ?? SearchResultCell(identifier: identifier)

        cell.configure(with: result)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        36
    }

    // MARK: - Actions

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < results.count else { return }
        let result = results[row]
        onResultSelected?(result.fileURL, result.lineNumber)
    }
}

// MARK: - Search Result Cell

@MainActor
private final class SearchResultCell: NSTableCellView {

    private let fileLabel = NSTextField(labelWithString: "")
    private let lineLabel = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SearchResultCell does not support NSCoding")
    }

    private func setupSubviews() {
        fileLabel.font = .systemFont(ofSize: 11, weight: .medium)
        fileLabel.textColor = CocxyColors.text
        fileLabel.lineBreakMode = .byTruncatingTail
        fileLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fileLabel)

        lineLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        lineLabel.textColor = CocxyColors.subtext0
        lineLabel.lineBreakMode = .byTruncatingTail
        lineLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lineLabel)

        NSLayoutConstraint.activate([
            fileLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            fileLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            fileLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            lineLabel.topAnchor.constraint(equalTo: fileLabel.bottomAnchor, constant: 1),
            lineLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            lineLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
    }

    func configure(with result: MarkdownSearchResult) {
        fileLabel.stringValue = "\(result.fileName):\(result.lineNumber)"
        lineLabel.stringValue = result.lineText
    }
}
