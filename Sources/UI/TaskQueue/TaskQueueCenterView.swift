// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskQueueCenterView.swift - Native queue management and enqueue surface.

import SwiftUI
import UniformTypeIdentifiers

enum TaskQueuePresentation {
    static func status(
        _ status: TaskQueueItemStatus,
        localizer: AppLocalizer
    ) -> String {
        let fallback: String
        switch status {
        case .scheduled: fallback = "Scheduled"
        case .queued: fallback = "Queued"
        case .running: fallback = "Running"
        case .retrying: fallback = "Retrying"
        case .succeeded: fallback = "Succeeded"
        case .failed: fallback = "Failed"
        case .cancelled: fallback = "Cancelled"
        }
        return localizer.string("taskQueue.status.\(status.rawValue)", fallback: fallback)
    }

    static func statusColor(_ status: TaskQueueItemStatus) -> Color {
        switch status {
        case .scheduled, .cancelled: return .secondary
        case .queued: return .cyan
        case .running: return .blue
        case .retrying: return .orange
        case .succeeded: return .green
        case .failed: return .red
        }
    }

    static func trigger(
        _ trigger: TaskQueueTrigger,
        localizer: AppLocalizer
    ) -> String {
        switch trigger {
        case .manual:
            return localizer.string("taskQueue.trigger.manual", fallback: "Manual")
        case .cron(let schedule):
            return String(
                format: localizer.string(
                    "taskQueue.trigger.cron.detail",
                    fallback: "Cron: %@ (%@)"
                ),
                schedule.expression,
                schedule.timeZoneIdentifier
            )
        case .event(let event):
            return String(
                format: localizer.string(
                    "taskQueue.trigger.event.detail",
                    fallback: "Event: %@"
                ),
                eventLabel(event, localizer: localizer)
            )
        }
    }

    static func eventLabel(
        _ event: PluginEvent,
        localizer: AppLocalizer
    ) -> String {
        let fallback = event.rawValue
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
        return localizer.string("taskQueue.event.\(event.rawValue)", fallback: fallback)
    }

    static func validationMessage(
        _ issue: TaskQueueDraftValidationIssue,
        localizer: AppLocalizer
    ) -> String {
        let key: String
        let fallback: String
        switch issue {
        case .invalidTaskID:
            key = "taskQueue.validation.taskID"
            fallback = "Enter a task ID containing letters or numbers."
        case .taskIDTooLong:
            key = "taskQueue.validation.taskIDTooLong"
            fallback = "Task ID must be 128 UTF-8 bytes or fewer."
        case .missingPrompt:
            key = "taskQueue.validation.prompt"
            fallback = "Enter a task prompt."
        case .promptTooLarge:
            key = "taskQueue.validation.promptTooLarge"
            fallback = "Task prompt must be 32 KB or smaller."
        case .missingPipeline:
            key = "taskQueue.validation.pipeline"
            fallback = "Choose an absolute pipeline JSON path."
        case .invalidWorktree:
            key = "taskQueue.validation.worktree"
            fallback = "Choose an absolute worktree path."
        case .invalidCron:
            key = "taskQueue.validation.cron"
            fallback = "Enter a valid five-field cron expression."
        case .invalidTimeZone:
            key = "taskQueue.validation.timeZone"
            fallback = "Enter a valid IANA time zone."
        case .missingEvent:
            key = "taskQueue.validation.event"
            fallback = "Choose an event trigger."
        case .invalidRetries:
            key = "taskQueue.validation.retries"
            fallback = "Retries must be between 0 and 5."
        case .invalidConcurrency:
            key = "taskQueue.validation.concurrency"
            fallback = "Step concurrency must be between 1 and 8."
        }
        return localizer.string(key, fallback: fallback)
    }
}

struct TaskQueueCenterView: View {
    @ObservedObject var viewModel: TaskQueueCenterViewModel
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    let onDismiss: () -> Void

    @State private var cancellationTask: TaskQueueItem?
    @State private var removalTask: TaskQueueItem?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                taskList
                    .frame(width: 310)
                Divider()
                detailPane
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .glassPanelBackground()
        .environment(\.locale, localizer.locale)
        .task {
            await viewModel.reload()
            while !Task.isCancelled {
                try? await Task<Never, Never>.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                await viewModel.reload(showProgress: false)
            }
        }
        .confirmationDialog(
            localizer.string("taskQueue.cancel.confirmTitle", fallback: "Cancel task?"),
            isPresented: Binding(
                get: { cancellationTask != nil },
                set: { if !$0 { cancellationTask = nil } }
            ),
            titleVisibility: .visible,
            presenting: cancellationTask
        ) { item in
            Button(
                localizer.string("taskQueue.cancel.action", fallback: "Cancel Task"),
                role: .destructive
            ) {
                cancellationTask = nil
                Task { await viewModel.cancel(taskID: item.id) }
            }
            Button(localizer.string("common.cancel", fallback: "Cancel"), role: .cancel) {
                cancellationTask = nil
            }
        } message: { item in
            Text(String(
                format: localizer.string(
                    "taskQueue.cancel.confirmMessage",
                    fallback: "Stop %@ and prevent future runs?"
                ),
                item.id
            ))
        }
        .confirmationDialog(
            localizer.string("taskQueue.remove.confirmTitle", fallback: "Remove task?"),
            isPresented: Binding(
                get: { removalTask != nil },
                set: { if !$0 { removalTask = nil } }
            ),
            titleVisibility: .visible,
            presenting: removalTask
        ) { item in
            Button(
                localizer.string("taskQueue.remove.action", fallback: "Remove Task"),
                role: .destructive
            ) {
                removalTask = nil
                Task { await viewModel.remove(taskID: item.id) }
            }
            Button(localizer.string("common.cancel", fallback: "Cancel"), role: .cancel) {
                removalTask = nil
            }
        } message: { item in
            Text(String(
                format: localizer.string(
                    "taskQueue.remove.confirmMessage",
                    fallback: "Remove %@ and its saved queue record?"
                ),
                item.id
            ))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(localizer.string("taskQueue.title", fallback: "Task Queue"))
                    .font(.title2.weight(.semibold))
                Text(taskCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(
                        localizer.string("taskQueue.loading", fallback: "Loading tasks")
                    )
            }
            Button {
                Task { await viewModel.reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(localizer.string("taskQueue.refresh", fallback: "Refresh task queue"))
            .disabled(viewModel.isLoading)

            Button {
                viewModel.startCreating()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help(localizer.string("taskQueue.new", fallback: "New task"))

            Button(localizer.string("common.done", fallback: "Done"), action: onDismiss)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var taskList: some View {
        Group {
            if viewModel.items.isEmpty, !viewModel.isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(localizer.string("taskQueue.empty", fallback: "No scheduled tasks"))
                        .font(.headline)
                    Button {
                        viewModel.startCreating()
                    } label: {
                        Label(
                            localizer.string("taskQueue.new", fallback: "New task"),
                            systemImage: "plus"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { viewModel.selectedTaskID },
                    set: { viewModel.selectTask($0) }
                )) {
                    ForEach(viewModel.items) { item in
                        TaskQueueRowView(item: item, localizer: localizer)
                            .tag(item.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private var detailPane: some View {
        VStack(spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.callout)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.08))
                Divider()
            }

            if viewModel.isCreating {
                TaskQueueComposerView(viewModel: viewModel, localizer: localizer)
            } else if let item = viewModel.selectedTask {
                TaskQueueDetailView(
                    item: item,
                    isCancelling: viewModel.cancellingTaskID == item.id,
                    isOperating: viewModel.operatingTaskID == item.id,
                    localizer: localizer,
                    onCancel: { cancellationTask = item },
                    onRerun: { Task { await viewModel.rerun(taskID: item.id) } },
                    onRemove: { removalTask = item }
                )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(localizer.string("taskQueue.select", fallback: "Select a task"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var taskCountText: String {
        let key = viewModel.items.count == 1
            ? "taskQueue.count.one"
            : "taskQueue.count.many"
        let fallback = viewModel.items.count == 1 ? "%d task" : "%d tasks"
        return String(
            format: localizer.string(key, fallback: fallback),
            viewModel.items.count
        )
    }
}

private struct TaskQueueRowView: View {
    let item: TaskQueueItem
    let localizer: AppLocalizer

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(TaskQueuePresentation.statusColor(item.status))
                .frame(width: 8, height: 8)
                .padding(.top, 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(TaskQueuePresentation.status(item.status, localizer: localizer))
                    Label(stepCountText, systemImage: "point.3.connected.trianglepath.dotted")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    private var stepCountText: String {
        let count = item.pipeline.steps.count
        let key = count == 1 ? "taskQueue.step.one" : "taskQueue.step.many"
        let fallback = count == 1 ? "%d step" : "%d steps"
        return String(format: localizer.string(key, fallback: fallback), count)
    }
}

private struct TaskQueueDetailView: View {
    let item: TaskQueueItem
    let isCancelling: Bool
    let isOperating: Bool
    let localizer: AppLocalizer
    let onCancel: () -> Void
    let onRerun: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.displayName)
                                .font(.title3.weight(.semibold))
                            if item.displayName != item.id {
                                Text(item.id)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        Spacer()
                        Label {
                            Text(TaskQueuePresentation.status(item.status, localizer: localizer))
                        } icon: {
                            Circle()
                                .fill(TaskQueuePresentation.statusColor(item.status))
                                .frame(width: 8, height: 8)
                        }
                        .font(.callout.weight(.medium))
                    }

                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                        detailRow(
                            localizer.string("taskQueue.detail.trigger", fallback: "Trigger"),
                            TaskQueuePresentation.trigger(item.trigger, localizer: localizer)
                        )
                        detailRow(
                            localizer.string("taskQueue.detail.runs", fallback: "Runs"),
                            "\(item.totalRunCount)"
                        )
                        detailRow(
                            localizer.string("taskQueue.detail.attempt", fallback: "Attempt"),
                            "\(item.retryAttempt)"
                        )
                        detailRow(
                            localizer.string("taskQueue.detail.retryLimit", fallback: "Retry limit"),
                            "\(item.maximumRetries)"
                        )
                        detailRow(
                            localizer.string("taskQueue.detail.concurrency", fallback: "Step concurrency"),
                            "\(item.maximumParallelSteps)"
                        )
                        GridRow {
                            Text(localizer.string("taskQueue.detail.updated", fallback: "Updated"))
                                .foregroundStyle(.secondary)
                            Text(item.updatedAt, format: .dateTime.year().month().day().hour().minute().second())
                        }
                        if let nextRunAt = item.nextRunAt {
                            GridRow {
                                Text(localizer.string("taskQueue.detail.nextRun", fallback: "Next run"))
                                    .foregroundStyle(.secondary)
                                Text(nextRunAt, format: .dateTime.year().month().day().hour().minute())
                            }
                        }
                    }
                    .font(.callout)

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text(localizer.string("taskQueue.detail.pipeline", fallback: "Pipeline"))
                            .font(.headline)
                        ForEach(item.pipeline.steps) { step in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(step.id)
                                        .font(.body.monospaced().weight(.medium))
                                    Spacer()
                                    Text(step.provider.displayName)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                if !step.dependsOn.isEmpty {
                                    Text(String(
                                        format: localizer.string(
                                            "taskQueue.detail.dependsOn",
                                            fallback: "Depends on: %@"
                                        ),
                                        step.dependsOn.joined(separator: ", ")
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                if let worktree = step.worktree {
                                    Text(worktree)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .textSelection(.enabled)
                                }
                            }
                            if step.id != item.pipeline.steps.last?.id {
                                Divider()
                            }
                        }
                    }

                    if let lastError = item.lastError {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text(localizer.string("taskQueue.detail.lastError", fallback: "Last error"))
                                .font(.headline)
                            Text(lastError)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(22)
            }

            if !item.status.isFinished {
                Divider()
                HStack {
                    Spacer()
                    Button(role: .destructive, action: onCancel) {
                        if isCancelling {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(
                                localizer.string("taskQueue.cancel.action", fallback: "Cancel Task"),
                                systemImage: "stop.circle"
                            )
                        }
                    }
                    .disabled(isCancelling || isOperating)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            } else {
                Divider()
                HStack(spacing: 10) {
                    Spacer()
                    Button(action: onRerun) {
                        Label(
                            localizer.string("taskQueue.rerun.action", fallback: "Run Again"),
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .disabled(isOperating)
                    Button(role: .destructive, action: onRemove) {
                        if isOperating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(
                                localizer.string("taskQueue.remove.action", fallback: "Remove Task"),
                                systemImage: "trash"
                            )
                        }
                    }
                    .disabled(isOperating)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private struct TaskQueueComposerView: View {
    @ObservedObject var viewModel: TaskQueueCenterViewModel
    let localizer: AppLocalizer

    @State private var isChoosingPipeline = false
    @State private var isChoosingWorktree = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(localizer.string("taskQueue.composer.title", fallback: "New Task"))
                        .font(.title3.weight(.semibold))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(localizer.string("taskQueue.composer.id", fallback: "Task ID"))
                            .font(.headline)
                        TextField(
                            localizer.string(
                                "taskQueue.composer.taskIDPlaceholder",
                                fallback: "task-id"
                            ),
                            text: $viewModel.draft.taskID
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    Picker(
                        localizer.string("taskQueue.composer.source", fallback: "Source"),
                        selection: $viewModel.draft.sourceMode
                    ) {
                        Text(localizer.string("taskQueue.source.prompt", fallback: "Prompt"))
                            .tag(TaskQueueDraftSourceMode.prompt)
                        Text(localizer.string("taskQueue.source.pipeline", fallback: "Pipeline JSON"))
                            .tag(TaskQueueDraftSourceMode.pipeline)
                    }
                    .pickerStyle(.segmented)

                    if viewModel.draft.sourceMode == .prompt {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(localizer.string("taskQueue.composer.provider", fallback: "Provider"))
                                .font(.headline)
                            Picker("", selection: $viewModel.draft.provider) {
                                ForEach(AgentTeamProvider.allCases, id: \.rawValue) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 280)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(localizer.string("taskQueue.composer.prompt", fallback: "Task prompt"))
                                .font(.headline)
                            TextEditor(text: $viewModel.draft.prompt)
                                .font(.system(size: 13))
                                .frame(minHeight: 110)
                                .padding(6)
                                .background(Color.secondary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.2))
                                )
                        }
                    } else {
                        pathField(
                            title: localizer.string(
                                "taskQueue.composer.pipeline",
                                fallback: "Pipeline JSON"
                            ),
                            placeholder: "/path/to/pipeline.json",
                            text: $viewModel.draft.pipelinePath,
                            help: localizer.string(
                                "taskQueue.composer.choosePipeline",
                                fallback: "Choose pipeline JSON"
                            ),
                            action: { isChoosingPipeline = true }
                        )
                    }

                    pathField(
                        title: localizer.string("taskQueue.composer.worktree", fallback: "Worktree"),
                        placeholder: "/path/to/worktree",
                        text: $viewModel.draft.worktree,
                        help: localizer.string(
                            "taskQueue.composer.chooseWorktree",
                            fallback: "Choose worktree"
                        ),
                        action: { isChoosingWorktree = true }
                    )

                    Picker(
                        localizer.string("taskQueue.composer.trigger", fallback: "Trigger"),
                        selection: $viewModel.draft.triggerMode
                    ) {
                        Text(localizer.string("taskQueue.trigger.manual", fallback: "Manual"))
                            .tag(TaskQueueDraftTriggerMode.manual)
                        Text(localizer.string("taskQueue.trigger.cron", fallback: "Schedule"))
                            .tag(TaskQueueDraftTriggerMode.cron)
                        Text(localizer.string("taskQueue.trigger.event", fallback: "Event"))
                            .tag(TaskQueueDraftTriggerMode.event)
                    }
                    .pickerStyle(.segmented)

                    switch viewModel.draft.triggerMode {
                    case .manual:
                        EmptyView()
                    case .cron:
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(localizer.string(
                                    "taskQueue.composer.cron",
                                    fallback: "Cron expression"
                                ))
                                .font(.headline)
                                TextField("0 9 * * 1-5", text: $viewModel.draft.cronExpression)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body.monospaced())
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(localizer.string(
                                    "taskQueue.composer.timeZone",
                                    fallback: "Time zone"
                                ))
                                .font(.headline)
                                TextField(
                                    localizer.string(
                                        "taskQueue.composer.timeZonePlaceholder",
                                        fallback: "America/Tegucigalpa"
                                    ),
                                    text: $viewModel.draft.timeZoneIdentifier
                                )
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                    case .event:
                        VStack(alignment: .leading, spacing: 6) {
                            Text(localizer.string("taskQueue.composer.event", fallback: "Plugin event"))
                                .font(.headline)
                            Picker("", selection: $viewModel.draft.event) {
                                ForEach(TaskQueueEnqueueDraft.supportedEvents, id: \.rawValue) { event in
                                    Text(TaskQueuePresentation.eventLabel(event, localizer: localizer))
                                        .tag(event)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 320)
                        }
                    }

                    HStack(spacing: 28) {
                        Stepper(value: $viewModel.draft.maximumRetries, in: 0...5) {
                            LabeledContent(
                                localizer.string("taskQueue.composer.retries", fallback: "Retries"),
                                value: "\(viewModel.draft.maximumRetries)"
                            )
                        }
                        Stepper(value: $viewModel.draft.maximumParallelSteps, in: 1...8) {
                            LabeledContent(
                                localizer.string(
                                    "taskQueue.composer.concurrency",
                                    fallback: "Step concurrency"
                                ),
                                value: "\(viewModel.draft.maximumParallelSteps)"
                            )
                        }
                    }

                    if let issue = viewModel.validationIssue {
                        Label(
                            TaskQueuePresentation.validationMessage(issue, localizer: localizer),
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(22)
            }

            Divider()
            HStack {
                Button(
                    localizer.string("taskQueue.composer.discard", fallback: "Discard"),
                    action: viewModel.stopCreating
                )
                .disabled(viewModel.items.isEmpty || viewModel.isSubmitting)
                Spacer()
                Button {
                    Task { await viewModel.enqueueDraft() }
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            localizer.string("taskQueue.composer.enqueue", fallback: "Enqueue"),
                            systemImage: "calendar.badge.plus"
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canEnqueue)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .fileImporter(
            isPresented: $isChoosingPipeline,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            applyImportedURL(result, to: \TaskQueueEnqueueDraft.pipelinePath)
        }
        .fileImporter(
            isPresented: $isChoosingWorktree,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            applyImportedURL(result, to: \TaskQueueEnqueueDraft.worktree)
        }
    }

    private func pathField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            HStack(spacing: 8) {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                Button(action: action) {
                    Image(systemName: "folder")
                }
                .help(help)
            }
        }
    }

    private func applyImportedURL(
        _ result: Result<[URL], Error>,
        to keyPath: WritableKeyPath<TaskQueueEnqueueDraft, String>
    ) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            viewModel.draft[keyPath: keyPath] = url.path
        case .failure(let error):
            viewModel.setExternalError(error)
        }
    }
}
