// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentDashboardFileChangedSwiftTests.swift
// Phase 3 coverage: AgentDashboardViewModel attributes FileChanged events
// to the active subagent or to the owning session, using the canonical
// `event.sessionId` lookup and respecting deduplication semantics.

import Foundation
import Combine
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("AgentDashboardViewModel FileChanged attribution")
struct AgentDashboardFileChangedSwiftTests {

    @Test("FileChanged with one active subagent attributes the path to that subagent")
    func fileChangedAttributesPathToActiveSubagent() {
        let viewModel = AgentDashboardViewModel()
        seedSession(viewModel, sessionId: "sess-1", cwd: "/tmp/proj")
        seedActiveSubagent(viewModel, sessionId: "sess-1", subagentId: "sub-A")

        viewModel.processHookEvent(fileChangedEvent(
            sessionId: "sess-1",
            cwd: "/tmp/proj",
            filePath: "/tmp/proj/main.swift",
            changeType: "edit"
        ))
        viewModel.flushPendingFileChanges()

        let session = viewModel.sessions.first { $0.id == "sess-1" }
        #expect(session != nil)
        let subagent = session?.subagents.first
        #expect(subagent?.touchedFilePaths.contains("/tmp/proj/main.swift") == true)
        let impact = session?.filesTouched.first { $0.path == "/tmp/proj/main.swift" }
        #expect(impact != nil)
        #expect(impact?.operations.contains(.edit) == true)
    }

    @Test("FileChanged without an active subagent records only at the session level")
    func fileChangedWithoutActiveSubagentAttributesToSession() {
        let viewModel = AgentDashboardViewModel()
        seedSession(viewModel, sessionId: "sess-2", cwd: "/tmp/proj")

        viewModel.processHookEvent(fileChangedEvent(
            sessionId: "sess-2",
            cwd: "/tmp/proj",
            filePath: "/tmp/proj/lonely.swift",
            changeType: "write"
        ))
        viewModel.flushPendingFileChanges()

        let session = viewModel.sessions.first { $0.id == "sess-2" }
        let impact = session?.filesTouched.first { $0.path == "/tmp/proj/lonely.swift" }
        #expect(impact?.operations.contains(.write) == true)
        #expect(session?.subagents.isEmpty == true)
    }

    @Test("FileChanged for an unknown session is ignored")
    func fileChangedInUnknownSessionIsIgnored() {
        let viewModel = AgentDashboardViewModel()
        seedSession(viewModel, sessionId: "sess-real", cwd: "/tmp/proj")

        viewModel.processHookEvent(fileChangedEvent(
            sessionId: "sess-ghost",
            cwd: "/tmp/proj",
            filePath: "/tmp/proj/x.swift",
            changeType: "edit"
        ))
        viewModel.flushPendingFileChanges()

        let realSession = viewModel.sessions.first { $0.id == "sess-real" }
        #expect(realSession?.filesTouched.isEmpty == true)
        #expect(viewModel.sessions.contains { $0.id == "sess-ghost" } == false)
    }

    @Test("FileChanged deduplicates repeated paths")
    func fileChangedDeduplicatesRepeatedPaths() {
        let viewModel = AgentDashboardViewModel()
        seedSession(viewModel, sessionId: "sess-3", cwd: "/tmp/proj")

        for _ in 0..<3 {
            viewModel.processHookEvent(fileChangedEvent(
                sessionId: "sess-3",
                cwd: "/tmp/proj",
                filePath: "/tmp/proj/repeat.swift",
                changeType: "edit"
            ))
        }
        viewModel.flushPendingFileChanges()

        let session = viewModel.sessions.first { $0.id == "sess-3" }
        let matching = session?.filesTouched.filter { $0.path == "/tmp/proj/repeat.swift" }
        #expect(matching?.count == 1)
        #expect(matching?.first?.operations == Set([.edit]))
    }

    @Test("FileChanged with empty file_path is tolerated and skipped")
    func fileChangedWithEmptyFilePathIsSkipped() {
        let viewModel = AgentDashboardViewModel()
        seedSession(viewModel, sessionId: "sess-4", cwd: "/tmp/proj")

        viewModel.processHookEvent(fileChangedEvent(
            sessionId: "sess-4",
            cwd: "/tmp/proj",
            filePath: "",
            changeType: "edit"
        ))
        viewModel.flushPendingFileChanges()

        let session = viewModel.sessions.first { $0.id == "sess-4" }
        #expect(session?.filesTouched.isEmpty == true)
    }

    @Test("canonical unlink event maps to FileOperation.delete")
    func unlinkEventMapsToDelete() {
        let viewModel = AgentDashboardViewModel()
        seedSession(viewModel, sessionId: "sess-5", cwd: "/tmp/proj")

        viewModel.processHookEvent(fileChangedEvent(
            sessionId: "sess-5",
            cwd: "/tmp/proj",
            filePath: "/tmp/proj/gone.swift",
            changeType: "unlink"
        ))
        viewModel.flushPendingFileChanges()

        let session = viewModel.sessions.first { $0.id == "sess-5" }
        let impact = session?.filesTouched.first { $0.path == "/tmp/proj/gone.swift" }
        #expect(impact?.operations.contains(.delete) == true)
    }

    @Test("FileChanged impacts are ordered by real event recency")
    func fileChangedImpactsAreOrderedByRecency() {
        let viewModel = AgentDashboardViewModel()
        seedSession(viewModel, sessionId: "sess-recency", cwd: "/tmp/proj")
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)

        viewModel.processHookEvent(fileChangedEvent(
            sessionId: "sess-recency",
            cwd: "/tmp/proj",
            filePath: "/tmp/proj/older.swift",
            changeType: "change",
            timestamp: older
        ))
        viewModel.processHookEvent(fileChangedEvent(
            sessionId: "sess-recency",
            cwd: "/tmp/proj",
            filePath: "/tmp/proj/newer.swift",
            changeType: "add",
            timestamp: newer
        ))
        viewModel.flushPendingFileChanges()

        let impacts = viewModel.sessions.first { $0.id == "sess-recency" }?.filesTouched
        #expect(impacts?.map(\.fileName) == ["newer.swift", "older.swift"])
        #expect(impacts?.first?.lastChangedAt == newer)
        #expect(impacts?.first?.operations == [.create])
    }

    @Test("opening a tracked impact forwards the exact session and path")
    func openingTrackedImpactForwardsExactContext() {
        let viewModel = AgentDashboardViewModel()
        seedSession(viewModel, sessionId: "sess-open", cwd: "/tmp/proj")
        let path = "/tmp/proj/Sources/App.swift"
        viewModel.processHookEvent(fileChangedEvent(
            sessionId: "sess-open",
            cwd: "/tmp/proj",
            filePath: path,
            changeType: "change"
        ))
        viewModel.flushPendingFileChanges()
        var opened: (String, String)?
        viewModel.onOpenFileImpact = { opened = ($0, $1) }

        viewModel.openFileImpact(path, for: "sess-open")

        #expect(opened?.0 == "sess-open")
        #expect(opened?.1 == path)
    }

    @Test("rapid FileChanged bursts publish one coalesced dashboard snapshot")
    func rapidFileChangedBurstIsCoalesced() async throws {
        let viewModel = AgentDashboardViewModel()
        viewModel.fileChangeDebounceInterval = 0.02
        seedSession(viewModel, sessionId: "sess-burst", cwd: "/tmp/proj")

        var publishedSnapshotCount = 0
        let cancellable = viewModel.sessionsPublisher
            .dropFirst()
            .sink { _ in
                publishedSnapshotCount += 1
            }

        for index in 0..<64 {
            viewModel.processHookEvent(fileChangedEvent(
                sessionId: "sess-burst",
                cwd: "/tmp/proj",
                filePath: "/tmp/proj/file-\(index).swift",
                changeType: "change",
                timestamp: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }

        #expect(viewModel.sessions.first?.filesTouched.isEmpty == true)
        for _ in 0..<1_500 where publishedSnapshotCount == 0 { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(100))

        #expect(publishedSnapshotCount == 1)
        #expect(viewModel.sessions.first?.filesTouched.count == 64)
        withExtendedLifetime(cancellable) {}
    }

    @Test("FileChanged impacts retain only the 512 most recent paths")
    func fileChangedImpactsUseBoundedLRU() {
        let viewModel = AgentDashboardViewModel()
        seedSession(viewModel, sessionId: "sess-lru", cwd: "/tmp/proj")
        seedActiveSubagent(viewModel, sessionId: "sess-lru", subagentId: "sub-lru")

        for index in 0..<600 {
            viewModel.processHookEvent(fileChangedEvent(
                sessionId: "sess-lru",
                cwd: "/tmp/proj",
                filePath: "/tmp/proj/file-\(index).swift",
                changeType: "change",
                timestamp: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }
        viewModel.flushPendingFileChanges()

        let impacts = viewModel.sessions.first?.filesTouched
        #expect(impacts?.count == AgentDashboardViewModel.maxFileImpactsPerSession)
        #expect(impacts?.first?.fileName == "file-599.swift")
        #expect(impacts?.last?.fileName == "file-88.swift")
        #expect(impacts?.contains { $0.fileName == "file-87.swift" } == false)
        let touchedPaths = viewModel.sessions.first?.subagents.first?.touchedFilePaths
        #expect(touchedPaths?.count == AgentDashboardViewModel.maxFileImpactsPerSession)
        #expect(touchedPaths?.contains("/tmp/proj/file-599.swift") == true)
        #expect(touchedPaths?.contains("/tmp/proj/file-87.swift") == false)
    }

    // MARK: - Helpers

    private func seedSession(
        _ viewModel: AgentDashboardViewModel,
        sessionId: String,
        cwd: String
    ) {
        viewModel.processHookEvent(HookEvent(
            type: .sessionStart,
            sessionId: sessionId,
            timestamp: Date(),
            data: .sessionStart(SessionStartData(
                model: "claude-sonnet-4",
                agentType: "claude-code",
                workingDirectory: cwd
            )),
            cwd: cwd
        ))
    }

    private func seedActiveSubagent(
        _ viewModel: AgentDashboardViewModel,
        sessionId: String,
        subagentId: String
    ) {
        viewModel.processHookEvent(HookEvent(
            type: .subagentStart,
            sessionId: sessionId,
            timestamp: Date(),
            data: .subagent(SubagentData(
                subagentId: subagentId,
                subagentType: "research"
            )),
            cwd: "/tmp/proj"
        ))
    }

    private func fileChangedEvent(
        sessionId: String,
        cwd: String,
        filePath: String,
        changeType: String?,
        timestamp: Date = Date()
    ) -> HookEvent {
        HookEvent(
            type: .fileChanged,
            sessionId: sessionId,
            timestamp: timestamp,
            data: .fileChanged(FileChangedData(
                filePath: filePath,
                changeType: changeType
            )),
            cwd: cwd
        )
    }
}
