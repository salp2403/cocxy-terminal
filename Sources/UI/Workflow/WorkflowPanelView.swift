// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorkflowPanelView.swift - SwiftUI workflow editor and run output panel.

import SwiftUI

struct WorkflowPanelView: View {
    @StateObject private var viewModel: WorkflowPanelViewModel
    let onClose: (() -> Void)?

    init(viewModel: WorkflowPanelViewModel, onClose: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                TextEditor(text: $viewModel.sourceText)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(minWidth: 320)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.stepPresentations) { step in
                            WorkflowStepPanel(step: step)
                        }
                    }
                    .padding(12)
                }
                .frame(minWidth: 280)
            }
        }
        .glassPanelBackground()
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Label(viewModel.workflowID, systemImage: "arrow.triangle.branch")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let errorText = viewModel.errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else {
                Text(viewModel.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                try? viewModel.save()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .controlSize(.small)

            Button {
                Task { await viewModel.run() }
            } label: {
                Label(viewModel.isRunning ? "Running" : "Run", systemImage: "play.fill")
            }
            .controlSize(.small)
            .disabled(viewModel.isRunning)

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .controlSize(.small)
                .help("Close")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

private struct WorkflowStepPanel: View {
    let step: WorkflowStepPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(step.title ?? step.id)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(step.status)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor)
            }

            Text(step.command.isEmpty ? " " : step.command)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: CocxyColors.surface0))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            if !step.stdout.isEmpty {
                outputText(step.stdout, background: Color(nsColor: CocxyColors.surface1))
            }

            if !step.stderr.isEmpty {
                outputText(
                    step.stderr,
                    background: Color(nsColor: CocxyColors.red.withAlphaComponent(0.16))
                )
            }
        }
    }

    private var statusColor: Color {
        switch step.status {
        case "Completed":
            return Color(nsColor: CocxyColors.green)
        case "Failed":
            return Color(nsColor: CocxyColors.red)
        default:
            return Color(nsColor: CocxyColors.subtext0)
        }
    }

    private func outputText(_ text: String, background: Color) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
