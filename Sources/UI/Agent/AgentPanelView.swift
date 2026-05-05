// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentPanelView.swift - SwiftUI surface for built-in Agent Mode.

import SwiftUI

struct AgentPanelView: View {
    @ObservedObject var viewModel: AgentPanelViewModel
    var onDismiss: (() -> Void)? = nil
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

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
        .glassPanelBackground()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("agent.panel.accessibility", fallback: "Agent Mode"))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)

            Text(localized("agent.panel.title", fallback: "Agent Mode"))
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button(action: { onDismiss?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .help(localized("agent.panel.close", fallback: "Close Agent Mode"))
            .accessibilityLabel(localized("agent.panel.close", fallback: "Close Agent Mode"))
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
                        AgentMessageRow(message: message, localizer: localizer)
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
            Text(localizedStatusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizedStatusText)
                .font(.caption)
                .foregroundStyle(statusColor)
                .lineLimit(2)
                .textSelection(.enabled)

            if let status = viewModel.computerUseStatus {
                computerUseStatusRow(status)
            }

            if !viewModel.availableSkills.isEmpty {
                skillPicker
            }

            if let approval = viewModel.pendingApproval {
                approvalCard(approval)
            }

            AgentAttachmentBar(
                attachments: viewModel.imageAttachments,
                onRemove: viewModel.removeImageAttachment(id:),
                localizer: localizer
            )

            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    AgentPromptComposerTextView(
                        text: $viewModel.promptDraft,
                        isEnabled: inputEnabled,
                        onSubmit: submit,
                        onImageData: attachImageData(_:suggestedFilename:),
                        onFileURLs: attachFiles(_:)
                    )
                    .frame(minHeight: 34, maxHeight: 88)

                    if viewModel.promptDraft.isEmpty {
                        Text(localized("agent.panel.prompt.placeholder", fallback: "Ask Agent Mode"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: CocxyColors.surface0).opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: CocxyColors.overlay0).opacity(0.45), lineWidth: 1)
                )
                .opacity(inputEnabled ? 1 : 0.55)

                Button(action: submit) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .disabled(!viewModel.canSubmit)
                .keyboardShortcut(.return, modifiers: [.command])
                .help(localized("agent.panel.sendPrompt", fallback: "Send prompt"))
                .accessibilityLabel(localized("agent.panel.sendPrompt", fallback: "Send prompt"))
            }
        }
        .padding(12)
        .dropDestination(for: URL.self) { urls, _ in
            attachFiles(urls)
            return true
        }
    }

    private var skillPicker: some View {
        Menu {
            ForEach(viewModel.availableSkills) { skill in
                Button(action: {
                    viewModel.setSkill(skill.id, selected: !viewModel.isSkillSelected(skill.id))
                }) {
                    Label(
                        skillMenuTitle(skill),
                        systemImage: viewModel.isSkillSelected(skill.id)
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                }
            }
        } label: {
            Label(skillPickerTitle, systemImage: "wand.and.stars")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .disabled(viewModel.state == .running)
        .help(localized(
            "agent.panel.skills.help",
            fallback: "Select local skills for the next Agent prompt"
        ))
        .accessibilityLabel(skillPickerTitle)
    }

    private func computerUseStatusRow(_ status: AgentComputerUseStatus) -> some View {
        HStack(spacing: 8) {
            Image(systemName: status.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    status.phase == .running
                        ? Color(nsColor: CocxyColors.blue)
                        : Color(nsColor: CocxyColors.yellow)
                )
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.localizedTitle(using: localizer))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(status.localizedDetail(using: localizer))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: CocxyColors.surface0).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: CocxyColors.overlay0).opacity(0.45), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.localizedAccessibilityLabel(using: localizer))
    }

    private func approvalCard(_ request: AgentToolApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: approvalIcon(for: request.preview.kind))
                    .foregroundStyle(statusColor)
                Text(AgentPanelLocalization.approvalTitle(request.preview.title, using: localizer))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }

            ScrollView(.vertical, showsIndicators: true) {
                Text(AgentPanelLocalization.approvalBody(request.preview.body, using: localizer))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)

            if request.preview.kind == .userInput {
                TextField(
                    localized("agent.panel.approval.response.placeholder", fallback: "Response"),
                    text: $viewModel.pendingApprovalResponseDraft,
                    axis: .vertical
                )
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            HStack(spacing: 8) {
                Button(action: approvePendingTool) {
                    Label(
                        request.preview.kind == .userInput
                            ? localized("agent.panel.approval.send", fallback: "Send")
                            : localized("agent.panel.approval.approve", fallback: "Approve"),
                        systemImage: request.preview.kind == .userInput ? "paperplane" : "checkmark"
                    )
                }
                .disabled(!viewModel.canApprovePendingTool)

                Button(role: .cancel, action: viewModel.rejectPendingTool) {
                    Label(
                        localized("agent.panel.approval.reject", fallback: "Reject"),
                        systemImage: "xmark"
                    )
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

    private var skillPickerTitle: String {
        Self.localizedSkillPickerTitle(
            selectedCount: viewModel.selectedSkillsCount,
            using: localizer
        )
    }

    static func localizedSkillPickerTitle(selectedCount: Int, using localizer: AppLocalizer) -> String {
        if selectedCount == 0 {
            return localizer.string("agent.panel.skills", fallback: "Skills")
        }
        if selectedCount == 1 {
            return String(
                format: localizer.string("agent.panel.skills.one", fallback: "%d Skill"),
                selectedCount
            )
        }
        return String(
            format: localizer.string("agent.panel.skills.many", fallback: "%d Skills"),
            selectedCount
        )
    }

    private func skillMenuTitle(_ skill: AgentPanelSkillOption) -> String {
        "\(skill.name) (\(skill.source.rawValue))"
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

    private var localizedStatusText: String {
        AgentPanelLocalization.statusText(viewModel.statusText, using: localizer)
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
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

    private func attachImageData(_ data: Data, suggestedFilename: String?) {
        do {
            try viewModel.attachImageData(data, suggestedFilename: suggestedFilename)
        } catch {
            viewModel.handleAttachmentError(error)
        }
    }

    private func attachFiles(_ urls: [URL]) {
        for url in urls {
            do {
                try viewModel.attachImageFile(url)
            } catch {
                viewModel.handleAttachmentError(error)
            }
        }
    }

    private func approvalIcon(for kind: AgentToolApprovalPreviewKind) -> String {
        switch kind {
        case .diff:
            return "doc.text.magnifyingglass"
        case .command:
            return "terminal"
        case .computerUse:
            return "cursorarrow.click"
        case .externalTool:
            return "point.3.connected.trianglepath.dotted"
        case .userInput:
            return "questionmark.bubble"
        }
    }
}

enum AgentPanelLocalization {
    static func approvalTitle(_ text: String, using localizer: AppLocalizer) -> String {
        switch text {
        case "Approve command":
            return localizer.string("agent.panel.approval.title.command", fallback: text)
        case "Approve computer action":
            return localizer.string("agent.panel.approval.title.computerAction", fallback: text)
        case "Approve external tool":
            return localizer.string("agent.panel.approval.title.externalTool", fallback: text)
        case "Approve external MCP tool":
            return localizer.string("agent.panel.approval.title.externalMCPTool", fallback: text)
        case "Agent requested input":
            return localizer.string("agent.panel.approval.title.userInput", fallback: text)
        default:
            return dynamicApprovalTitle(text, using: localizer)
        }
    }

    static func approvalBody(_ text: String, using localizer: AppLocalizer) -> String {
        if text == "The agent requested user input." {
            return localizer.string("agent.panel.approval.body.userInput", fallback: text)
        }

        if text.hasPrefix("Allow "), text.hasSuffix(" to control this Mac locally.") {
            let toolID = String(text.dropFirst("Allow ".count).dropLast(" to control this Mac locally.".count))
            return String(
                format: localizer.string(
                    "agent.panel.approval.body.allowComputerAction",
                    fallback: "Allow %@ to control this Mac locally."
                ),
                toolID
            )
        }

        if text.hasPrefix("Allow "), text.hasSuffix(" to call a configured local MCP server.") {
            let toolID = String(text.dropFirst("Allow ".count).dropLast(" to call a configured local MCP server.".count))
            return String(
                format: localizer.string(
                    "agent.panel.approval.body.allowMCPTool",
                    fallback: "Allow %@ to call a configured local MCP server."
                ),
                toolID
            )
        }

        if text.hasPrefix("Diff preview is unavailable for call "), text.hasSuffix(".") {
            let callID = String(text.dropFirst("Diff preview is unavailable for call ".count).dropLast())
            return String(
                format: localizer.string(
                    "agent.panel.approval.body.diffUnavailable",
                    fallback: "Diff preview is unavailable for call %@."
                ),
                callID
            )
        }

        return text
    }

    static func statusText(_ text: String, using localizer: AppLocalizer) -> String {
        switch text {
        case "Ready.":
            return localizer.string("agent.panel.status.ready", fallback: "Ready.")
        case "Agent Mode is disabled.":
            return localizer.string(
                "agent.panel.status.disabled",
                fallback: "Agent Mode is disabled."
            )
        case "Running...":
            return localizer.string("agent.panel.status.running", fallback: "Running...")
        case "Running approved tool...":
            return localizer.string(
                "agent.panel.status.runningApprovedTool",
                fallback: "Running approved tool..."
            )
        case "Completed.":
            return localizer.string("agent.panel.status.completed", fallback: "Completed.")
        case "Request rejected.":
            return localizer.string("agent.panel.status.rejected", fallback: "Request rejected.")
        case "Stopped at max iterations.":
            return localizer.string(
                "agent.panel.status.maxIterations",
                fallback: "Stopped at max iterations."
            )
        case "Provider unavailable.":
            return localizer.string(
                "agent.panel.status.providerUnavailable",
                fallback: "Provider unavailable."
            )
        case "Current Agent runner does not support image attachments.":
            return localizer.string(
                "agent.panel.status.attachmentRunnerUnavailable",
                fallback: "Current Agent runner does not support image attachments."
            )
        case "Approval is unavailable for this Agent runner.":
            return localizer.string(
                "agent.panel.status.approvalUnavailable",
                fallback: "Approval is unavailable for this Agent runner."
            )
        default:
            return dynamicStatusText(text, using: localizer)
        }
    }

    private static func dynamicApprovalTitle(_ text: String, using localizer: AppLocalizer) -> String {
        if text.hasPrefix("Review changes to ") {
            let path = String(text.dropFirst("Review changes to ".count))
            return String(
                format: localizer.string(
                    "agent.panel.approval.title.reviewChangesTo",
                    fallback: "Review changes to %@"
                ),
                path
            )
        }

        if text.hasPrefix("Review changes for ") {
            let toolID = String(text.dropFirst("Review changes for ".count))
            return String(
                format: localizer.string(
                    "agent.panel.approval.title.reviewChangesFor",
                    fallback: "Review changes for %@"
                ),
                toolID
            )
        }

        return text
    }

    private static func dynamicStatusText(_ text: String, using localizer: AppLocalizer) -> String {
        if text.hasPrefix("Failed to load skills: ") {
            let reason = String(text.dropFirst("Failed to load skills: ".count))
            return String(
                format: localizer.string(
                    "agent.panel.status.loadSkillsFailed",
                    fallback: "Failed to load skills: %@"
                ),
                reason
            )
        }

        if let imageCount = imageAttachmentCount(from: text) {
            let key = imageCount == 1
                ? "agent.panel.status.images.one"
                : "agent.panel.status.images.many"
            let fallback = imageCount == 1
                ? "%d image attached."
                : "%d images attached."
            return String(format: localizer.string(key, fallback: fallback), imageCount)
        }

        if text.hasPrefix("Approve command: ") {
            let command = String(text.dropFirst("Approve command: ".count))
            return String(
                format: localizer.string(
                    "agent.panel.status.approveCommand",
                    fallback: "Approve command: %@"
                ),
                command
            )
        }

        if text.hasPrefix("Review diff for "), text.hasSuffix(".") {
            let toolID = String(text.dropFirst("Review diff for ".count).dropLast())
            return String(
                format: localizer.string(
                    "agent.panel.status.reviewDiff",
                    fallback: "Review diff for %@."
                ),
                toolID
            )
        }

        if text.hasPrefix("Approve computer action "), text.hasSuffix(".") {
            let toolID = String(text.dropFirst("Approve computer action ".count).dropLast())
            return String(
                format: localizer.string(
                    "agent.panel.status.approveComputerAction",
                    fallback: "Approve computer action %@."
                ),
                toolID
            )
        }

        if text.hasPrefix("Approve external tool "), text.hasSuffix(".") {
            let toolID = String(text.dropFirst("Approve external tool ".count).dropLast())
            return String(
                format: localizer.string(
                    "agent.panel.status.approveExternalTool",
                    fallback: "Approve external tool %@."
                ),
                toolID
            )
        }

        if text.hasPrefix("Agent requested input for "), text.hasSuffix(".") {
            let toolID = String(text.dropFirst("Agent requested input for ".count).dropLast())
            return String(
                format: localizer.string(
                    "agent.panel.status.requestedInput",
                    fallback: "Agent requested input for %@."
                ),
                toolID
            )
        }

        if text.hasPrefix("Blocked "), text.hasSuffix(" without a command.") {
            let toolID = String(
                text.dropFirst("Blocked ".count).dropLast(" without a command.".count)
            )
            return String(
                format: localizer.string(
                    "agent.panel.status.blockedMissingCommand",
                    fallback: "Blocked %@ without a command."
                ),
                toolID
            )
        }

        if text.hasPrefix("Blocked dangerous command: ") {
            let command = String(text.dropFirst("Blocked dangerous command: ".count))
            return String(
                format: localizer.string(
                    "agent.panel.status.blockedDangerousCommand",
                    fallback: "Blocked dangerous command: %@"
                ),
                command
            )
        }

        if text.hasPrefix("Blocked "),
           text.hasSuffix(" because a preview could not be generated.") {
            let toolID = String(
                text
                    .dropFirst("Blocked ".count)
                    .dropLast(" because a preview could not be generated.".count)
            )
            return String(
                format: localizer.string(
                    "agent.panel.status.blockedPreviewUnavailable",
                    fallback: "Blocked %@ because a preview could not be generated."
                ),
                toolID
            )
        }

        if text.hasPrefix("Tool protocol error: ") {
            let error = String(text.dropFirst("Tool protocol error: ".count))
            return String(
                format: localizer.string(
                    "agent.panel.status.toolProtocolError",
                    fallback: "Tool protocol error: %@"
                ),
                error
            )
        }

        if text.hasSuffix(" does not support image attachments in Agent Mode.") {
            let provider = String(
                text.dropLast(" does not support image attachments in Agent Mode.".count)
            )
            return String(
                format: localizer.string(
                    "agent.panel.status.imageAttachmentsUnsupported",
                    fallback: "%@ does not support image attachments in Agent Mode."
                ),
                provider
            )
        }

        return text
    }

    private static func imageAttachmentCount(from text: String) -> Int? {
        guard text.hasSuffix(" attached."),
              text.contains(" image") else {
            return nil
        }
        let firstToken = text.split(separator: " ").first
        return firstToken.flatMap { Int($0) }
    }
}

private struct AgentMessageRow: View {
    let message: AgentMessage
    let localizer: AppLocalizer

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
            return localizer.string("agent.panel.message.system", fallback: "System")
        case .user:
            return localizer.string("agent.panel.message.you", fallback: "You")
        case .assistant:
            return localizer.string("agent.panel.message.agent", fallback: "Agent")
        case .tool:
            if let toolName = message.toolName {
                return String(
                    format: localizer.string("agent.panel.message.toolNamed", fallback: "Tool: %@"),
                    toolName
                )
            }
            return localizer.string("agent.panel.message.tool", fallback: "Tool")
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
