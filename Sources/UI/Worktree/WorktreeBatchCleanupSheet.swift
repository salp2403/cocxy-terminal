// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeBatchCleanupSheet.swift - Confirmation UI for merged worktree cleanup.

import Foundation
import SwiftUI

struct WorktreeBatchCleanupSheetViewModel: Equatable {
    let plan: WorktreeBatchCleanupPlan
    let baseRef: String

    var canCleanUp: Bool { !plan.removable.isEmpty }

    var primarySummary: String {
        let count = plan.removable.count
        if count == 1 { return "1 merged worktree ready to clean up" }
        return "\(count) merged worktrees ready to clean up"
    }

    func localizedPrimarySummary(using localizer: AppLocalizer) -> String {
        let count = plan.removable.count
        let key = count == 1
            ? "worktree.batchCleanup.summary.one"
            : "worktree.batchCleanup.summary.many"
        let fallback = count == 1
            ? "%d merged worktree ready to clean up"
            : "%d merged worktrees ready to clean up"
        return String(format: localizer.string(key, fallback: fallback), count)
    }

    var blockedDetails: [String] {
        plan.blocked.map { block in
            "\(block.entry.id): \(describe(block.reason))"
        }
    }

    func localizedBlockedDetails(using localizer: AppLocalizer) -> [String] {
        plan.blocked.map { block in
            "\(block.entry.id): \(describe(block.reason, using: localizer))"
        }
    }

    var skippedDetails: [String] {
        plan.skipped.map { skip in
            "\(skip.entry.id): \(describe(skip.reason))"
        }
    }

    func localizedSkippedDetails(using localizer: AppLocalizer) -> [String] {
        plan.skipped.map { skip in
            "\(skip.entry.id): \(describe(skip.reason, using: localizer))"
        }
    }

    private func describe(_ reason: WorktreeBatchCleanupBlockReason) -> String {
        switch reason {
        case .uncommittedChanges:
            return "uncommitted changes"
        case .dependentWorktrees(let ids):
            return "dependent worktrees: \(ids.joined(separator: ", "))"
        }
    }

    private func describe(_ reason: WorktreeBatchCleanupSkipReason) -> String {
        switch reason {
        case .notMerged:
            return "not merged into \(baseRef)"
        }
    }

    private func describe(_ reason: WorktreeBatchCleanupBlockReason, using localizer: AppLocalizer) -> String {
        switch reason {
        case .uncommittedChanges:
            return localizer.string(
                "worktree.batchCleanup.reason.uncommittedChanges",
                fallback: "uncommitted changes"
            )
        case .dependentWorktrees(let ids):
            return String(
                format: localizer.string(
                    "worktree.batchCleanup.reason.dependentWorktrees",
                    fallback: "dependent worktrees: %@"
                ),
                ids.joined(separator: ", ")
            )
        }
    }

    private func describe(_ reason: WorktreeBatchCleanupSkipReason, using localizer: AppLocalizer) -> String {
        switch reason {
        case .notMerged:
            return String(
                format: localizer.string(
                    "worktree.batchCleanup.reason.notMerged",
                    fallback: "not merged into %@"
                ),
                baseRef
            )
        }
    }
}

struct WorktreeBatchCleanupSheet: View {
    let viewModel: WorktreeBatchCleanupSheetViewModel
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    let onCancel: () -> Void
    let onCleanUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Self.localizedTitle(using: localizer))
                .font(.title2.weight(.semibold))
            Text(viewModel.localizedPrimarySummary(using: localizer))
                .foregroundStyle(.secondary)

            if !viewModel.plan.removable.isEmpty {
                Section(Self.localizedReadySectionTitle(using: localizer)) {
                    ForEach(viewModel.plan.removable, id: \.id) { entry in
                        Text("\(entry.id) · \(entry.branch)")
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            let blockedDetails = viewModel.localizedBlockedDetails(using: localizer)
            if !blockedDetails.isEmpty {
                Section(Self.localizedBlockedSectionTitle(using: localizer)) {
                    ForEach(blockedDetails, id: \.self) { detail in
                        Text(detail)
                    }
                }
            }

            let skippedDetails = viewModel.localizedSkippedDetails(using: localizer)
            if !skippedDetails.isEmpty {
                Section(Self.localizedSkippedSectionTitle(using: localizer)) {
                    ForEach(skippedDetails, id: \.self) { detail in
                        Text(detail)
                    }
                }
            }

            HStack {
                Spacer()
                Button(localizer.string("common.cancel", fallback: "Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(Self.localizedCleanUpButtonTitle(using: localizer), action: onCleanUp)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canCleanUp)
            }
        }
        .padding(20)
        .frame(width: 560)
        .glassPanelBackground()
    }

    static func localizedTitle(using localizer: AppLocalizer) -> String {
        localizer.string("worktree.batchCleanup.title", fallback: "Clean Up Merged Worktrees")
    }

    static func localizedReadySectionTitle(using localizer: AppLocalizer) -> String {
        localizer.string("worktree.batchCleanup.ready", fallback: "Ready")
    }

    static func localizedBlockedSectionTitle(using localizer: AppLocalizer) -> String {
        localizer.string("worktree.batchCleanup.blocked", fallback: "Blocked")
    }

    static func localizedSkippedSectionTitle(using localizer: AppLocalizer) -> String {
        localizer.string("worktree.batchCleanup.skipped", fallback: "Skipped")
    }

    static func localizedCleanUpButtonTitle(using localizer: AppLocalizer) -> String {
        localizer.string("worktree.batchCleanup.cleanUp", fallback: "Clean Up")
    }
}
