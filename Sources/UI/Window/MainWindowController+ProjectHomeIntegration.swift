// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+ProjectHomeIntegration.swift - Project home panel and actions.

import AppKit
import Combine
import SwiftUI

extension MainWindowController {
    func wireProjectHomeInbox(to controller: AuroraChromeController) {
        projectInboxCancellable = injectedTaskInboxStore?.$snapshot
            .map(\.badgeCounts)
            .removeDuplicates()
            .sink { [weak controller] counts in
                controller?.applyProjectTaskCountsSnapshot(counts)
            }
    }

    func makeProjectHomePanelView(panel: PanelInfo, tabID: TabID?) -> NSView {
        let localizer = appLocalizer()
        guard let store = injectedTaskInboxStore else {
            return NSHostingView(rootView: ProjectHomeUnavailablePanelView(localizer: localizer))
        }
        let fallbackRoot = tabID.flatMap { tabManager.tab(for: $0)?.workingDirectory }
            ?? tabManager.activeTab?.workingDirectory
        guard let requestedRoot = panel.filePath ?? fallbackRoot else {
            return NSHostingView(rootView: ProjectHomeUnavailablePanelView(localizer: localizer))
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: requestedRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return NSHostingView(rootView: ProjectHomeUnavailablePanelView(
                localizer: localizer,
                message: localizer.string(
                    "projectHome.unavailable.folder",
                    fallback: "The project folder is no longer available."
                )
            ))
        }

        let descriptor = projectResolver.resolveProject(for: requestedRoot)
        let projectID = descriptor.groupingID
        let projectRoot = descriptor.groupingRootURL
        let record = projectRegistry?.record(for: projectID)
        let displayName = auroraWorkspaceTitleStore.title(for: projectID.rawValue)
            ?? descriptor.groupingAutomaticName
        let globalConfig = configService?.current ?? .defaults
        let sourceTab = tabID.flatMap { tabManager.tab(for: $0) }
        let worktreeConfig: WorktreeConfig
        if let sourceTab,
           projectResolver.resolveProject(for: sourceTab.workingDirectory).groupingID == projectID {
            worktreeConfig = Self.effectiveWorktreeConfig(for: sourceTab, globalConfig: globalConfig)
        } else {
            worktreeConfig = globalConfig.worktree
        }

        let actions = ProjectHomeActions(
            createSession: { [weak self] in
                guard let self else { return }
                let tabID = createTab(workingDirectory: projectRoot)
                _ = focusTab(id: tabID)
            },
            createWorktree: worktreeConfig.enabled ? { [weak self] in
                self?.showWorktreeAdvancedModal(projectRoot: projectRoot)
            } : nil,
            launchTeam: { request in
                guard let delegate = NSApp.delegate as? AppDelegate else {
                    throw ProjectHomeActionFailure(message: "Project team services are unavailable.")
                }
                try await delegate.launchProjectTeam(request, projectRoot: projectRoot)
            },
            openCodeReview: { [weak self] in
                self?.openProjectCodeReview(projectRoot: projectRoot)
            },
            activateEntry: { [weak self] navigation in
                guard let tabID = navigation.tabID else { return }
                if let delegate = NSApp.delegate as? AppDelegate,
                   let router = delegate.windowTabRouter {
                    router.activateTab(id: tabID)
                } else {
                    _ = self?.focusTab(id: tabID)
                }
            },
            focusWorktree: worktreeConfig.enabled ? { id in
                guard let delegate = NSApp.delegate as? AppDelegate else {
                    throw ProjectHomeActionFailure(message: "Worktree services are unavailable.")
                }
                let result = await delegate.performProjectWorktreeRequest(
                    kind: "focus",
                    projectRoot: projectRoot,
                    params: ["id": id]
                )
                guard result.0 else {
                    throw ProjectHomeActionFailure(
                        message: result.1["error"] ?? "The worktree could not be opened."
                    )
                }
            } : nil,
            openRecentDiff: { [weak self] sessionID in
                _ = self?.performVisualSplitWithPanel(
                    isVertical: true,
                    panel: .aiEditHistory(sessionID: sessionID, workingDirectory: projectRoot),
                    appendToEnd: true,
                    focusNewPanel: true
                )
            }
        )
        let viewModel = ProjectHomePanelViewModel(
            projectID: projectID,
            projectRoot: projectRoot,
            displayName: displayName,
            accent: record?.accent,
            fallbackRemote: record?.remoteOrigin,
            worktreeConfig: worktreeConfig,
            recentDiffProvider: { [weak self] in
                self?.injectedSessionDiffTracker?.latestSessionId(for: projectRoot)
            },
            actions: actions
        )
        return NSHostingView(rootView: ProjectHomePanelView(
            viewModel: viewModel,
            inboxStore: store,
            localizer: localizer
        ))
    }

    @discardableResult
    func openProjectHome(projectRoot: URL) -> Bool {
        guard let tabID = visibleTabID ?? tabManager.activeTabID else { return false }
        let splitManager = tabSplitCoordinator.splitManager(for: tabID)
        let canonicalRoot = projectRoot.resolvingSymlinksInPath().standardizedFileURL
        if let contentID = splitManager.panelTypes.first(where: { _, info in
            info.type == .projectHome
                && info.filePath?.resolvingSymlinksInPath().standardizedFileURL == canonicalRoot
        })?.key,
           let leaf = splitManager.rootNode.allLeafIDs().first(where: {
               $0.terminalID == contentID
           }) {
            splitManager.focusLeaf(id: leaf.leafID)
            if let panelView = panelContentViews[contentID] {
                focusPanelView(panelView)
            }
            updateWorkspaceToolbar()
            refreshTabStrip(syncFromFirstResponder: false)
            return true
        }
        return performVisualSplitWithPanel(
            isVertical: true,
            panel: .projectHome(projectRoot: projectRoot),
            appendToEnd: true,
            focusNewPanel: true
        )
    }

    private func openProjectCodeReview(projectRoot: URL) {
        guard let delegate = NSApp.delegate as? AppDelegate else {
            presentProjectHomeActionError("Project services are unavailable.")
            return
        }
        do {
            let projectID = projectResolver.resolveProject(for: projectRoot).groupingID
            let tabID = try delegate.activateProject(projectID)
            guard let controller = delegate.controllerContainingTab(tabID) else {
                throw ProjectActivationError.noWindow
            }
            controller.showCodeReviewPanel()
        } catch {
            presentProjectHomeActionError(
                (error as? LocalizedError)?.errorDescription ?? "Code Review could not be opened."
            )
        }
    }

    private func presentProjectHomeActionError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = appLocalizer().string(
            "projectHome.action.error.title",
            fallback: "Action Failed"
        )
        alert.informativeText = message
        alert.addButton(withTitle: appLocalizer().string("common.ok", fallback: "OK"))
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
