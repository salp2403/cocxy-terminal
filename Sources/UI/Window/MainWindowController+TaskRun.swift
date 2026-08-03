// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+TaskRun.swift - Project Home fan-out command routing.

import AppKit

@MainActor
extension MainWindowController {
    func showTaskRunLaunchSheet() {
        guard window != nil,
              let delegate = NSApp.delegate as? AppDelegate,
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

        let projectID = projectResolver.resolveProject(
            for: context.originRepoPath
        ).groupingID
        do {
            let targetTabID = try delegate.showProjectHome(projectID)
            delegate.projectFanOutCoordinator.presentLaunch(
                projectID: projectID,
                targetTabID: targetTabID
            )
        } catch {
            presentTaskRunAlert(message: String(describing: error))
        }
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
                    self?.showTaskRunComparisonSheet(runID: runID)
                }
            )
        }
        showTransientCommandPaletteOverlay(
            engine: StaticCommandPaletteEngine(actions: actions)
        )
    }

    func showTaskRunComparisonSheet(runID: String) {
        guard let delegate = NSApp.delegate as? AppDelegate,
              let run = delegate.taskRunsSnapshot().first(where: { $0.id == runID }) else {
            presentTaskRunAlert(
                message: localizedTaskRunString(
                    "taskRun.error.notFound",
                    fallback: "The selected parallel task is no longer available."
                )
            )
            return
        }
        do {
            let targetTabID = try delegate.showProjectHome(run.projectID)
            delegate.projectFanOutCoordinator.presentComparison(
                projectID: run.projectID,
                targetTabID: targetTabID,
                runID: run.id
            )
        } catch {
            presentTaskRunAlert(message: String(describing: error))
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
