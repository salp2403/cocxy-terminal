// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskRunLifecycleControls.swift - Confirmed task run lifecycle actions.

import SwiftUI

struct TaskRunLifecycleControls: View {
    let canCancel: Bool
    let canForget: Bool
    let isBusy: Bool
    let localizer: AppLocalizer
    let cancel: () -> Void
    let forget: () -> Void

    @State private var pendingAction: Action?

    private enum Action: String, Identifiable {
        case cancel
        case forget

        var id: String { rawValue }
    }

    var body: some View {
        HStack(spacing: 4) {
            if canCancel {
                Button { pendingAction = .cancel } label: {
                    Image(systemName: "stop.circle").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .help(cancelActionTitle)
                .accessibilityLabel(cancelActionTitle)
            }
            if canForget {
                Button { pendingAction = .forget } label: {
                    Image(systemName: "trash").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .help(forgetActionTitle)
                .accessibilityLabel(forgetActionTitle)
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if pendingAction == .cancel {
                Button(cancelActionTitle, role: .destructive) {
                    pendingAction = nil
                    cancel()
                }
            } else if pendingAction == .forget {
                Button(forgetActionTitle, role: .destructive) {
                    pendingAction = nil
                    forget()
                }
            }
            Button(localizer.string("common.cancel", fallback: "Cancel"), role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationTitle: String {
        switch pendingAction {
        case .cancel:
            return localizer.string(
                "taskRun.lifecycle.cancel.title",
                fallback: "Cancel Parallel Task?"
            )
        case .forget:
            return localizer.string(
                "taskRun.lifecycle.forget.title",
                fallback: "Remove Task History?"
            )
        case nil:
            return ""
        }
    }

    private var cancelActionTitle: String {
        localizer.string("taskRun.lifecycle.cancel.action", fallback: "Cancel Task")
    }

    private var forgetActionTitle: String {
        localizer.string("taskRun.lifecycle.forget.action", fallback: "Remove History")
    }

    private var confirmationMessage: String {
        switch pendingAction {
        case .cancel:
            return localizer.string(
                "taskRun.lifecycle.cancel.message",
                fallback: "Running agents will stop. Their worktrees and files will be kept."
            )
        case .forget:
            return localizer.string(
                "taskRun.lifecycle.forget.message",
                fallback: "This removes the saved task record. Worktrees and files will be kept."
            )
        case nil:
            return ""
        }
    }
}
