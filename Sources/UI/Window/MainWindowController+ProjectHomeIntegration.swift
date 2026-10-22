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
        guard let store = injectedTaskInboxStore,
              let fanOutCoordinator = injectedProjectFanOutCoordinator else {
            return makeShellHostingView(rootView: ProjectHomeUnavailablePanelView(localizer: localizer))
        }
        let fallbackRoot = tabID.flatMap { tabManager.tab(for: $0)?.workingDirectory }
            ?? tabManager.activeTab?.workingDirectory
        guard let requestedRoot = panel.filePath ?? fallbackRoot else {
            return makeShellHostingView(rootView: ProjectHomeUnavailablePanelView(localizer: localizer))
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: requestedRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return makeShellHostingView(rootView: ProjectHomeUnavailablePanelView(
                localizer: localizer,
                messageKey: "projectHome.unavailable.folder",
                messageFallback: "The project folder is no longer available."
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
                    throw ProjectHomeActionFailure.servicesUnavailable
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
                    throw ProjectHomeActionFailure.servicesUnavailable
                }
                let result = await delegate.performProjectWorktreeRequest(
                    kind: "focus",
                    projectRoot: projectRoot,
                    params: ["id": id]
                )
                guard result.0 else {
                    throw ProjectHomeActionFailure.worktreeOpenFailed
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
            localizer: localizer,
            headerUpdates: projectHomeHeaderUpdates(
                projectID: projectID,
                automaticName: descriptor.groupingAutomaticName
            ),
            activitySummaryLoader: { [weak self] projectID in
                guard let self else { return .unavailable }
                return await self.loadProjectActivitySummary(for: projectID)
            },
            recentDiffProvider: { [weak self] in
                self?.injectedSessionDiffTracker?.latestSessionId(for: projectRoot)
            },
            actions: actions
        )
        let fanOutViewModel = makeProjectFanOutViewModel(
            projectID: projectID,
            projectRoot: projectRoot,
            preferredSourceTabID: sourceTab?.id,
            record: record,
            worktreeConfig: worktreeConfig
        )
        return makeShellHostingView(rootView: ProjectHomePanelView(
            viewModel: viewModel,
            fanOutViewModel: fanOutViewModel,
            inboxStore: store,
            fanOutCoordinator: fanOutCoordinator,
            targetTabID: tabID ?? visibleTabID ?? tabManager.activeTabID,
            localizer: localizer
        ))
    }

    private func projectHomeHeaderUpdates(
        projectID: ProjectID,
        automaticName: String
    ) -> AnyPublisher<ProjectHomeHeaderState, Never> {
        let records = projectRegistry?.$records.eraseToAnyPublisher()
            ?? Just<[ProjectRecord]>([]).eraseToAnyPublisher()
        return Publishers.CombineLatest(records, auroraWorkspaceTitleStore.$revision)
            .map { [weak self] records, _ in
                let record = records.first { $0.id == projectID }
                return ProjectHomeHeaderState(
                    displayName: self?.auroraWorkspaceTitleStore.title(for: projectID.rawValue)
                        ?? automaticName,
                    accent: record?.accent,
                    remoteOrigin: record?.remoteOrigin
                )
            }
            .eraseToAnyPublisher()
    }

    @discardableResult
    func openProjectHome(projectRoot: URL, in targetTabID: TabID? = nil) -> Bool {
        if let targetTabID, visibleTabID != targetTabID {
            guard focusTab(id: targetTabID) else { return false }
        }
        guard let tabID = targetTabID ?? visibleTabID ?? tabManager.activeTabID,
              visibleTabID == tabID else { return false }
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
            presentProjectHomeActionError(
                ProjectHomeActionFailure.servicesUnavailable,
                context: .codeReview
            )
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
            presentProjectHomeActionError(error, context: .codeReview)
        }
    }

    private func presentProjectHomeActionError(
        _ error: Error,
        context: ProjectErrorPresentationContext
    ) {
        let localizer = appLocalizer()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizer.string(
            "projectHome.action.error.title",
            fallback: "Action Failed"
        )
        alert.informativeText = localizer.projectErrorMessage(for: error, context: context)
        alert.addButton(withTitle: localizer.string("common.ok", fallback: "OK"))
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
