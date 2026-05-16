// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultSidebarViewModelSwiftTestingTests.swift - UI state coverage for the Vault sidebar.

import Foundation
import Testing
@testable import CocxyTerminal
@testable import CocxyVault

@MainActor
@Suite("Vault sidebar view model")
struct VaultSidebarViewModelSwiftTestingTests {

    @Test("loadSessions indexes store data and builds pinned recent older sections")
    func loadSessionsIndexesStoreDataAndBuildsSections() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let pinned = makeSession(id: "codex:pinned", agentID: "codex", lastSeenAt: now.addingTimeInterval(-120))
        let recent = makeSession(id: "claude:recent", agentID: "claude", lastSeenAt: now.addingTimeInterval(-3_600))
        let older = makeSession(id: "qoder:older", agentID: "qoder", lastSeenAt: now.addingTimeInterval(-10 * 86_400))
        let store = InMemoryVaultStore([older, recent, pinned])
        let preferences = try makePreferences()
        preferences.pinnedSessionIDs = [pinned.id]
        let viewModel = try makeViewModel(store: store, preferences: preferences, now: now)

        await viewModel.loadSessions()

        #expect(viewModel.sessions.map(\.id) == [pinned.id, recent.id, older.id])
        #expect(viewModel.filteredSessions.map(\.id) == [pinned.id, recent.id, older.id])
        #expect(viewModel.groupSections.map(\.kind) == [.pinned, .recent, .older])
        #expect(viewModel.groupSections[0].cards.map(\.session.id) == [pinned.id])
        #expect(viewModel.groupSections[1].cards.map(\.session.id) == [recent.id])
        #expect(viewModel.groupSections[2].cards.map(\.session.id) == [older.id])
    }

    @Test("search query uses search index highlights and keeps results scoped to loaded sessions")
    func searchQueryUsesSearchIndexHighlights() async throws {
        let session = makeSession(
            id: "codex:search",
            agentID: "codex",
            arguments: ["codex", "resume", "search", "needle", "vault"]
        )
        let store = InMemoryVaultStore([session])
        let viewModel = try makeViewModel(store: store)

        await viewModel.loadSessions()
        await viewModel.search(query: "needle")

        #expect(viewModel.filteredSessions.map(\.id) == [session.id])
        let card = try #require(viewModel.cards.first)
        #expect(card.highlights.contains { $0.snippet.localizedCaseInsensitiveContains("needle") })
        #expect(card.preview.localizedCaseInsensitiveContains("needle"))
    }

    @Test("agent filter chips support multi-select filtering")
    func agentFilterChipsSupportMultiSelectFiltering() async throws {
        let codex = makeSession(id: "codex:one", agentID: "codex")
        let claude = makeSession(id: "claude:one", agentID: "claude")
        let qoder = makeSession(id: "qoder:one", agentID: "qoder")
        let viewModel = try makeViewModel(store: InMemoryVaultStore([codex, claude, qoder]))

        await viewModel.loadSessions()
        viewModel.toggleAgentFilter(VaultAgentID("codex"))
        viewModel.toggleAgentFilter(VaultAgentID("qoder"))

        #expect(viewModel.selectedAgents == [VaultAgentID("codex"), VaultAgentID("qoder")])
        #expect(viewModel.filteredSessions.map(\.id) == [codex.id, qoder.id])

        viewModel.clearAgentFilters()

        #expect(viewModel.filteredSessions.map(\.id) == [claude.id, codex.id, qoder.id])
    }

    @Test("pin and unpin update sections and persist preferences")
    func pinAndUnpinPersistPreferences() async throws {
        let session = makeSession(id: "codex:persist", agentID: "codex")
        let preferences = try makePreferences()
        let viewModel = try makeViewModel(
            store: InMemoryVaultStore([session]),
            preferences: preferences
        )

        await viewModel.loadSessions()
        viewModel.pin(session: session)

        #expect(preferences.pinnedSessionIDs == [session.id])
        #expect(viewModel.groupSections.first?.kind == .pinned)

        viewModel.unpin(session: session)

        #expect(preferences.pinnedSessionIDs.isEmpty)
        #expect(!viewModel.groupSections.contains { $0.kind == .pinned })
    }

    @Test("delete removes session from store search index and selection")
    func deleteRemovesSessionFromStoreSearchIndexAndSelection() async throws {
        let keep = makeSession(id: "codex:keep", agentID: "codex", arguments: ["keep", "needle"])
        let delete = makeSession(id: "codex:delete", agentID: "codex", arguments: ["delete", "needle"])
        let store = InMemoryVaultStore([keep, delete])
        let viewModel = try makeViewModel(store: store)

        await viewModel.loadSessions()
        viewModel.toggleSelection(delete.id)
        try await viewModel.delete(session: delete)
        await viewModel.search(query: "delete")

        #expect(store.sessions.map(\.id) == [keep.id])
        #expect(viewModel.selectedSessionIDs.isEmpty)
        #expect(viewModel.filteredSessions.isEmpty)
    }

    @Test("multi-select supports toggle range and select all visible")
    func multiSelectSupportsToggleRangeAndSelectAllVisible() async throws {
        let sessions = (1...4).map { makeSession(id: "codex:\($0)", agentID: "codex", lastSeenAt: Date(timeIntervalSince1970: TimeInterval(10 - $0))) }
        let viewModel = try makeViewModel(store: InMemoryVaultStore(sessions))

        await viewModel.loadSessions()
        viewModel.toggleSelection("codex:1")
        viewModel.selectRange(to: "codex:3")

        #expect(viewModel.selectedSessionIDs == ["codex:1", "codex:2", "codex:3"])

        viewModel.selectAllVisible()
        #expect(viewModel.selectedSessionIDs == Set(sessions.map(\.id)))

        viewModel.clearSelection()
        #expect(viewModel.selectedSessionIDs.isEmpty)
    }

    @Test("bulk pin unpin delete and workspace suggestions use selected visible sessions")
    func bulkActionsAndWorkspaceSuggestionUseVisibleSessions() async throws {
        let codex = makeSession(
            id: "codex:bulk",
            agentID: "codex",
            workingDirectory: "/tmp/cocxy-terminal"
        )
        let claude = makeSession(
            id: "claude:bulk",
            agentID: "claude",
            workingDirectory: "/tmp/cocxy-terminal",
            lastSeenAt: Date(timeIntervalSince1970: 90)
        )
        let other = makeSession(id: "qoder:bulk", agentID: "qoder", workingDirectory: "/tmp/other")
        let store = InMemoryVaultStore([codex, claude, other])
        let viewModel = try makeViewModel(store: store)

        await viewModel.loadSessions()
        viewModel.setActiveWorkspacePath("/tmp/cocxy-terminal")
        viewModel.toggleSelection(codex.id)
        viewModel.toggleSelection(claude.id)
        viewModel.pinSelected()

        #expect(viewModel.workspaceSuggestion?.matchingSessionCount == 2)
        #expect(viewModel.workspaceSuggestion?.workspaceDisplay == "cocxy-terminal")
        #expect(viewModel.pinnedSessionIDs == [codex.id, claude.id])
        #expect(viewModel.selectedSessions.map(\.id) == [codex.id, claude.id])

        viewModel.unpinSelected()
        #expect(viewModel.pinnedSessionIDs.isEmpty)

        try await viewModel.deleteSelected()
        #expect(store.sessions.map(\.id) == [other.id])
        #expect(viewModel.selectedSessionIDs.isEmpty)
    }

    @Test("store change notification reloads sessions for live updates")
    func storeChangeNotificationReloadsSessions() async throws {
        let notificationCenter = NotificationCenter()
        let initial = makeSession(id: "codex:initial", agentID: "codex")
        let added = makeSession(id: "claude:added", agentID: "claude")
        let store = InMemoryVaultStore([initial])
        let viewModel = try makeViewModel(store: store, notificationCenter: notificationCenter)

        await viewModel.loadSessions()
        store.sessions.append(added)
        notificationCenter.post(name: VaultSessionStore.sessionsDidChangeNotification, object: nil)
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(viewModel.sessions.map(\.id).contains(added.id))
    }

    @Test("width mode cycles expanded compact icon-only")
    func widthModeCyclesExpandedCompactIconOnly() throws {
        let preferences = try makePreferences()
        let viewModel = try makeViewModel(
            store: InMemoryVaultStore([]),
            preferences: preferences
        )

        #expect(viewModel.widthMode == .expanded)
        viewModel.cycleWidthMode()
        #expect(viewModel.widthMode == .compact)
        viewModel.cycleWidthMode()
        #expect(viewModel.widthMode == .iconOnly)
        viewModel.cycleWidthMode()
        #expect(viewModel.widthMode == .expanded)
        #expect(preferences.widthMode == .expanded)
    }

    @Test("session card presentation derives age preview workspace and accessibility copy")
    func cardPresentationDerivesCopy() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let session = makeSession(
            id: "claude:copy",
            agentID: "claude",
            workingDirectory: "/Users/example/cocxy-terminal",
            arguments: ["claude", "--resume", "copy", "visual", "vault"],
            lastSeenAt: now.addingTimeInterval(-5 * 60)
        )
        let viewModel = try makeViewModel(store: InMemoryVaultStore([session]), now: now)

        await viewModel.loadSessions()

        let card = try #require(viewModel.cards.first)
        #expect(card.title == "Claude")
        #expect(card.workspaceDisplay == "cocxy-terminal")
        #expect(card.ageText == "5 min ago")
        #expect(card.accessibilityLabel.contains("Claude"))
        #expect(card.accessibilityHint == "Press Enter to resume. Drag to a terminal to resume there.")
    }

    private func makeViewModel(
        store: InMemoryVaultStore,
        preferences: VaultSidebarPreferences? = nil,
        notificationCenter: NotificationCenter = .default,
        now: Date = Date(timeIntervalSince1970: 10_000)
    ) throws -> VaultSidebarViewModel {
        try VaultSidebarViewModel(
            store: store,
            searchIndex: VaultSearchIndex(
                indexURL: temporaryDirectory().appendingPathComponent("vault-search.sqlite"),
                keyProvider: StaticVaultKeyProvider(keyData: Data(repeating: 3, count: 32))
            ),
            preferences: preferences ?? makePreferences(),
            notificationCenter: notificationCenter,
            clock: { now }
        )
    }

    private func makePreferences() throws -> VaultSidebarPreferences {
        let defaults = try #require(UserDefaults(suiteName: "VaultSidebarViewModelTests-\(UUID().uuidString)"))
        defaults.removePersistentDomain(forName: defaultsSuiteName(defaults))
        return VaultSidebarPreferences(defaults: defaults)
    }

    private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
        defaults.dictionaryRepresentation()["NSArgumentDomain"] as? String ?? "unused"
    }

    private func makeSession(
        id: String,
        agentID: VaultAgentID,
        workingDirectory: String? = nil,
        arguments: [String] = [],
        lastSeenAt: Date = Date(timeIntervalSince1970: 100)
    ) -> VaultSession {
        VaultSession(
            id: id,
            agentID: agentID,
            agentDisplayName: agentID.rawValue.prefix(1).uppercased() + agentID.rawValue.dropFirst(),
            sessionID: id.components(separatedBy: ":").last ?? id,
            workingDirectory: workingDirectory,
            capturedAt: Date(timeIntervalSince1970: 50),
            lastSeenAt: lastSeenAt,
            source: .manual,
            sanitizedArguments: arguments
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-vault-sidebar-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class InMemoryVaultStore: VaultSessionStoring {
    var sessions: [VaultSession]

    init(_ sessions: [VaultSession]) {
        self.sessions = sessions
    }

    func loadSessions() throws -> [VaultSession] {
        sessions.sorted { $0.lastSeenAt > $1.lastSeenAt }
    }

    func saveSessions(_ sessions: [VaultSession]) throws {
        self.sessions = sessions.sorted { $0.lastSeenAt > $1.lastSeenAt }
    }

    func upsert(_ session: VaultSession) throws {
        sessions.removeAll { $0.id == session.id }
        sessions.append(session)
    }

    func pruneSessions(olderThan cutoff: Date) throws -> [VaultSession] {
        sessions = sessions.filter { $0.lastSeenAt >= cutoff }
        return try loadSessions()
    }

    func clear() throws {
        sessions = []
    }
}
