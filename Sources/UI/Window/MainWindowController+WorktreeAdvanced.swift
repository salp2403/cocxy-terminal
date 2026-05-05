// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+WorktreeAdvanced.swift - Phase W worktree UI wiring.

import AppKit
import SwiftUI

extension MainWindowController {
    @MainActor
    func showWorktreeAdvancedModal() {
        guard let window else { return }

        let config = configService?.current.worktree ?? WorktreeConfig.defaults
        let viewModel = WorktreeAdvancedModalViewModel(
            initialBaseRef: config.baseRef,
            availableBaseRefs: availableWorktreeBaseRefs(),
            detectedAgent: activeWorktreeAgentName(),
            previewID: WorktreeID.generate(length: config.idLength)
        )

        var sheet: NSWindow!
        let view = WorktreeAdvancedModal(
            viewModel: viewModel,
            onCancel: { [weak window] in
                if let sheet { window?.endSheet(sheet) }
            },
            onCreate: { [weak self, weak window] request in
                if let sheet { window?.endSheet(sheet) }
                Task { @MainActor in
                    guard let delegate = NSApp.delegate as? AppDelegate else { return }
                    let result = await delegate.performWorktreeCLIRequest(
                        kind: "add",
                        params: request.cliParams
                    )
                    if !result.0 {
                        self?.presentWorktreeError(result.1["error"] ?? "Worktree creation failed.")
                    }
                }
            }
        )
        sheet = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet.title = "New Worktree"
        sheet.styleMask = [.titled]
        sheet.isReleasedWhenClosed = false
        window.beginSheet(sheet)
    }

    @MainActor
    func showWorktreeBatchCleanupSheet() {
        guard let window else { return }
        guard let config = configService?.current.worktree, config.enabled else {
            presentWorktreeError(AppDelegate.worktreeEnablementErrorMessage)
            return
        }
        guard let originRepo = currentWorktreeOriginRepo() else {
            presentWorktreeError("No active repository is available for worktree cleanup.")
            return
        }

        let origin = AppDelegate.resolveOriginRepoRoot(from: originRepo)
        let store = WorktreeManifestStore.forRepo(
            basePath: config.basePath,
            originRepoPath: origin
        )
        let service = AppDelegate.sharedWorktreeService
        Task { [weak self, weak window] in
            do {
                let plan = try await service.mergedCleanupPlan(
                    originRepoPath: origin,
                    baseRef: config.baseRef,
                    store: store
                )
                await MainActor.run {
                    self?.presentWorktreeBatchCleanupSheet(
                        plan: plan,
                        baseRef: config.baseRef,
                        originRepoPath: origin,
                        config: config,
                        window: window
                    )
                }
            } catch {
                await MainActor.run {
                    self?.presentWorktreeError("Worktree cleanup failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @MainActor
    private func presentWorktreeBatchCleanupSheet(
        plan: WorktreeBatchCleanupPlan,
        baseRef: String,
        originRepoPath: URL,
        config: WorktreeConfig,
        window: NSWindow?
    ) {
        guard let window else { return }
        let viewModel = WorktreeBatchCleanupSheetViewModel(plan: plan, baseRef: baseRef)
        var sheet: NSWindow!
        let view = WorktreeBatchCleanupSheet(
            viewModel: viewModel,
            onCancel: { [weak window] in
                if let sheet { window?.endSheet(sheet) }
            },
            onCleanUp: { [weak self, weak window] in
                if let sheet { window?.endSheet(sheet) }
                Task { @MainActor in
                    guard let delegate = NSApp.delegate as? AppDelegate else { return }
                    let result = await delegate.performWorktreeCleanupMergedRequest(
                        originRepoPath: originRepoPath,
                        basePath: config.basePath,
                        baseRef: baseRef
                    )
                    if !result.0 {
                        self?.presentWorktreeError(result.1["error"] ?? "Worktree cleanup failed.")
                    }
                }
            }
        )
        sheet = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet.title = "Clean Up Worktrees"
        sheet.styleMask = [.titled]
        sheet.isReleasedWhenClosed = false
        window.beginSheet(sheet)
    }

    @MainActor
    private func availableWorktreeBaseRefs() -> [String] {
        guard let repo = currentWorktreeOriginRepo() else {
            return ["HEAD"]
        }
        let origin = AppDelegate.resolveOriginRepoRoot(from: repo)
        guard let result = try? CodeReviewGit.run(
            workingDirectory: origin,
            arguments: ["branch", "--format=%(refname:short)"]
        ),
        result.terminationStatus == 0 else {
            return ["HEAD"]
        }
        let branches = result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return ["HEAD"] + branches
    }

    @MainActor
    private func activeWorktreeAgentName() -> String? {
        guard let tabID = tabManager.activeTabID else { return nil }
        return resolveSurfaceAgentState(for: tabID).detectedAgent?.name
    }

    @MainActor
    private func currentWorktreeOriginRepo() -> URL? {
        guard let tab = tabManager.activeTab else { return nil }
        return tab.worktreeOriginRepo ?? tab.workingDirectory
    }

    @MainActor
    private func presentWorktreeError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Worktree"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
