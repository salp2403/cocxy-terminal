// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+TaskRun.swift - Parallel task sheet and palette wiring.

import AppKit
import SwiftUI

@MainActor
extension MainWindowController {
    func showTaskRunLaunchSheet() {
        guard let window else { return }
        let localizer = appLocalizer()
        guard let delegate = NSApp.delegate as? AppDelegate,
              let context = delegate.focusedTaskRunLaunchContext(),
              context.windowID == windowID else {
            presentTaskRunAlert(
                message: localizedTaskRunString(
                    "taskRun.error.noTarget",
                    fallback: "No active repository-backed terminal is available."
                )
            )
            return
        }
        guard context.worktreeConfig.enabled else {
            presentTaskRunAlert(
                message: localizedTaskRunString(
                    "taskRun.error.disabled",
                    fallback: AppDelegate.worktreeEnablementErrorMessage
                )
            )
            return
        }

        let viewModel = TaskRunLaunchSheetViewModel(
            availableBaseRefs: availableWorktreeBaseRefs(),
            initialBaseRef: context.worktreeConfig.baseRef
        )
        var sheet: NSWindow!
        let view = TaskRunLaunchSheet(
            viewModel: viewModel,
            localizer: localizer,
            onCancel: { [weak window] in
                guard let sheet, sheet.sheetParent === window else { return }
                window?.endSheet(sheet)
            },
            onLaunch: { [weak self, weak window] request in
                guard !viewModel.isLaunching else { return }
                viewModel.beginLaunch()
                Task { @MainActor [weak self, weak window] in
                    do {
                        let run = try await delegate.performTaskRunLaunch(
                            request: request,
                            context: context
                        )
                        if let sheet, sheet.sheetParent === window {
                            window?.endSheet(sheet)
                        }
                        DispatchQueue.main.async { [weak self] in
                            self?.showTaskRunComparisonSheet(runID: run.id)
                        }
                    } catch {
                        viewModel.finishLaunch(error: String(describing: error))
                    }
                }
            }
        )
        sheet = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet.title = localizer.string("taskRun.launch.title", fallback: "Fan Out Task")
        sheet.styleMask = [.titled]
        sheet.isReleasedWhenClosed = false
        window.beginSheet(sheet)
    }

    func showTaskRunComparisonPicker() {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        let runs = delegate.taskRunsSnapshot().filter { $0.status == .running }
        guard !runs.isEmpty else {
            presentTaskRunAlert(
                message: localizedTaskRunString(
                    "taskRun.error.noRunningTasks",
                    fallback: "No running parallel tasks are available to compare."
                )
            )
            return
        }
        if runs.count == 1, let run = runs.first {
            showTaskRunComparisonSheet(runID: run.id)
            return
        }

        let actions = runs.map { run in
            let repository = run.originRepoPath.lastPathComponent.isEmpty
                ? run.originRepoPath.path
                : run.originRepoPath.lastPathComponent
            let description = String(
                format: appLocalizer().string(
                    "taskRun.compare.pickerDescription",
                    fallback: "%d candidates | %@ | %@"
                ),
                run.candidates.count,
                run.baseRef,
                run.id
            )
            return CommandAction(
                id: "taskRun.compare.\(run.id)",
                name: repository,
                description: description,
                shortcut: nil,
                category: .agent,
                handler: { [weak self, runID = run.id] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in
                        self?.showTaskRunComparisonSheet(runID: runID)
                    }
                }
            )
        }
        showTransientCommandPaletteOverlay(
            engine: StaticCommandPaletteEngine(actions: actions)
        )
    }

    func showTaskRunComparisonSheet(runID: String) {
        guard let window,
              let delegate = NSApp.delegate as? AppDelegate,
              let run = delegate.taskRunsSnapshot().first(where: { $0.id == runID }) else {
            presentTaskRunAlert(
                message: localizedTaskRunString(
                    "taskRun.error.notFound",
                    fallback: "The selected parallel task is no longer available."
                )
            )
            return
        }

        let localizer = appLocalizer()
        let viewModel = TaskRunComparisonSheetViewModel(run: run)
        var sheet: NSWindow!
        let view = TaskRunComparisonSheet(
            viewModel: viewModel,
            localizer: localizer,
            onRefresh: { [weak self] in
                self?.reloadTaskRunComparison(runID: runID, viewModel: viewModel)
            },
            onPromote: { [weak self, weak window] candidateID in
                guard let self, let sheet else { return }
                self.promoteTaskRunFromSheet(
                    runID: runID,
                    candidateID: candidateID,
                    viewModel: viewModel,
                    sheet: sheet,
                    parentWindow: window
                )
            },
            onDismiss: { [weak window] in
                guard let sheet, sheet.sheetParent === window else { return }
                window?.endSheet(sheet)
            }
        )
        sheet = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet.title = localizer.string(
            "taskRun.compare.title",
            fallback: "Compare Task Candidates"
        )
        sheet.styleMask = [.titled, .resizable]
        sheet.minSize = NSSize(width: 820, height: 540)
        sheet.isReleasedWhenClosed = false
        window.beginSheet(sheet)
        reloadTaskRunComparison(runID: runID, viewModel: viewModel)
    }

    private func reloadTaskRunComparison(
        runID: String,
        viewModel: TaskRunComparisonSheetViewModel
    ) {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        let revision = viewModel.beginReload()
        Task { @MainActor [weak viewModel] in
            do {
                let comparisons = try await delegate.taskRunComparisons(runID: runID)
                guard let latestRun = delegate.taskRunsSnapshot().first(where: {
                    $0.id == runID
                }) else {
                    throw TaskRunError.runNotFound(runID)
                }
                viewModel?.apply(
                    run: latestRun,
                    comparisons: comparisons,
                    revision: revision
                )
            } catch {
                viewModel?.failReload(
                    String(describing: error),
                    revision: revision
                )
            }
        }
    }

    private func promoteTaskRunFromSheet(
        runID: String,
        candidateID: String,
        viewModel: TaskRunComparisonSheetViewModel,
        sheet: NSWindow,
        parentWindow: NSWindow?
    ) {
        guard let delegate = NSApp.delegate as? AppDelegate,
              !viewModel.isPromoting else {
            return
        }
        viewModel.beginPromotion()
        Task { @MainActor [weak self, weak parentWindow, weak sheet] in
            do {
                let outcome = try await delegate.promoteTaskRun(
                    runID: runID,
                    candidateID: candidateID
                )
                if let sheet, sheet.sheetParent === parentWindow {
                    parentWindow?.endSheet(sheet)
                }
                DispatchQueue.main.async { [weak self] in
                    self?.presentTaskRunPromotionResult(outcome)
                }
            } catch {
                viewModel.failPromotion(String(describing: error))
            }
        }
    }

    private func presentTaskRunPromotionResult(_ outcome: TaskRunPromotionOutcome) {
        let localizer = appLocalizer()
        let alert = NSAlert()
        if outcome.cleanupFailures.isEmpty {
            alert.alertStyle = .informational
            alert.messageText = localizer.string(
                "taskRun.promote.successTitle",
                fallback: "Candidate Promoted"
            )
            alert.informativeText = String(
                format: localizer.string(
                    "taskRun.promote.successMessage",
                    fallback: "Merged candidate %@ into the origin checkout."
                ),
                outcome.run.promotedCandidateID ?? ""
            )
        } else {
            alert.alertStyle = .warning
            alert.messageText = localizer.string(
                "taskRun.promote.cleanupTitle",
                fallback: "Candidate Promoted with Cleanup Warnings"
            )
            alert.informativeText = outcome.cleanupFailures.joined(separator: "\n")
        }
        alert.addButton(withTitle: localizer.string("common.ok", fallback: "OK"))
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func presentTaskRunAlert(message: String) {
        let localizer = appLocalizer()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizer.string(
            "taskRun.alert.title",
            fallback: "Parallel Task"
        )
        alert.informativeText = message
        alert.addButton(withTitle: localizer.string("common.ok", fallback: "OK"))
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func localizedTaskRunString(_ key: String, fallback: String) -> String {
        appLocalizer().string(key, fallback: fallback)
    }
}
