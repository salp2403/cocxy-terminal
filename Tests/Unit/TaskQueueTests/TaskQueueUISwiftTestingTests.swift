// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskQueueUISwiftTestingTests.swift - Task queue center behavior and wiring.

import Foundation
import SwiftUI
import Testing
@testable import CocxyTerminal

@Suite("Task queue UI")
@MainActor
struct TaskQueueUISwiftTestingTests {
    @Test("inline and JSON drafts build normalized queue items")
    func draftsBuildQueueItems() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        var inline = TaskQueueEnqueueDraft(taskID: "Daily Review", worktree: root.path)
        inline.provider = .codex
        inline.prompt = "Review the current changes"
        inline.triggerMode = .cron
        inline.cronExpression = "*/15 * * * *"
        inline.timeZoneIdentifier = "UTC"
        inline.maximumRetries = 2
        inline.maximumParallelSteps = 3

        let inlineItem = try inline.makeItem(now: Date(timeIntervalSince1970: 0))
        #expect(inlineItem.id == "daily-review")
        #expect(inlineItem.pipeline.steps.first?.provider == .codex)
        #expect(inlineItem.pipeline.steps.first?.worktree == root.path)
        #expect(inlineItem.maximumRetries == 2)
        #expect(inlineItem.maximumParallelSteps == 3)
        #expect(inlineItem.status == .scheduled)
        guard case .cron(let schedule) = inlineItem.trigger else {
            Issue.record("Expected a cron trigger")
            return
        }
        #expect(schedule.expression == "*/15 * * * *")
        #expect(schedule.timeZoneIdentifier == "UTC")

        let child = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        let pipeline = try AgentPipeline(
            id: "review-dag",
            name: "Review DAG",
            steps: [AgentPipelineStep(
                id: "inspect",
                provider: .claudeCode,
                prompt: "Inspect",
                worktree: "child"
            )]
        )
        let pipelineURL = root.appendingPathComponent("pipeline.json")
        try JSONEncoder().encode(pipeline).write(to: pipelineURL, options: .atomic)

        var imported = TaskQueueEnqueueDraft(taskID: "Imported", worktree: root.path)
        imported.sourceMode = .pipeline
        imported.pipelinePath = pipelineURL.path
        imported.triggerMode = .event
        imported.event = .tabCreated

        let importedItem = try imported.makeItem()
        #expect(importedItem.pipeline.id == "review-dag")
        #expect(importedItem.pipeline.steps.first?.worktree == child.path)
        #expect(importedItem.status == .scheduled)
        #expect(importedItem.nextRunAt == nil)
        #expect(importedItem.trigger == .event(.tabCreated))
    }

    @Test("draft validation rejects unsafe or inconsistent queue inputs")
    func draftValidationRejectsInvalidInputs() {
        var draft = TaskQueueEnqueueDraft(taskID: "---", worktree: "/tmp")
        draft.prompt = "run"
        #expect(draft.validationIssue == .invalidTaskID)

        draft.taskID = String(repeating: "a", count: TaskQueueItem.maximumIDBytes + 1)
        #expect(draft.validationIssue == .taskIDTooLong)

        draft.taskID = "valid"
        draft.worktree = "relative"
        #expect(draft.validationIssue == .invalidWorktree)

        draft.worktree = "/tmp"
        draft.triggerMode = .event
        draft.event = .taskRunStarted
        #expect(draft.validationIssue == .missingEvent)

        draft.event = .sessionStart
        draft.maximumRetries = 6
        #expect(draft.validationIssue == .invalidRetries)

        draft.maximumRetries = 0
        draft.maximumParallelSteps = 0
        #expect(draft.validationIssue == .invalidConcurrency)
    }

    @Test("center model loads, enqueues, selects, and cancels")
    func centerModelCoordinatesMutations() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = TaskQueueUITestBackend()
        let model = TaskQueueCenterViewModel(
            defaultWorktree: root.path,
            operations: TaskQueueCenterOperations(
                load: { backend.load() },
                enqueue: { draft in try backend.enqueue(draft) },
                cancel: { taskID in try backend.cancel(taskID) },
                rerun: { taskID in try backend.rerun(taskID) },
                remove: { taskID in try backend.remove(taskID) }
            )
        )

        await model.reload()
        #expect(model.items.isEmpty)
        #expect(model.isCreating)

        model.setExternalError(TaskQueueDraftError.pipelineFileUnavailable)
        await model.reload(showProgress: false)
        #expect(model.errorMessage != nil)
        model.startCreating()
        #expect(model.errorMessage == nil)

        model.draft.taskID = "ui-task"
        model.draft.prompt = "Run the UI task"
        #expect(model.canEnqueue)
        await model.enqueueDraft()

        #expect(model.items.map(\.id) == ["ui-task"])
        #expect(model.selectedTaskID == "ui-task")
        #expect(model.selectedTask?.status == .queued)
        #expect(!model.isCreating)

        await model.cancel(taskID: "ui-task")
        #expect(model.selectedTask?.status == .cancelled)
        #expect(model.cancellingTaskID == nil)
        #expect(model.errorMessage == nil)

        await model.rerun(taskID: "ui-task")
        #expect(model.selectedTask?.status == .queued)
        #expect(model.operatingTaskID == nil)
        await model.cancel(taskID: "ui-task")
        await model.remove(taskID: "ui-task")
        #expect(model.items.isEmpty)
        #expect(model.selectedTaskID == nil)
        #expect(model.operatingTaskID == nil)
    }

    @Test("both palettes expose the queue center")
    func paletteDiscoversQueueCenter() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let classicIDs = Set(controller.createWiredCommandPaletteEngine().allActions.map(\.id))
        let auroraIDs = Set(controller.buildAuroraPaletteActions().map(\.id))

        #expect(classicIDs.contains("taskQueue.manage"))
        #expect(auroraIDs.contains("taskQueue.manage"))
    }

    @Test("queue presentation localizes status and palette copy in Spanish")
    func queuePresentationLocalizesToSpanish() throws {
        let localizer = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(localizationBundle())
        )

        #expect(
            localizer.string("command.taskQueue.manage.name", fallback: "Task Queue...")
                == "Cola de tareas..."
        )
        #expect(
            TaskQueuePresentation.status(.running, localizer: localizer)
                == "En ejecución"
        )
        #expect(
            TaskQueuePresentation.eventLabel(.tabCreated, localizer: localizer)
                == "Pestaña creada"
        )
    }

    @Test("queue presentation resolves locale-aware layout direction")
    func queuePresentationResolvesLocaleAwareLayoutDirection() throws {
        let bundle = try #require(localizationBundle())
        let arabic = AppLocalizer(
            languagePreference: .arabic,
            bundle: bundle
        )
        let english = AppLocalizer(
            languagePreference: .english,
            bundle: bundle
        )

        #expect(TaskQueuePresentation.layoutDirection(localizer: arabic) == .rightToLeft)
        #expect(TaskQueuePresentation.layoutDirection(localizer: english) == .leftToRight)
    }

    @Test("queue center view constructs with bounded controls")
    func queueCenterViewConstructs() {
        let model = TaskQueueCenterViewModel(
            defaultWorktree: "/tmp",
            operations: TaskQueueCenterOperations(
                load: { [] },
                enqueue: { draft in try draft.makeItem() },
                cancel: { _ in throw TaskQueueError.taskNotFound("missing") },
                rerun: { _ in throw TaskQueueError.taskNotFound("missing") },
                remove: { _ in throw TaskQueueError.taskNotFound("missing") }
            )
        )
        _ = TaskQueueCenterView(
            viewModel: model,
            onDismiss: {}
        ).body
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-task-queue-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}

@MainActor
private final class TaskQueueUITestBackend {
    private var items: [TaskQueueItem] = []

    func load() -> [TaskQueueItem] {
        items
    }

    func enqueue(_ draft: TaskQueueEnqueueDraft) throws -> TaskQueueItem {
        let item = try draft.makeItem(now: Date(timeIntervalSince1970: 100))
        items.insert(item, at: 0)
        return item
    }

    func cancel(_ taskID: String) throws -> TaskQueueItem {
        guard let index = items.firstIndex(where: { $0.id == taskID }) else {
            throw TaskQueueError.taskNotFound(taskID)
        }
        var item = items[index]
        item.status = .cancelled
        item.nextRunAt = nil
        item.completedAt = Date(timeIntervalSince1970: 200)
        item.updatedAt = Date(timeIntervalSince1970: 200)
        items[index] = item
        return item
    }

    func rerun(_ taskID: String) throws -> TaskQueueItem {
        guard let index = items.firstIndex(where: { $0.id == taskID }) else {
            throw TaskQueueError.taskNotFound(taskID)
        }
        guard items[index].status.isFinished else {
            throw TaskQueueError.taskNotFinished(taskID)
        }
        var item = items[index]
        item.status = .queued
        item.nextRunAt = Date(timeIntervalSince1970: 300)
        item.completedAt = nil
        item.updatedAt = Date(timeIntervalSince1970: 300)
        items[index] = item
        return item
    }

    func remove(_ taskID: String) throws -> TaskQueueItem {
        guard let index = items.firstIndex(where: { $0.id == taskID }) else {
            throw TaskQueueError.taskNotFound(taskID)
        }
        guard items[index].status.isFinished else {
            throw TaskQueueError.taskNotFinished(taskID)
        }
        return items.remove(at: index)
    }
}
