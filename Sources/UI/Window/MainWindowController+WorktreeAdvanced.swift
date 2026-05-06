// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+WorktreeAdvanced.swift - Phase W worktree UI wiring.

import AppKit
import SwiftUI

extension MainWindowController {
    @MainActor
    func showWorktreeAdvancedModal() {
        guard let window else { return }

        let config = configService?.current.worktree ?? WorktreeConfig.defaults
        let localizer = appLocalizer()
        let viewModel = WorktreeAdvancedModalViewModel(
            initialBaseRef: config.baseRef,
            availableBaseRefs: availableWorktreeBaseRefs(),
            detectedAgent: activeWorktreeAgentName(),
            previewID: WorktreeID.generate(length: config.idLength)
        )

        var sheet: NSWindow!
        let view = WorktreeAdvancedModal(
            viewModel: viewModel,
            localizer: localizer,
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
                        self?.presentWorktreeError(
                            result.1["error"] ?? Self.localizedWorktreeCreationFailed(using: localizer)
                        )
                    }
                }
            }
        )
        sheet = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet.title = WorktreeAdvancedModal.localizedTitle(using: localizer)
        sheet.styleMask = [.titled]
        sheet.isReleasedWhenClosed = false
        window.beginSheet(sheet)
    }

    @MainActor
    func showWorktreeBatchCleanupSheet() {
        guard let window else { return }
        let localizer = appLocalizer()
        guard let config = configService?.current.worktree, config.enabled else {
            presentWorktreeError(Self.localizedWorktreeFeatureDisabled(using: localizer))
            return
        }
        guard let originRepo = currentWorktreeOriginRepo() else {
            presentWorktreeError(Self.localizedNoActiveWorktreeRepository(using: localizer))
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
                    self?.presentWorktreeError(
                        Self.localizedWorktreeCleanupFailed(
                            error.localizedDescription,
                            using: localizer
                        )
                    )
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
        let localizer = appLocalizer()
        let viewModel = WorktreeBatchCleanupSheetViewModel(plan: plan, baseRef: baseRef)
        var sheet: NSWindow!
        let view = WorktreeBatchCleanupSheet(
            viewModel: viewModel,
            localizer: localizer,
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
                        self?.presentWorktreeError(
                            result.1["error"] ?? Self.localizedWorktreeCleanupFailed(using: localizer)
                        )
                    }
                }
            }
        )
        sheet = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet.title = WorktreeBatchCleanupSheet.localizedTitle(using: localizer)
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
        let localizer = appLocalizer()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Self.localizedWorktreeAlertTitle(using: localizer)
        alert.informativeText = message
        alert.addButton(withTitle: localizer.string("common.ok", fallback: "OK"))
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    static func localizedWorktreeCreationFailed(using localizer: AppLocalizer) -> String {
        localizer.string("worktree.advanced.creationFailed", fallback: "Worktree creation failed.")
    }

    static func localizedWorktreeCleanupFailed(
        _ detail: String? = nil,
        using localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) -> String {
        if let detail, !detail.isEmpty {
            return String(
                format: localizer.string(
                    "worktree.batchCleanup.failedWithDetail",
                    fallback: "Worktree cleanup failed: %@"
                ),
                detail
            )
        }
        return localizer.string("worktree.batchCleanup.failed", fallback: "Worktree cleanup failed.")
    }

    static func localizedNoActiveWorktreeRepository(using localizer: AppLocalizer) -> String {
        localizer.string(
            "worktree.batchCleanup.noActiveRepository",
            fallback: "No active repository is available for worktree cleanup."
        )
    }

    static func localizedWorktreeFeatureDisabled(using localizer: AppLocalizer) -> String {
        localizer.string(
            "worktree.featureDisabled",
            fallback: AppDelegate.worktreeEnablementErrorMessage
        )
    }

    static func localizedWorktreeAlertTitle(using localizer: AppLocalizer) -> String {
        localizer.string("worktree.alert.title", fallback: "Worktree")
    }
}
