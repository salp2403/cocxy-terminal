// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AIEditHistoryPanelViewModelSwiftTestingTests.swift - UI state for local edit history.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("AI edit history panel view model")
struct AIEditHistoryPanelViewModelSwiftTestingTests {
    @Test("refresh loads newest edits and selects newest")
    func refreshLoadsNewestEditsAndSelectsNewest() throws {
        let storeRoot = try makeTemporaryDirectory(named: "ai-edit-history-panel-store")
        let workspace = try makeTemporaryDirectory(named: "ai-edit-history-panel-workspace")
        defer {
            try? FileManager.default.removeItem(at: storeRoot)
            try? FileManager.default.removeItem(at: workspace)
        }

        let store = AIEditStore(rootDirectory: storeRoot)
        let older = edit(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            createdAt: Date(timeIntervalSince1970: 10),
            filePath: "Sources/App.swift"
        )
        let newer = edit(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            createdAt: Date(timeIntervalSince1970: 20),
            filePath: "README.md"
        )
        try store.append(older, repoID: "repo")
        try store.append(newer, repoID: "repo")

        let viewModel = AIEditHistoryPanelViewModel(
            repoID: "repo",
            sessionID: "session",
            workingDirectory: workspace,
            store: store
        )

        try viewModel.refresh()

        #expect(viewModel.records.map(\.id) == [newer.id, older.id])
        #expect(viewModel.selectedRecordID == newer.id)
        #expect(viewModel.selectedFileSummaries == [
            AIEditFileSummary(filePath: "README.md", additions: 1, deletions: 1),
        ])
        #expect(viewModel.statusText == "2 edits")
    }

    @Test("revert selected restores files and keeps the timeline visible")
    func revertSelectedRestoresFilesAndKeepsTimelineVisible() throws {
        let storeRoot = try makeTemporaryDirectory(named: "ai-edit-history-panel-revert-store")
        let workspace = try makeTemporaryDirectory(named: "ai-edit-history-panel-revert-workspace")
        defer {
            try? FileManager.default.removeItem(at: storeRoot)
            try? FileManager.default.removeItem(at: workspace)
        }

        let file = workspace.appendingPathComponent("README.md")
        try "after\n".write(to: file, atomically: true, encoding: .utf8)

        let store = AIEditStore(rootDirectory: storeRoot)
        let record = edit(filePath: "README.md")
        try store.append(record, repoID: "repo")
        let viewModel = AIEditHistoryPanelViewModel(
            repoID: "repo",
            sessionID: "session",
            workingDirectory: workspace,
            store: store
        )
        try viewModel.refresh()

        try viewModel.revertSelected()

        #expect(try String(contentsOf: file, encoding: .utf8) == "before\n")
        #expect(viewModel.records.map(\.id) == [record.id])
        #expect(viewModel.selectedRecordID == record.id)
        #expect(viewModel.statusText == "Reverted 1 file")
    }

    private func edit(
        id: UUID = UUID(),
        createdAt: Date = Date(timeIntervalSince1970: 1),
        filePath: String
    ) -> AIEditRecord {
        AIEditRecord(
            id: id,
            sessionID: "session",
            agentID: "local-agent",
            createdAt: createdAt,
            summary: "Edit \(filePath)",
            changes: [
                AIEditChange(filePath: filePath, beforeContent: "before\n", afterContent: "after\n"),
            ]
        )
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
