// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraNotesSectionSwiftTestingTests.swift - Pin the contracts that
// the Aurora sidebar's per-workspace notes section relies on:
// adapter mapping (path -> NoteWorkspaceID), source builder
// propagation, controller publisher behaviour and dedup.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Aurora — Notes section")
struct AuroraNotesSectionSwiftTestingTests {

    // MARK: - Adapter mapping

    @Test("workspace exposes the resolved NoteWorkspaceID raw value so the sidebar binds the notes section to the same identifier the store uses on disk")
    func workspaceCarriesNotesIdentifierFromRootPath() {
        let path = "/Users/test/code/cocxy"
        let tab = Design.AuroraSourceTab(
            id: "tab-1",
            name: "tab",
            workspaceGroup: "cocxy",
            surfaces: [],
            workingDirectory: path,
            workspaceRootPath: path
        )

        let workspaces = Design.AuroraWorkspaceAdapter.workspaces(from: [tab])

        let expected = NoteWorkspaceID(
            workspaceRoot: URL(fileURLWithPath: path, isDirectory: true)
        ).rawValue
        #expect(workspaces.first?.notesWorkspaceID == expected)
    }

    @Test("workspaceRootPath wins over workingDirectory when both are present so git ancestors group sibling tabs under the same notes folder")
    func workspaceRootPathPreferredOverWorkingDirectory() {
        let root = "/Users/test/code/cocxy"
        let nested = "/Users/test/code/cocxy/web/src"
        let tab = Design.AuroraSourceTab(
            id: "tab-1",
            name: "web",
            workspaceGroup: "cocxy",
            surfaces: [],
            workingDirectory: nested,
            workspaceRootPath: root
        )

        let workspaces = Design.AuroraWorkspaceAdapter.workspaces(from: [tab])

        let expected = NoteWorkspaceID(
            workspaceRoot: URL(fileURLWithPath: root, isDirectory: true)
        ).rawValue
        #expect(workspaces.first?.notesWorkspaceID == expected)
    }

    @Test("workspace falls back to workingDirectory when the rootPath is missing so non-git tabs still get a stable notes identifier")
    func workspaceFallsBackToWorkingDirectoryWhenRootMissing() {
        let path = "/tmp/scratch"
        let tab = Design.AuroraSourceTab(
            id: "tab-1",
            name: "scratch",
            workspaceGroup: "scratch",
            surfaces: [],
            workingDirectory: path,
            workspaceRootPath: nil
        )

        let workspaces = Design.AuroraWorkspaceAdapter.workspaces(from: [tab])

        let expected = NoteWorkspaceID(
            workspaceRoot: URL(fileURLWithPath: path, isDirectory: true)
        ).rawValue
        #expect(workspaces.first?.notesWorkspaceID == expected)
    }

    @Test("workspace omits notesWorkspaceID when no path is resolvable so SSH and detached tabs do not surface a non-functional notes section")
    func workspaceWithoutPathSkipsNotesIdentifier() {
        let tab = Design.AuroraSourceTab(
            id: "tab-1",
            name: "ssh-host",
            workspaceGroup: "ssh",
            surfaces: [],
            workingDirectory: nil,
            workspaceRootPath: nil
        )

        let workspaces = Design.AuroraWorkspaceAdapter.workspaces(from: [tab])

        #expect(workspaces.first?.notesWorkspaceID == nil)
    }

    @Test("filteringSessions preserves the notes identifier so search filtering does not drop the per-workspace notes section")
    func filteringSessionsPreservesNotesIdentifier() {
        let workspace = Design.AuroraWorkspace(
            id: "ws-1",
            name: "ws-1",
            branch: nil,
            isCollapsed: false,
            sessions: [
                Design.AuroraSession(
                    id: "s",
                    name: "session",
                    agent: .claude,
                    state: .working,
                    panes: []
                )
            ],
            notesWorkspaceID: "abc123def456"
        )

        let filtered = workspace.filteringSessions(by: "no-match")

        #expect(filtered.notesWorkspaceID == "abc123def456")
        #expect(filtered.sessions.isEmpty)
    }

    // MARK: - Controller publishers

    @Test("notesByWorkspace defaults to empty so a fresh controller renders the sidebar without any notes section")
    @MainActor
    func notesByWorkspaceDefaultsToEmpty() {
        let controller = AuroraChromeController(
            tabManager: TabManager(),
            store: AgentStatePerSurfaceStore()
        )

        #expect(controller.notesByWorkspace.isEmpty)
    }

    @Test("refreshNotesSummaries clears the published map when the provider is later removed so a config flip-off propagates without rebuilding the controller")
    @MainActor
    func refreshClearsMapWhenProviderRemoved() async throws {
        let controller = AuroraChromeController(
            tabManager: TabManager(),
            store: AgentStatePerSurfaceStore()
        )
        controller.workspaces = [
            Design.AuroraWorkspace(
                id: "alpha",
                name: "alpha",
                branch: nil,
                isCollapsed: false,
                sessions: [],
                notesWorkspaceID: "id-alpha"
            )
        ]
        controller.notesSummariesProvider = { _ in
            [
                "id-alpha": Design.AuroraWorkspaceNotesSummary(
                    workspaceID: "id-alpha",
                    count: 1,
                    recentNotes: []
                )
            ]
        }

        controller.refreshNotesSummaries()
        _ = try await waitForMap(
            on: controller,
            condition: { $0["id-alpha"]?.count == 1 },
            timeout: 1.0
        )

        // Drop the provider as if the host's config service flipped
        // `[notes].enabled` off mid-session. Refresh should clear the
        // published map without leaving stale rows.
        controller.notesSummariesProvider = nil
        controller.refreshNotesSummaries()

        let cleared = try await waitForMap(
            on: controller,
            condition: { $0.isEmpty },
            timeout: 1.0
        )
        #expect(cleared.isEmpty)
    }

    @Test("refreshNotesSummaries calls the provider with every visible workspace identifier so the sidebar is fed the right keys")
    @MainActor
    func refreshCallsProviderWithVisibleIDs() async throws {
        let controller = AuroraChromeController(
            tabManager: TabManager(),
            store: AgentStatePerSurfaceStore()
        )
        controller.workspaces = [
            Design.AuroraWorkspace(
                id: "alpha",
                name: "alpha",
                branch: nil,
                isCollapsed: false,
                sessions: [],
                notesWorkspaceID: "id-alpha"
            ),
            Design.AuroraWorkspace(
                id: "beta",
                name: "beta",
                branch: nil,
                isCollapsed: false,
                sessions: [],
                notesWorkspaceID: "id-beta"
            ),
            Design.AuroraWorkspace(
                id: "gamma",
                name: "gamma",
                branch: nil,
                isCollapsed: false,
                sessions: [],
                notesWorkspaceID: nil  // missing path → omitted from query
            ),
        ]
        let recorded = ProviderRecorder()
        controller.notesSummariesProvider = { ids in
            await recorded.append(ids)
            return [
                "id-alpha": Design.AuroraWorkspaceNotesSummary(
                    workspaceID: "id-alpha",
                    count: 2,
                    recentNotes: []
                )
            ]
        }

        controller.refreshNotesSummaries()

        let recordedIDs = try await recorded.firstSet(timeout: 1.0)
        #expect(recordedIDs == Set(["id-alpha", "id-beta"]))
    }

    @Test("refreshNotesSummaries publishes the provider result so the sidebar gets the freshest counts")
    @MainActor
    func refreshPublishesProviderResult() async throws {
        let controller = AuroraChromeController(
            tabManager: TabManager(),
            store: AgentStatePerSurfaceStore()
        )
        controller.workspaces = [
            Design.AuroraWorkspace(
                id: "alpha",
                name: "alpha",
                branch: nil,
                isCollapsed: false,
                sessions: [],
                notesWorkspaceID: "id-alpha"
            )
        ]
        let row = Design.AuroraNoteRow(
            id: UUID().uuidString,
            title: "First",
            updatedAt: Date()
        )
        let summary = Design.AuroraWorkspaceNotesSummary(
            workspaceID: "id-alpha",
            count: 1,
            recentNotes: [row]
        )
        controller.notesSummariesProvider = { _ in
            ["id-alpha": summary]
        }

        controller.refreshNotesSummaries()

        let published = try await waitForMap(
            on: controller,
            condition: { $0["id-alpha"] == summary },
            timeout: 1.0
        )
        #expect(published["id-alpha"] == summary)
    }

    @Test("refreshNotesSummaries drops summaries whose workspace disappeared between request and response so the published map never carries stale rows for closed tabs")
    @MainActor
    func refreshFiltersOutStaleSummaries() async throws {
        let controller = AuroraChromeController(
            tabManager: TabManager(),
            store: AgentStatePerSurfaceStore()
        )
        controller.workspaces = [
            Design.AuroraWorkspace(
                id: "alpha",
                name: "alpha",
                branch: nil,
                isCollapsed: false,
                sessions: [],
                notesWorkspaceID: "id-alpha"
            )
        ]
        controller.notesSummariesProvider = { _ in
            // Provider returns an extra workspace key the controller no
            // longer cares about (closed tab). The published map must
            // drop it.
            [
                "id-alpha": Design.AuroraWorkspaceNotesSummary(
                    workspaceID: "id-alpha",
                    count: 1,
                    recentNotes: []
                ),
                "id-stale": Design.AuroraWorkspaceNotesSummary(
                    workspaceID: "id-stale",
                    count: 5,
                    recentNotes: []
                ),
            ]
        }

        controller.refreshNotesSummaries()

        let published = try await waitForMap(
            on: controller,
            condition: { $0["id-alpha"]?.count == 1 },
            timeout: 1.0
        )
        #expect(published.keys.contains("id-alpha"))
        #expect(published.keys.contains("id-stale") == false)
    }

    @Test("onOpenNoteInWorkspace is nil by default so the sidebar suppresses every notes row click until the host wires it")
    @MainActor
    func onOpenNoteInWorkspaceNilByDefault() {
        let controller = AuroraChromeController(
            tabManager: TabManager(),
            store: AgentStatePerSurfaceStore()
        )

        #expect(controller.onOpenNoteInWorkspace == nil)
    }

    @Test("onOpenNoteInWorkspace forwards both identifiers verbatim so the host can open the right overlay and select the right note")
    @MainActor
    func onOpenNoteInWorkspaceForwardsBothIdentifiers() {
        let controller = AuroraChromeController(
            tabManager: TabManager(),
            store: AgentStatePerSurfaceStore()
        )
        var captured: (String, String)?
        controller.onOpenNoteInWorkspace = { workspaceID, noteID in
            captured = (workspaceID, noteID)
        }

        controller.onOpenNoteInWorkspace?("ws-id", "note-id")

        #expect(captured?.0 == "ws-id")
        #expect(captured?.1 == "note-id")
    }

    // MARK: - Helpers

    /// Actor-backed recorder for `notesSummariesProvider` invocations
    /// so tests can assert against the sequence of identifier sets the
    /// controller asked for without sharing mutable state across the
    /// `await` boundary.
    private actor ProviderRecorder {
        private var calls: [Set<String>] = []
        private var continuation: CheckedContinuation<Set<String>, Error>?

        func append(_ ids: Set<String>) {
            calls.append(ids)
            if let continuation {
                self.continuation = nil
                continuation.resume(returning: ids)
            }
        }

        func firstSet(timeout: TimeInterval) async throws -> Set<String> {
            if let value = calls.first {
                return value
            }
            return try await withThrowingTaskGroup(of: Set<String>.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        Task { await self.setContinuation(continuation) }
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw RecorderError.timeout
                }
                let value = try await group.next()!
                group.cancelAll()
                return value
            }
        }

        private func setContinuation(_ continuation: CheckedContinuation<Set<String>, Error>) {
            if let value = calls.first {
                continuation.resume(returning: value)
            } else {
                self.continuation = continuation
            }
        }

        enum RecorderError: Error { case timeout }
    }

    @MainActor
    private func waitForMap(
        on controller: AuroraChromeController,
        condition: @escaping ([String: Design.AuroraWorkspaceNotesSummary]) -> Bool,
        timeout: TimeInterval
    ) async throws -> [String: Design.AuroraWorkspaceNotesSummary] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition(controller.notesByWorkspace) {
                return controller.notesByWorkspace
            }
            try await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }
        throw WaitError.timeout
    }

    private enum WaitError: Error { case timeout }
}
