// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskQueueCenterViewModel.swift - Persistent task queue presentation state.

import Combine
import Foundation
import os.log

enum TaskQueueDraftSourceMode: String, CaseIterable, Identifiable, Sendable {
    case prompt
    case pipeline

    var id: String { rawValue }
}

enum TaskQueueDraftTriggerMode: String, CaseIterable, Identifiable, Sendable {
    case manual
    case cron
    case event

    var id: String { rawValue }
}

enum TaskQueueDraftValidationIssue: Equatable, Sendable {
    case invalidTaskID
    case taskIDTooLong
    case missingPrompt
    case promptTooLarge
    case missingPipeline
    case invalidWorktree
    case invalidProject
    case invalidCron
    case invalidTimeZone
    case missingEvent
    case invalidRetries
    case invalidConcurrency
}

enum TaskQueueDraftError: Error, CustomStringConvertible {
    case invalidDraft(TaskQueueDraftValidationIssue)
    case pipelineFileUnavailable
    case invalidPipeline(String)

    var description: String {
        switch self {
        case .invalidDraft(let issue):
            return "Task queue draft is invalid: \(issue)"
        case .pipelineFileUnavailable:
            return "The selected pipeline JSON file is unavailable or too large"
        case .invalidPipeline(let reason):
            return "The selected pipeline JSON is invalid: \(reason)"
        }
    }
}

struct TaskQueueEnqueueDraft: Equatable, Sendable {
    static let supportedEvents = TaskQueueTrigger.supportedEvents

    var taskID: String
    var sourceMode: TaskQueueDraftSourceMode = .prompt
    var provider: AgentTeamProvider = .claudeCode
    var prompt = ""
    var pipelinePath = ""
    var worktree: String
    var project: String?
    var triggerMode: TaskQueueDraftTriggerMode = .manual
    var cronExpression = "0 9 * * 1-5"
    var timeZoneIdentifier = TimeZone.current.identifier
    var event = supportedEvents.first ?? .sessionStart
    var maximumRetries = 0
    var maximumParallelSteps = 2

    init(
        taskID: String = TaskQueueEnqueueDraft.makeDefaultTaskID(),
        worktree: String,
        project: String? = nil
    ) {
        self.taskID = taskID
        self.worktree = worktree
        self.project = project
    }

    var validationIssue: TaskQueueDraftValidationIssue? {
        let normalizedID = AgentPipelineStep.normalizedID(taskID)
        guard !normalizedID.isEmpty else { return .invalidTaskID }
        guard normalizedID.utf8.count <= TaskQueueItem.maximumIDBytes else {
            return .taskIDTooLong
        }

        let expandedWorktree = (worktree as NSString).expandingTildeInPath
        guard NSString(string: expandedWorktree).isAbsolutePath else {
            return .invalidWorktree
        }
        if let project {
            let expandedProject = (project as NSString).expandingTildeInPath
            guard NSString(string: expandedProject).isAbsolutePath else {
                return .invalidProject
            }
        }

        switch sourceMode {
        case .prompt:
            let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedPrompt.isEmpty else { return .missingPrompt }
            guard normalizedPrompt.utf8.count <= AgentPipelineStep.maximumPromptBytes else {
                return .promptTooLarge
            }
        case .pipeline:
            let expandedPath = (pipelinePath as NSString).expandingTildeInPath
            guard !expandedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  NSString(string: expandedPath).isAbsolutePath else {
                return .missingPipeline
            }
        }

        switch triggerMode {
        case .manual:
            break
        case .cron:
            let zone = timeZoneIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard TimeZone(identifier: zone) != nil else { return .invalidTimeZone }
            guard (try? CronSchedule(
                expression: cronExpression,
                timeZoneIdentifier: zone
            )) != nil else {
                return .invalidCron
            }
        case .event:
            guard Self.supportedEvents.contains(event) else { return .missingEvent }
        }

        guard (0...5).contains(maximumRetries) else { return .invalidRetries }
        guard (1...8).contains(maximumParallelSteps) else { return .invalidConcurrency }
        return nil
    }

    func makeItem(now: Date = Date()) throws -> TaskQueueItem {
        if let validationIssue {
            throw TaskQueueDraftError.invalidDraft(validationIssue)
        }

        let expandedWorktree = (worktree as NSString).expandingTildeInPath
        let canonicalWorktree = try AppDelegate.canonicalTaskQueueWorktree(expandedWorktree)
        let canonicalProject = try project.map {
            try AppDelegate.canonicalTaskQueueWorktree(($0 as NSString).expandingTildeInPath)
        }
        let pipeline: AgentPipeline

        switch sourceMode {
        case .prompt:
            pipeline = try AgentPipeline(
                id: taskID,
                steps: [AgentPipelineStep(
                    id: "run",
                    provider: provider,
                    prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                    worktree: canonicalWorktree,
                    project: canonicalProject
                )]
            )
        case .pipeline:
            let expandedPath = (pipelinePath as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expandedPath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard let data = SocketPrivilegedCommandSecurity.boundedFileData(at: url) else {
                throw TaskQueueDraftError.pipelineFileUnavailable
            }
            do {
                pipeline = try JSONDecoder().decode(AgentPipeline.self, from: data)
            } catch {
                throw TaskQueueDraftError.invalidPipeline(String(describing: error))
            }
        }

        let normalizedPipeline = try AppDelegate.normalizedTaskQueuePipeline(
            pipeline,
            defaultWorktree: canonicalWorktree,
            defaultProject: canonicalProject
        )
        return try TaskQueueItem(
            id: taskID,
            pipeline: normalizedPipeline,
            project: canonicalProject,
            trigger: try makeTrigger(),
            maximumRetries: maximumRetries,
            maximumParallelSteps: maximumParallelSteps,
            now: now
        )
    }

    static func makeDefaultTaskID() -> String {
        "task-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func makeTrigger() throws -> TaskQueueTrigger {
        switch triggerMode {
        case .manual:
            return .manual
        case .cron:
            return .cron(try CronSchedule(
                expression: cronExpression,
                timeZoneIdentifier: timeZoneIdentifier
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        case .event:
            return try TaskQueueTrigger.eventTrigger(event)
        }
    }
}

@MainActor
struct TaskQueueCenterOperations {
    let load: @MainActor () async throws -> [TaskQueueItem]
    let enqueue: @MainActor (TaskQueueEnqueueDraft) async throws -> TaskQueueItem
    let cancel: @MainActor (String) async throws -> TaskQueueItem
    let rerun: @MainActor (String) async throws -> TaskQueueItem
    let remove: @MainActor (String) async throws -> TaskQueueItem
}

@MainActor
final class TaskQueueCenterViewModel: ObservableObject {
    private enum ErrorSource {
        case load
        case operation
    }

    private enum PresentedError {
        case unavailable
        case selection
    }

    nonisolated private static let logger = Logger(
        subsystem: "dev.cocxy.terminal",
        category: "TaskQueuePresentation"
    )

    @Published private(set) var items: [TaskQueueItem] = []
    @Published var selectedTaskID: String?
    @Published private(set) var isCreating = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var cancellingTaskID: String?
    @Published private(set) var operatingTaskID: String?
    @Published private(set) var errorMessage: String?
    @Published var draft: TaskQueueEnqueueDraft

    private let defaultWorktree: String
    private let defaultProject: String?
    private let operations: TaskQueueCenterOperations
    private var localizer: AppLocalizer
    private var loadRevision = 0
    private var hasLoaded = false
    private var errorSource: ErrorSource?
    private var presentedError: PresentedError?

    init(
        defaultWorktree: String,
        defaultProject: String? = nil,
        localizer: AppLocalizer,
        operations: TaskQueueCenterOperations
    ) {
        self.defaultWorktree = defaultWorktree
        self.defaultProject = defaultProject
        self.localizer = localizer
        self.operations = operations
        draft = TaskQueueEnqueueDraft(worktree: defaultWorktree, project: defaultProject)
    }

    var selectedTask: TaskQueueItem? {
        guard !isCreating, let selectedTaskID else { return nil }
        return items.first { $0.id == selectedTaskID }
    }

    var validationIssue: TaskQueueDraftValidationIssue? {
        draft.validationIssue
    }

    var canEnqueue: Bool {
        !isSubmitting && validationIssue == nil
    }

    func selectTask(_ taskID: String?) {
        selectedTaskID = taskID
        if taskID != nil {
            isCreating = false
            clearError()
        }
    }

    func startCreating() {
        draft = TaskQueueEnqueueDraft(worktree: defaultWorktree, project: defaultProject)
        isCreating = true
        clearError()
    }

    func stopCreating() {
        isCreating = false
        if selectedTaskID == nil {
            selectedTaskID = items.first?.id
        }
        clearError()
    }

    func setExternalError(_ error: Error) {
        present(error, as: .selection, source: .operation)
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        if let presentedError {
            errorMessage = localizedMessage(for: presentedError)
        }
    }

    func reload(showProgress: Bool = true) async {
        loadRevision += 1
        let revision = loadRevision
        if showProgress { isLoading = true }

        do {
            let loadedItems = try await operations.load()
            guard revision == loadRevision else { return }
            let isFirstLoad = !hasLoaded
            hasLoaded = true
            items = loadedItems
            isLoading = false
            if showProgress || errorSource == .load {
                clearError()
            }

            if let selectedTaskID,
               !loadedItems.contains(where: { $0.id == selectedTaskID }) {
                self.selectedTaskID = nil
            }
            if isFirstLoad, loadedItems.isEmpty {
                isCreating = true
            } else if !isCreating, selectedTaskID == nil {
                selectedTaskID = loadedItems.first?.id
            }
        } catch {
            guard revision == loadRevision else { return }
            isLoading = false
            if showProgress || items.isEmpty {
                present(error, as: .unavailable, source: .load)
            }
        }
    }

    func enqueueDraft() async {
        guard canEnqueue else { return }
        isSubmitting = true
        clearError()
        do {
            let item = try await operations.enqueue(draft)
            upsert(item)
            selectedTaskID = item.id
            isCreating = false
            draft = TaskQueueEnqueueDraft(worktree: defaultWorktree, project: defaultProject)
            isSubmitting = false
            await reload(showProgress: false)
        } catch {
            isSubmitting = false
            present(error, as: .unavailable, source: .operation)
        }
    }

    func cancel(taskID: String) async {
        guard cancellingTaskID == nil, operatingTaskID == nil else { return }
        cancellingTaskID = taskID
        clearError()
        do {
            let item = try await operations.cancel(taskID)
            upsert(item)
            cancellingTaskID = nil
            await reload(showProgress: false)
        } catch {
            cancellingTaskID = nil
            present(error, as: .unavailable, source: .operation)
        }
    }

    func rerun(taskID: String) async {
        guard operatingTaskID == nil, cancellingTaskID == nil else { return }
        operatingTaskID = taskID
        clearError()
        do {
            let item = try await operations.rerun(taskID)
            upsert(item)
            operatingTaskID = nil
            await reload(showProgress: false)
        } catch {
            operatingTaskID = nil
            present(error, as: .unavailable, source: .operation)
        }
    }

    func remove(taskID: String) async {
        guard operatingTaskID == nil, cancellingTaskID == nil else { return }
        operatingTaskID = taskID
        clearError()
        do {
            _ = try await operations.remove(taskID)
            items.removeAll { $0.id == taskID }
            if selectedTaskID == taskID {
                selectedTaskID = items.first?.id
            }
            operatingTaskID = nil
            await reload(showProgress: false)
        } catch {
            operatingTaskID = nil
            present(error, as: .unavailable, source: .operation)
        }
    }

    private func present(
        _ error: any Error,
        as presentedError: PresentedError,
        source: ErrorSource
    ) {
        Self.logger.error(
            "Task queue operation failed: \(String(describing: error), privacy: .private)"
        )
        self.presentedError = presentedError
        errorMessage = localizedMessage(for: presentedError)
        errorSource = source
    }

    private func localizedMessage(for error: PresentedError) -> String {
        switch error {
        case .unavailable:
            return localizer.string(
                "taskQueue.error.unavailable",
                fallback: "The task queue action could not be completed."
            )
        case .selection:
            return localizer.string(
                "taskQueue.error.selection",
                fallback: "The selected file or folder could not be used."
            )
        }
    }

    private func upsert(_ item: TaskQueueItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
    }

    private func clearError() {
        errorMessage = nil
        errorSource = nil
        presentedError = nil
    }
}
