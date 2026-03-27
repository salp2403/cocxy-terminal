// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserHistoryView.swift - Browsing history panel with search and date grouping.

import SwiftUI

// MARK: - History Clear Range

/// Time ranges for the "Clear History" action.
enum HistoryClearRange: String, CaseIterable, Identifiable {
    case lastHour = "Last Hour"
    case today = "Today"
    case all = "All History"

    var id: String { rawValue }
}

// MARK: - Browser History View

/// A panel showing browsing history grouped by date with full-text search.
///
/// ## Layout
///
/// ```
/// +-- History ----------------------------+
/// |                                     X |
/// +---------------------------------------+
/// | Search history...                     |
/// +---------------------------------------+
/// | Today                                 |
/// |   GitHub - salp2403           12:45   |
/// |   localhost:3000              12:30   |
/// |   Stack Overflow              11:15   |
/// | Yesterday                             |
/// |   MDN - Array.map            18:20   |
/// |   npmjs.com                  16:45   |
/// +---------------------------------------+
/// | [Clear History ...]                   |
/// +---------------------------------------+
/// ```
///
/// ## Features
///
/// - Full-text search via ``BrowserHistoryStoring/search(query:profileID:limit:)``.
/// - Entries grouped by date with labels ("Today", "Yesterday", date).
/// - Click to navigate the browser to a history entry's URL.
/// - Clear history with time range options.
/// - Filters by the active browser profile.
///
/// - SeeAlso: ``BrowserHistoryStoring`` for the data layer.
/// - SeeAlso: ``HistoryEntry`` for the entry model.
/// - SeeAlso: ``DateGroup`` for the date grouping model.
struct BrowserHistoryView: View {

    /// The history store providing search and date-grouped queries.
    let historyStore: BrowserHistoryStoring

    /// The active profile ID for filtering entries.
    let activeProfileID: UUID?

    /// Called when the user clicks an entry to navigate to its URL.
    let onNavigate: (String) -> Void

    /// Called when the user taps the close button.
    let onDismiss: () -> Void

    /// Search query text.
    @State private var searchText: String = ""

    /// History groups for the non-search view.
    @State private var dateGroups: [DateGroup<HistoryEntry>] = []

    /// Search results when a query is active.
    @State private var searchResults: [HistoryEntry] = []

    /// Whether the clear confirmation alert is showing.
    @State private var showClearConfirmation: Bool = false

    /// The selected clear range.
    @State private var selectedClearRange: HistoryClearRange = .all

    /// Maximum number of entries to load.
    private let historyLimit: Int = 500

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            searchBar
            Divider()
            historyContent
            Divider()
            footerView
        }
        .background(
            ZStack {
                Color(nsColor: CocxyColors.mantle)
                VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Browsing History")
        .onAppear { loadHistory() }
        .onChange(of: searchText) { performSearch() }
        .alert("Clear History", isPresented: $showClearConfirmation) {
            Button("Clear", role: .destructive) { clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \(selectedClearRange.rawValue.lowercased()) of browsing history.")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("History")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .accessibilityLabel("Close history")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))

            TextField("Search history...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.text))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: CocxyColors.surface0).opacity(0.5))
    }

    // MARK: - Content

    @ViewBuilder
    private var historyContent: some View {
        if isSearchActive {
            searchResultsListView
        } else {
            groupedHistoryListView
        }
    }

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Search Results

    private var searchResultsListView: some View {
        Group {
            if searchResults.isEmpty {
                historyEmptyState(
                    symbol: "magnifyingglass",
                    title: "No results",
                    detail: "No history entries match your search."
                )
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(searchResults, id: \.id) { entry in
                            historyEntryRow(entry)
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Grouped History

    private var groupedHistoryListView: some View {
        Group {
            if dateGroups.isEmpty {
                historyEmptyState(
                    symbol: "clock",
                    title: "No history",
                    detail: "Pages you visit will appear here."
                )
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(dateGroups) { group in
                            dateGroupHeader(group.label)

                            ForEach(group.entries, id: \.id) { entry in
                                historyEntryRow(entry)
                                Divider()
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
            }
        }
    }

    private func dateGroupHeader(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    // MARK: - Entry Row

    private func historyEntryRow(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title ?? displayHost(entry.url))
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
                    .lineLimit(1)

                Text(entry.url)
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { onNavigate(entry.url) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title ?? entry.url)")
        .accessibilityHint("Navigate to this page")
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Menu {
                ForEach(HistoryClearRange.allCases) { range in
                    Button(range.rawValue) {
                        selectedClearRange = range
                        showClearConfirmation = true
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                    Text("Clear History")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(Color(nsColor: CocxyColors.red))
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Clear browsing history")

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private func historyEmptyState(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Data Loading

    private func loadHistory() {
        dateGroups = (try? historyStore.groupedByDate(
            profileID: activeProfileID,
            limit: historyLimit
        )) ?? []
    }

    private func performSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        searchResults = (try? historyStore.search(
            query: trimmed,
            profileID: activeProfileID,
            limit: historyLimit
        )) ?? []
    }

    private func clearHistory() {
        let now = Date()
        let calendar = Calendar.current

        switch selectedClearRange {
        case .lastHour:
            let oneHourAgo = calendar.date(byAdding: .hour, value: -1, to: now) ?? now
            try? historyStore.deleteByDateRange(from: oneHourAgo, to: now, profileID: activeProfileID)

        case .today:
            let startOfDay = calendar.startOfDay(for: now)
            try? historyStore.deleteByDateRange(from: startOfDay, to: now, profileID: activeProfileID)

        case .all:
            try? historyStore.deleteAll(profileID: activeProfileID)
        }

        loadHistory()
        searchResults = []
    }

    // MARK: - Formatting

    /// Extracts the host from a URL string for display when no title is available.
    private func displayHost(_ urlString: String) -> String {
        URL(string: urlString)?.host ?? urlString
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
