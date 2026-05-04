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
    private enum StatusState: Equatable {
        case noEdits
        case noSession
        case edits(Int)
        case reverted(Int)
    }

    @Published private(set) var records: [AIEditRecordPresentation] = []
    @Published var selectedRecordID: UUID?
    @Published private(set) var selectedFileSummaries: [AIEditFileSummary] = []
    @Published private(set) var selectedChanges: [AIEditChange] = []
    @Published private(set) var statusText: String
    @Published private(set) var errorText: String?

    let repoID: String
    let sessionID: String?
    let workingDirectory: URL

    private let store: AIEditStore
    private let differ: AIEditDiffer
    private let reverter: any AIEditReverting
    private var localizer: AppLocalizer
    private var statusState: StatusState = .noEdits
    private var currentError: Error?
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
        reverter: any AIEditReverting = AIEditReverter(),
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.repoID = repoID
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
        self.store = store
        self.differ = differ
        self.reverter = reverter
        self.localizer = localizer
        self.statusText = Self.localizedStatusText(.noEdits, localizer: localizer)
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        let selected = selectedRecordID
        records = loadedRecords.map { Self.presentation(for: $0, localizer: localizer) }
        if let selected,
           records.contains(where: { $0.id == selected }) {
            selectedRecordID = selected
        } else {
            selectedRecordID = records.first?.id
        }
        statusText = Self.localizedStatusText(statusState, localizer: localizer)
        if let currentError {
            errorText = Self.localizedErrorDescription(currentError, localizer: localizer)
        }
    }

    func refresh() throws {
        guard let sessionID, !sessionID.isEmpty else {
            loadedRecords = []
            records = []
            selectedRecordID = nil
            selectedFileSummaries = []
            selectedChanges = []
            setStatus(.noSession)
            currentError = nil
            errorText = nil
            return
        }

        let previousSelection = selectedRecordID
        loadedRecords = Array(try store.timeline(repoID: repoID, sessionID: sessionID).records.reversed())
        records = loadedRecords.map { Self.presentation(for: $0, localizer: localizer) }

        if let previousSelection,
           records.contains(where: { $0.id == previousSelection }) {
            selectedRecordID = previousSelection
        } else {
            selectedRecordID = records.first?.id
        }

        updateSelectedDetails()
        setStatus(.edits(records.count))
        currentError = nil
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
        setStatus(.reverted(result.revertedFiles.count))
        currentError = nil
        errorText = nil
    }

    func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            currentError = error
            errorText = Self.localizedErrorDescription(error, localizer: localizer)
        }
    }

    private func setStatus(_ status: StatusState) {
        statusState = status
        statusText = Self.localizedStatusText(status, localizer: localizer)
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

    private static func presentation(
        for record: AIEditRecord,
        localizer: AppLocalizer
    ) -> AIEditRecordPresentation {
        let fileCount = record.changes.count
        return AIEditRecordPresentation(
            id: record.id,
            sessionID: record.sessionID,
            agentID: record.agentID,
            createdAt: record.createdAt,
            title: record.summary,
            detail: "\(localizedFileCount(fileCount, localizer: localizer)) - \(record.agentID)",
            summary: record.summary
        )
    }

    private static func localizedStatusText(
        _ status: StatusState,
        localizer: AppLocalizer
    ) -> String {
        switch status {
        case .noEdits:
            return localizer.string("aiEditHistory.status.noEdits", fallback: "No edits")
        case .noSession:
            return localizer.string("aiEditHistory.status.noSession", fallback: "No edit session")
        case .edits(let count):
            return localizedEditCount(count, localizer: localizer)
        case .reverted(let count):
            return String(
                format: localizer.string(
                    "aiEditHistory.status.reverted",
                    fallback: "Reverted %@"
                ),
                localizedFileCount(count, localizer: localizer)
            )
        }
    }

    private static func localizedEditCount(_ count: Int, localizer: AppLocalizer) -> String {
        String(
            format: localizer.string(
                count == 1
                ? "aiEditHistory.count.edit.one"
                : "aiEditHistory.count.edit.many",
                fallback: count == 1 ? "%d edit" : "%d edits"
            ),
            count
        )
    }

    private static func localizedFileCount(_ count: Int, localizer: AppLocalizer) -> String {
        String(
            format: localizer.string(
                count == 1
                ? "aiEditHistory.count.file.one"
                : "aiEditHistory.count.file.many",
                fallback: count == 1 ? "%d file" : "%d files"
            ),
            count
        )
    }

    private static func localizedErrorDescription(
        _ error: Error,
        localizer: AppLocalizer
    ) -> String {
        if let panelError = error as? AIEditHistoryPanelError {
            switch panelError {
            case .noSession:
                return localizer.string(
                    "aiEditHistory.error.noSession",
                    fallback: "No agent edit session is selected."
                )
            case .noSelection:
                return localizer.string(
                    "aiEditHistory.error.noSelection",
                    fallback: "No edit is selected."
                )
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

}
