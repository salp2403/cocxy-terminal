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

    var blockedDetails: [String] {
        plan.blocked.map { block in
            "\(block.entry.id): \(describe(block.reason))"
        }
    }

    var skippedDetails: [String] {
        plan.skipped.map { skip in
            "\(skip.entry.id): \(describe(skip.reason))"
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
}

struct WorktreeBatchCleanupSheet: View {
    let viewModel: WorktreeBatchCleanupSheetViewModel
    let onCancel: () -> Void
    let onCleanUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clean Up Merged Worktrees")
                .font(.title2.weight(.semibold))
            Text(viewModel.primarySummary)
                .foregroundStyle(.secondary)

            if !viewModel.plan.removable.isEmpty {
                Section("Ready") {
                    ForEach(viewModel.plan.removable, id: \.id) { entry in
                        Text("\(entry.id) · \(entry.branch)")
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            if !viewModel.blockedDetails.isEmpty {
                Section("Blocked") {
                    ForEach(viewModel.blockedDetails, id: \.self) { detail in
                        Text(detail)
                    }
                }
            }

            if !viewModel.skippedDetails.isEmpty {
                Section("Skipped") {
                    ForEach(viewModel.skippedDetails, id: \.self) { detail in
                        Text(detail)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Clean Up", action: onCleanUp)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canCleanUp)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
