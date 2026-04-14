// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentDashboardFileChangedSwiftTests.swift
// Phase 3 coverage: AgentDashboardViewModel attributes FileChanged events
// to the active subagent or to the owning session, using the canonical
// `event.sessionId` lookup and respecting deduplication semantics.

import Foundation
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

        let session = viewModel.sessions.first { $0.id == "sess-4" }
        #expect(session?.filesTouched.isEmpty == true)
    }

    @Test("change_type 'delete' currently maps to FileOperation.write")
    func deleteChangeTypeMapsToWrite() {
        let viewModel = AgentDashboardViewModel()
        seedSession(viewModel, sessionId: "sess-5", cwd: "/tmp/proj")

        viewModel.processHookEvent(fileChangedEvent(
            sessionId: "sess-5",
            cwd: "/tmp/proj",
            filePath: "/tmp/proj/gone.swift",
            changeType: "delete"
        ))

        let session = viewModel.sessions.first { $0.id == "sess-5" }
        let impact = session?.filesTouched.first { $0.path == "/tmp/proj/gone.swift" }
        #expect(impact?.operations.contains(.write) == true)
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
        changeType: String?
    ) -> HookEvent {
        HookEvent(
            type: .fileChanged,
            sessionId: sessionId,
            timestamp: Date(),
            data: .fileChanged(FileChangedData(
                filePath: filePath,
                changeType: changeType
            )),
            cwd: cwd
        )
    }
}
