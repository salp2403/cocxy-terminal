// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskQueueComposerView.swift - Task queue enqueue form.

import SwiftUI
import UniformTypeIdentifiers

struct TaskQueueComposerView: View {
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
