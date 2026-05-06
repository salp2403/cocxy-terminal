// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeAdvancedModal.swift - Guided worktree creation UI.

import Foundation
import SwiftUI

final class WorktreeAdvancedModalViewModel: ObservableObject {
    let templates: [WorktreeTemplate]
    let availableBaseRefs: [String]

    @Published var selectedTemplateID: String
    @Published var summary: String
    @Published var issue: String
    @Published var baseRef: String
    @Published var agent: String

    private let previewID: String
    private let now: Date
    private let timeZone: TimeZone

    init(
        templates: [WorktreeTemplate] = WorktreeTemplate.builtIns,
        initialBaseRef: String,
        availableBaseRefs: [String],
        detectedAgent: String?,
        previewID: String = WorktreeID.generate(length: WorktreeConfig.defaults.idLength),
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) {
        self.templates = templates.isEmpty ? WorktreeTemplate.builtIns : templates
        self.availableBaseRefs = Self.uniqueBaseRefs(
            [initialBaseRef] + availableBaseRefs + ["HEAD"]
        )
        self.selectedTemplateID = self.templates.first?.id ?? WorktreeTemplate.feature.id
        self.summary = ""
        self.issue = ""
        self.baseRef = initialBaseRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "HEAD"
            : initialBaseRef
        self.agent = detectedAgent ?? ""
        self.previewID = previewID
        self.now = now
        self.timeZone = timeZone
    }

    var selectedTemplate: WorktreeTemplate {
        templates.first { $0.id == selectedTemplateID } ?? templates[0]
    }

    var previewBranch: String {
        WorktreeBranchNameGenerator.preview(
            template: selectedTemplate,
            summary: summary,
            issue: issue.nilIfBlank,
            agent: agent.nilIfBlank,
            id: previewID,
            date: now,
            timeZone: timeZone
        )
    }

    var canCreate: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !baseRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func creationRequest() -> WorktreeAdvancedCreationRequest? {
        guard canCreate else { return nil }
        return WorktreeAdvancedCreationRequest(
            templateID: selectedTemplate.id,
            branch: previewBranch,
            baseRef: baseRef.trimmingCharacters(in: .whitespacesAndNewlines),
            agent: agent.nilIfBlank
        )
    }

    private static func uniqueBaseRefs(_ refs: [String]) -> [String] {
        var seen = Set<String>()
        return refs.compactMap { raw in
            let ref = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ref.isEmpty, seen.insert(ref).inserted else { return nil }
            return ref
        }
    }
}

struct WorktreeAdvancedModal: View {
    @ObservedObject var viewModel: WorktreeAdvancedModalViewModel
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    let onCancel: () -> Void
    let onCreate: (WorktreeAdvancedCreationRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Self.localizedTitle(using: localizer))
                .font(.title2.weight(.semibold))

            Form {
                WorktreeTemplatePicker(viewModel: viewModel, localizer: localizer)

                TextField(Self.localizedShortDescriptionPlaceholder(using: localizer), text: $viewModel.summary)
                    .textFieldStyle(.roundedBorder)

                if viewModel.selectedTemplate.branchKind == .hotfix {
                    TextField(Self.localizedIssueKeyPlaceholder(using: localizer), text: $viewModel.issue)
                        .textFieldStyle(.roundedBorder)
                }

                Picker(Self.localizedBaseBranchTitle(using: localizer), selection: $viewModel.baseRef) {
                    ForEach(viewModel.availableBaseRefs, id: \.self) { ref in
                        Text(ref).tag(ref)
                    }
                }

                TextField(Self.localizedAgentPlaceholder(using: localizer), text: $viewModel.agent)
                    .textFieldStyle(.roundedBorder)

                WorktreeBranchNamePreview(branch: viewModel.previewBranch, localizer: localizer)
            }

            HStack {
                Spacer()
                Button(localizer.string("common.cancel", fallback: "Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(Self.localizedCreateButtonTitle(using: localizer)) {
                    guard let request = viewModel.creationRequest() else { return }
                    onCreate(request)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canCreate)
            }
        }
        .padding(20)
        .frame(width: 560)
        .glassPanelBackground()
    }

    static func localizedTitle(using localizer: AppLocalizer) -> String {
        localizer.string("worktree.advanced.title", fallback: "New Worktree")
    }

    static func localizedShortDescriptionPlaceholder(using localizer: AppLocalizer) -> String {
        localizer.string("worktree.advanced.shortDescription", fallback: "Short description")
    }

    static func localizedIssueKeyPlaceholder(using localizer: AppLocalizer) -> String {
        localizer.string("worktree.advanced.issueKey", fallback: "Issue key")
    }

    static func localizedBaseBranchTitle(using localizer: AppLocalizer) -> String {
        localizer.string("worktree.advanced.baseBranch", fallback: "Base branch")
    }

    static func localizedAgentPlaceholder(using localizer: AppLocalizer) -> String {
        localizer.string("worktree.advanced.agent", fallback: "Agent")
    }

    static func localizedCreateButtonTitle(using localizer: AppLocalizer) -> String {
        localizer.string("worktree.advanced.create", fallback: "Create")
    }
}

struct WorktreeTemplatePicker: View {
    @ObservedObject var viewModel: WorktreeAdvancedModalViewModel
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        Picker(localizer.string("worktree.advanced.template", fallback: "Template"), selection: $viewModel.selectedTemplateID) {
            ForEach(viewModel.templates) { template in
                Text(template.localizedDisplayName(using: localizer)).tag(template.id)
            }
        }
        Text(viewModel.selectedTemplate.localizedDescription(using: localizer))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct WorktreeBranchNamePreview: View {
    let branch: String
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.localizedTitle(using: localizer))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(branch)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    static func localizedTitle(using localizer: AppLocalizer) -> String {
        localizer.string("worktree.advanced.branchPreview", fallback: "Branch Preview")
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
