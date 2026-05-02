// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentPanelView.swift - SwiftUI surface for built-in Agent Mode.

import SwiftUI

struct AgentPanelView: View {
    @ObservedObject var viewModel: AgentPanelViewModel
    var onDismiss: (() -> Void)? = nil

    static let panelWidth: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            composer
        }
        .frame(width: Self.panelWidth)
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                Color(nsColor: CocxyColors.mantle)
                VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent Mode")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)

            Text("Agent Mode")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button(action: { onDismiss?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .help("Close Agent Mode")
            .accessibilityLabel("Close Agent Mode")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var transcript: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 10) {
                if viewModel.messages.isEmpty {
                    emptyTranscript
                } else {
                    ForEach(viewModel.messages) { message in
                        AgentMessageRow(message: message)
                    }
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTranscript: some View {
        VStack(alignment: .center, spacing: 8) {
            Spacer(minLength: 80)
            Image(systemName: "text.bubble")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(viewModel.statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.statusText)
                .font(.caption)
                .foregroundStyle(statusColor)
                .lineLimit(2)
                .textSelection(.enabled)

            if let approval = viewModel.pendingApproval {
                approvalCard(approval)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask Agent Mode", text: $viewModel.promptDraft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!inputEnabled)
                    .onSubmit {
                        submit()
                    }

                Button(action: submit) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .disabled(!viewModel.canSubmit)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send prompt")
                .accessibilityLabel("Send prompt")
            }
        }
        .padding(12)
    }

    private func approvalCard(_ request: AgentToolApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: approvalIcon(for: request.preview.kind))
                    .foregroundStyle(statusColor)
                Text(request.preview.title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }

            ScrollView(.vertical, showsIndicators: true) {
                Text(request.preview.body)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)

            if request.preview.kind == .userInput {
                TextField("Response", text: $viewModel.pendingApprovalResponseDraft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            HStack(spacing: 8) {
                Button(action: approvePendingTool) {
                    Label(
                        request.preview.kind == .userInput ? "Send" : "Approve",
                        systemImage: request.preview.kind == .userInput ? "paperplane" : "checkmark"
                    )
                }
                .disabled(!viewModel.canApprovePendingTool)

                Button(role: .cancel, action: viewModel.rejectPendingTool) {
                    Label("Reject", systemImage: "xmark")
                }

                Spacer()
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: CocxyColors.surface0).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: CocxyColors.overlay0).opacity(0.45), lineWidth: 1)
        )
    }

    private var inputEnabled: Bool {
        switch viewModel.state {
        case .disabled, .running, .awaitingApproval:
            return false
        case .idle, .failed:
            return true
        }
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .failed:
            return Color(nsColor: CocxyColors.red)
        case .awaitingApproval:
            return Color(nsColor: CocxyColors.yellow)
        case .running:
            return Color(nsColor: CocxyColors.blue)
        default:
            return .secondary
        }
    }

    private func submit() {
        Task {
            await viewModel.submitPrompt()
        }
    }

    private func approvePendingTool() {
        Task {
            await viewModel.approvePendingTool()
        }
    }

    private func approvalIcon(for kind: AgentToolApprovalPreviewKind) -> String {
        switch kind {
        case .diff:
            return "doc.text.magnifyingglass"
        case .command:
            return "terminal"
        case .userInput:
            return "questionmark.bubble"
        }
    }
}

private struct AgentMessageRow: View {
    let message: AgentMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(message.content)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
        )
    }

    private var title: String {
        switch message.role {
        case .system:
            return "System"
        case .user:
            return "You"
        case .assistant:
            return "Agent"
        case .tool:
            return message.toolName.map { "Tool: \($0)" } ?? "Tool"
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor.opacity(0.14)
        case .assistant:
            return Color(nsColor: CocxyColors.surface0).opacity(0.7)
        case .tool:
            return Color(nsColor: CocxyColors.overlay0).opacity(0.16)
        case .system:
            return Color(nsColor: CocxyColors.surface1).opacity(0.55)
        }
    }
}
