// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultSidebarViewModel.swift - Presentation state for the visual Vault pane.

import Combine
import Foundation
import CocxyVault

enum VaultSidebarSectionKind: Equatable, Sendable {
    case all
    case pinned
    case recent
    case older
    case agent(String)
    case workspace(String)
    case date(String)
}

struct VaultSidebarCard: Identifiable, Equatable, Sendable {
    let id: String
    let session: VaultSession
    let title: String
    let preview: String
    let workspaceDisplay: String
    let ageText: String
    let isPinned: Bool
    let highlights: [VaultSearchHighlight]
    let activitySparkline: [Double]
    let accessibilityLabel: String
    let accessibilityHint: String
}

struct VaultSidebarSection: Identifiable, Equatable, Sendable {
    let id: String
    let kind: VaultSidebarSectionKind
    let title: String
    let cards: [VaultSidebarCard]
    let isCollapsed: Bool
}

struct VaultWorkspaceSuggestion: Equatable, Sendable {
    let workspaceDisplay: String
    let matchingSessionCount: Int
}

@MainActor
final class VaultSidebarViewModel: ObservableObject {
    @Published private(set) var sessions: [VaultSession] = []
    @Published private(set) var filteredSessions: [VaultSession] = []
    @Published private(set) var cards: [VaultSidebarCard] = []
    @Published private(set) var groupSections: [VaultSidebarSection] = []
    @Published var searchQuery: String = ""
    @Published private(set) var selectedAgents: Set<VaultAgentID> = []
    @Published var sortOrder: VaultSortOrder {
        didSet {
            preferences.sortOrder = sortOrder
            applyLocalFilters()
        }
    }
    @Published var groupBy: VaultGroupBy {
        didSet {
            preferences.groupBy = groupBy
            rebuildPresentation()
        }
    }
    @Published private(set) var pinnedSessionIDs: Set<String>
    @Published private(set) var isSearching = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedSessionIDs: Set<String> = []
    @Published var widthMode: VaultSidebarWidthMode {
        didSet { preferences.widthMode = widthMode }
    }
    @Published var isOnboardingVisible: Bool

    private let store: any VaultSessionStoring
    private let searchIndex: any VaultSearchIndexing
    private let preferences: VaultSidebarPreferences
    private let clock: () -> Date
    private let notificationCenter: NotificationCenter
    private var highlightsBySessionID: [String: [VaultSearchHighlight]] = [:]
    private var selectionAnchorID: String?
    private var storeObserver: NSObjectProtocol?
    private var activeWorkspacePath: String?

    init(
        store: any VaultSessionStoring,
        searchIndex: any VaultSearchIndexing,
        preferences: VaultSidebarPreferences = VaultSidebarPreferences(),
        notificationCenter: NotificationCenter = .default,
        clock: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.searchIndex = searchIndex
        self.preferences = preferences
        self.clock = clock
        self.notificationCenter = notificationCenter
        self.sortOrder = preferences.sortOrder
        self.groupBy = preferences.groupBy
        self.pinnedSessionIDs = preferences.pinnedSessionIDs
        self.widthMode = preferences.widthMode
        self.isOnboardingVisible = !preferences.hasSeenOnboarding
        installStoreObserver()
    }

    deinit {
        MainActor.assumeIsolated {
            if let storeObserver {
                notificationCenter.removeObserver(storeObserver)
            }
        }
    }

    func loadSessions() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loaded = try store.loadSessions()
            if let concreteIndex = searchIndex as? VaultSearchIndex {
                try concreteIndex.rebuild(sessions: loaded)
            } else {
                try searchIndex.rebuild()
                for session in loaded {
                    try searchIndex.indexSession(session)
                }
            }
            sessions = sortSessions(loaded)
            applyLocalFilters()
        } catch {
            errorMessage = error.localizedDescription
            sessions = []
            filteredSessions = []
            cards = []
            groupSections = []
        }
    }

    func search(query: String) async {
        searchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            highlightsBySessionID = [:]
            applyLocalFilters()
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            let loadedIDs = Set(sessions.map(\.id))
            let filters = VaultSearchFilters(
                agentIDs: selectedAgents,
                pinnedSessionIDs: pinnedSessionIDs
            )
            let results = try searchIndex.search(query: trimmed, filters: filters)
                .filter { loadedIDs.contains($0.session.id) }
            highlightsBySessionID = Dictionary(uniqueKeysWithValues: results.map { ($0.session.id, $0.highlights) })
            filteredSessions = sortSessions(results.map(\.session))
            rebuildPresentation()
        } catch {
            errorMessage = error.localizedDescription
            filteredSessions = []
            cards = []
            groupSections = []
        }
    }

    func retryLoad() {
        Task { await loadSessions() }
    }

    var selectedSessions: [VaultSession] {
        filteredSessions.filter { selectedSessionIDs.contains($0.id) }
    }

    var workspaceSuggestion: VaultWorkspaceSuggestion? {
        guard let activeWorkspacePath,
              !activeWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let matching = sessions.filter {
            Self.standardizedPath($0.workingDirectory) == Self.standardizedPath(activeWorkspacePath)
        }
        guard !matching.isEmpty else { return nil }
        return VaultWorkspaceSuggestion(
            workspaceDisplay: URL(fileURLWithPath: activeWorkspacePath).lastPathComponent,
            matchingSessionCount: matching.count
        )
    }

    func setActiveWorkspacePath(_ path: String?) {
        activeWorkspacePath = path
        rebuildPresentation()
    }

    func toggleAgentFilter(_ agentID: VaultAgentID) {
        if selectedAgents.contains(agentID) {
            selectedAgents.remove(agentID)
        } else {
            selectedAgents.insert(agentID)
        }
        refreshAfterFilterChange()
    }

    func clearAgentFilters() {
        selectedAgents = []
        refreshAfterFilterChange()
    }

    func pin(session: VaultSession) {
        pinnedSessionIDs.insert(session.id)
        preferences.pinnedSessionIDs = pinnedSessionIDs
        rebuildPresentation()
    }

    func unpin(session: VaultSession) {
        pinnedSessionIDs.remove(session.id)
        preferences.pinnedSessionIDs = pinnedSessionIDs
        rebuildPresentation()
    }

    func pinSelected() {
        pinnedSessionIDs.formUnion(selectedSessionIDs)
        preferences.pinnedSessionIDs = pinnedSessionIDs
        rebuildPresentation()
    }

    func unpinSelected() {
        pinnedSessionIDs.subtract(selectedSessionIDs)
        preferences.pinnedSessionIDs = pinnedSessionIDs
        rebuildPresentation()
    }

    func delete(session: VaultSession) async throws {
        let remaining = sessions.filter { $0.id != session.id }
        try store.saveSessions(remaining)
        try searchIndex.removeSession(id: session.id)
        pinnedSessionIDs.remove(session.id)
        preferences.pinnedSessionIDs = pinnedSessionIDs
        selectedSessionIDs.remove(session.id)
        if selectionAnchorID == session.id {
            selectionAnchorID = selectedSessionIDs.first
        }
        sessions = sortSessions(remaining)
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            applyLocalFilters()
        } else {
            await search(query: searchQuery)
        }
    }

    func deleteSelected() async throws {
        guard !selectedSessionIDs.isEmpty else { return }
        let deletedIDs = selectedSessionIDs
        let remaining = sessions.filter { !deletedIDs.contains($0.id) }
        try store.saveSessions(remaining)
        for id in deletedIDs {
            try searchIndex.removeSession(id: id)
        }
        pinnedSessionIDs.subtract(deletedIDs)
        preferences.pinnedSessionIDs = pinnedSessionIDs
        selectedSessionIDs = []
        selectionAnchorID = nil
        sessions = sortSessions(remaining)
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            applyLocalFilters()
        } else {
            await search(query: searchQuery)
        }
    }

    func toggleSelection(_ sessionID: String) {
        if selectedSessionIDs.contains(sessionID) {
            selectedSessionIDs.remove(sessionID)
        } else {
            selectedSessionIDs.insert(sessionID)
            selectionAnchorID = sessionID
        }
        rebuildPresentation()
    }

    func selectRange(to sessionID: String) {
        let orderedIDs = filteredSessions.map(\.id)
        guard let targetIndex = orderedIDs.firstIndex(of: sessionID) else { return }
        let anchor = selectionAnchorID ?? selectedSessionIDs.first ?? sessionID
        guard let anchorIndex = orderedIDs.firstIndex(of: anchor) else { return }
        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedSessionIDs.formUnion(orderedIDs[bounds])
        rebuildPresentation()
    }

    func selectAllVisible() {
        selectedSessionIDs = Set(filteredSessions.map(\.id))
        selectionAnchorID = filteredSessions.first?.id
        rebuildPresentation()
    }

    func clearSelection() {
        selectedSessionIDs = []
        selectionAnchorID = nil
        rebuildPresentation()
    }

    func cycleWidthMode() {
        widthMode = widthMode.next
    }

    func dismissOnboarding() {
        preferences.hasSeenOnboarding = true
        isOnboardingVisible = false
    }

    private func installStoreObserver() {
        storeObserver = notificationCenter.addObserver(
            forName: VaultSessionStore.sessionsDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.loadSessions()
            }
        }
    }

    private func refreshAfterFilterChange() {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            applyLocalFilters()
        } else {
            Task { await search(query: searchQuery) }
        }
    }

    private func applyLocalFilters() {
        let filtered = sessions.filter { session in
            selectedAgents.isEmpty || selectedAgents.contains(session.agentID)
        }
        filteredSessions = sortSessions(filtered)
        highlightsBySessionID = [:]
        rebuildPresentation()
    }

    private func rebuildPresentation() {
        cards = filteredSessions.map(makeCard(for:))
        groupSections = makeSections(from: cards)
    }

    private func sortSessions(_ input: [VaultSession]) -> [VaultSession] {
        input.sorted { lhs, rhs in
            switch sortOrder {
            case .mostRecent:
                if lhs.lastSeenAt != rhs.lastSeenAt { return lhs.lastSeenAt > rhs.lastSeenAt }
            case .oldest:
                if lhs.lastSeenAt != rhs.lastSeenAt { return lhs.lastSeenAt < rhs.lastSeenAt }
            case .alphabetical:
                let lhsTitle = lhs.agentDisplayName + lhs.sessionID
                let rhsTitle = rhs.agentDisplayName + rhs.sessionID
                if lhsTitle != rhsTitle { return lhsTitle < rhsTitle }
            case .agentThenRecent:
                if lhs.agentDisplayName != rhs.agentDisplayName { return lhs.agentDisplayName < rhs.agentDisplayName }
                if lhs.lastSeenAt != rhs.lastSeenAt { return lhs.lastSeenAt > rhs.lastSeenAt }
            case .workspaceThenRecent:
                let lhsWorkspace = workspaceDisplay(for: lhs)
                let rhsWorkspace = workspaceDisplay(for: rhs)
                if lhsWorkspace != rhsWorkspace { return lhsWorkspace < rhsWorkspace }
                if lhs.lastSeenAt != rhs.lastSeenAt { return lhs.lastSeenAt > rhs.lastSeenAt }
            }
            return lhs.id < rhs.id
        }
    }

    private func makeSections(from cards: [VaultSidebarCard]) -> [VaultSidebarSection] {
        switch groupBy {
        case .none:
            return cards.isEmpty ? [] : [
                VaultSidebarSection(id: "all", kind: .all, title: "All", cards: cards, isCollapsed: false),
            ]
        case .pinFirst:
            let pinned = cards.filter(\.isPinned)
            let unpinned = cards.filter { !$0.isPinned }
            let recentCutoff = clock().addingTimeInterval(-7 * 86_400)
            let recent = unpinned.filter { $0.session.lastSeenAt >= recentCutoff }
            let older = unpinned.filter { $0.session.lastSeenAt < recentCutoff }
            return [
                pinned.isEmpty ? nil : VaultSidebarSection(id: "pinned", kind: .pinned, title: "Pinned", cards: pinned, isCollapsed: false),
                recent.isEmpty ? nil : VaultSidebarSection(id: "recent", kind: .recent, title: "Recent", cards: recent, isCollapsed: false),
                older.isEmpty ? nil : VaultSidebarSection(id: "older", kind: .older, title: "Older", cards: older, isCollapsed: false),
            ].compactMap { $0 }
        case .agent:
            return groupedSections(cards, key: { $0.session.agentDisplayName }, kind: { .agent($0) })
        case .workspace:
            return groupedSections(cards, key: { $0.workspaceDisplay }, kind: { .workspace($0) })
        case .date:
            return groupedSections(cards, key: { dateBucket(for: $0.session.lastSeenAt) }, kind: { .date($0) })
        }
    }

    private func groupedSections(
        _ cards: [VaultSidebarCard],
        key: (VaultSidebarCard) -> String,
        kind: (String) -> VaultSidebarSectionKind
    ) -> [VaultSidebarSection] {
        let grouped = Dictionary(grouping: cards, by: key)
        return grouped.keys.sorted().map { title in
            VaultSidebarSection(
                id: title,
                kind: kind(title),
                title: title,
                cards: grouped[title] ?? [],
                isCollapsed: false
            )
        }
    }

    private func makeCard(for session: VaultSession) -> VaultSidebarCard {
        let preview = previewText(for: session, highlights: highlightsBySessionID[session.id] ?? [])
        let workspace = workspaceDisplay(for: session)
        let age = ageText(for: session.lastSeenAt)
        let title = session.agentDisplayName
        return VaultSidebarCard(
            id: session.id,
            session: session,
            title: title,
            preview: preview,
            workspaceDisplay: workspace,
            ageText: age,
            isPinned: pinnedSessionIDs.contains(session.id),
            highlights: highlightsBySessionID[session.id] ?? [],
            activitySparkline: activitySparkline(for: session),
            accessibilityLabel: "\(title), \(age), \(workspace)",
            accessibilityHint: "Press Enter to resume. Drag to a terminal to resume there."
        )
    }

    private func previewText(for session: VaultSession, highlights: [VaultSearchHighlight]) -> String {
        if let firstHighlight = highlights.first, !firstHighlight.snippet.isEmpty {
            return firstHighlight.snippet
        }
        let args = session.sanitizedArguments
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !args.isEmpty {
            return args.joined(separator: " ")
        }
        return session.sessionID
    }

    private func workspaceDisplay(for session: VaultSession) -> String {
        guard let path = session.workingDirectory, !path.isEmpty else { return "No workspace" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func dateBucket(for date: Date) -> String {
        let now = clock()
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return "Today"
        }
        if Calendar.current.isDate(date, inSameDayAs: now.addingTimeInterval(-86_400)) {
            return "Yesterday"
        }
        if date >= now.addingTimeInterval(-7 * 86_400) {
            return "Last 7 days"
        }
        return "Older"
    }

    private func ageText(for date: Date) -> String {
        let seconds = max(0, Int(clock().timeIntervalSince(date)))
        if seconds < 60 { return "Just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hours ago" }
        if hours < 48 { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func activitySparkline(for session: VaultSession) -> [Double] {
        let recency = max(0, min(1, 1 - clock().timeIntervalSince(session.lastSeenAt) / (24 * 60 * 60)))
        return [0.2, 0.35, recency, max(0.25, recency * 0.75)]
    }

    private static func standardizedPath(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        return NSString(string: value).standardizingPath
    }
}
