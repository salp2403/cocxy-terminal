// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AIEditHistoryPanelViewModel.swift - Presentation state for local edit history.

import Combine
import Foundation

struct AIEditRecordPresentation: Identifiable, Equatable {
    let id: UUID
    let sessionID: String
    let agentID: String
    let createdAt: Date
    let title: String
    let detail: String
    let summary: String
}

enum AIEditHistoryPanelError: Error, Equatable, LocalizedError {
    case noSession
    case noSelection

    var errorDescription: String? {
        switch self {
        case .noSession:
            return "No agent edit session is selected."
        case .noSelection:
            return "No edit is selected."
        }
    }
}

protocol AIEditReverting {
    func revert(_ record: AIEditRecord, in workingDirectory: URL) throws -> AIEditRevertResult
}

extension AIEditReverter: AIEditReverting {}

@MainActor
final class AIEditHistoryPanelViewModel: ObservableObject {
    @Published private(set) var records: [AIEditRecordPresentation] = []
    @Published var selectedRecordID: UUID?
    @Published private(set) var selectedFileSummaries: [AIEditFileSummary] = []
    @Published private(set) var selectedChanges: [AIEditChange] = []
    @Published private(set) var statusText = "No edits"
    @Published private(set) var errorText: String?

    let repoID: String
    let sessionID: String?
    let workingDirectory: URL

    private let store: AIEditStore
    private let differ: AIEditDiffer
    private let reverter: any AIEditReverting
    private var loadedRecords: [AIEditRecord] = []

    var selectedRecord: AIEditRecordPresentation? {
        guard let selectedRecordID else { return nil }
        return records.first { $0.id == selectedRecordID }
    }

    init(
        repoID: String,
        sessionID: String?,
        workingDirectory: URL,
        store: AIEditStore = AIEditStore(),
        differ: AIEditDiffer = AIEditDiffer(),
        reverter: any AIEditReverting = AIEditReverter()
    ) {
        self.repoID = repoID
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
        self.store = store
        self.differ = differ
        self.reverter = reverter
    }

    func refresh() throws {
        guard let sessionID, !sessionID.isEmpty else {
            loadedRecords = []
            records = []
            selectedRecordID = nil
            selectedFileSummaries = []
            selectedChanges = []
            statusText = "No edit session"
            errorText = nil
            return
        }

        let previousSelection = selectedRecordID
        loadedRecords = Array(try store.timeline(repoID: repoID, sessionID: sessionID).records.reversed())
        records = loadedRecords.map(Self.presentation(for:))

        if let previousSelection,
           records.contains(where: { $0.id == previousSelection }) {
            selectedRecordID = previousSelection
        } else {
            selectedRecordID = records.first?.id
        }

        updateSelectedDetails()
        statusText = records.count == 1 ? "1 edit" : "\(records.count) edits"
        errorText = nil
    }

    func select(recordID: UUID?) {
        selectedRecordID = recordID
        updateSelectedDetails()
    }

    func revertSelected() throws {
        guard let record = rawSelectedRecord() else {
            throw AIEditHistoryPanelError.noSelection
        }
        let result = try reverter.revert(record, in: workingDirectory)
        updateSelectedDetails()
        statusText = "Reverted \(result.revertedFiles.count) \(result.revertedFiles.count == 1 ? "file" : "files")"
        errorText = nil
    }

    func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func rawSelectedRecord() -> AIEditRecord? {
        guard let selectedRecordID else { return nil }
        return loadedRecords.first { $0.id == selectedRecordID }
    }

    private func updateSelectedDetails() {
        guard let record = rawSelectedRecord() else {
            selectedFileSummaries = []
            selectedChanges = []
            return
        }
        selectedFileSummaries = differ.fileSummaries(for: record)
        selectedChanges = record.changes.sorted {
            $0.filePath.localizedCaseInsensitiveCompare($1.filePath) == .orderedAscending
        }
    }

    private static func presentation(for record: AIEditRecord) -> AIEditRecordPresentation {
        let fileCount = record.changes.count
        return AIEditRecordPresentation(
            id: record.id,
            sessionID: record.sessionID,
            agentID: record.agentID,
            createdAt: record.createdAt,
            title: record.summary,
            detail: "\(fileCount) \(fileCount == 1 ? "file" : "files") - \(record.agentID)",
            summary: record.summary
        )
    }
}
