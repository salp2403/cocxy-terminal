// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+ProjectConfigWatcher.swift - Shared project hot reload wiring.

import Foundation

extension MainWindowController {
    func synchronizeProjectConfigWatcher(
        for tab: Tab,
        preserveCurrentLeaseWhenMissing: Bool = false
    ) {
        let inheritProjectConfig = configService?.current.worktree.inheritProjectConfig ?? true
        let originRepo = inheritProjectConfig ? tab.worktreeOriginRepo : nil
        let configPath = ProjectConfigService().findConfigPath(
            for: tab.workingDirectory,
            originRepo: originRepo
        )

        guard let configPath else {
            if !preserveCurrentLeaseWhenMissing {
                releaseProjectConfigWatcher()
            }
            return
        }

        let projectID = projectResolver.resolveProject(for: tab.workingDirectory).groupingID
        if let lease = projectConfigWatchLease,
           projectConfigWatcherRegistry.matches(
               lease,
               projectID: projectID,
               configFilePath: configPath
           ) {
            projectConfigWatcherRegistry.touch(lease)
            return
        }

        releaseProjectConfigWatcher()
        projectConfigWatchLease = projectConfigWatcherRegistry.acquire(
            projectID: projectID,
            configFilePath: configPath
        ) { [weak self, tabID = tab.id] in
            self?.reloadProjectConfigFromWatcher(for: tabID)
        }
    }

    func releaseProjectConfigWatcher() {
        guard let lease = projectConfigWatchLease else { return }
        projectConfigWatcherRegistry.release(lease)
        projectConfigWatchLease = nil
    }

    private func reloadProjectConfigFromWatcher(for tabID: TabID) {
        guard let currentTab = tabManager.tab(for: tabID) else { return }
        let inheritProjectConfig = configService?.current.worktree.inheritProjectConfig ?? true
        let originRepo = inheritProjectConfig ? currentTab.worktreeOriginRepo : nil
        let newConfig = ProjectConfigService().loadConfig(
            for: currentTab.workingDirectory,
            originRepo: originRepo
        )
        tabManager.updateTab(id: tabID) { tab in
            tab.projectConfig = newConfig
        }

        let effective = effectiveConfig(for: tabID)
        for viewModel in viewModelsForTab(tabID) {
            viewModel.setDefaultFontSize(effective.appearance.fontSize)
        }
        for surfaceID in surfaceIDs(for: tabID) {
            applyTerminalFont(
                family: effective.appearance.fontFamily,
                size: effective.appearance.fontSize,
                to: surfaceID
            )
        }
        if visibleTabID == tabID {
            applyEffectiveAppearance(effective.appearance)
            synchronizeProjectConfigWatcher(
                for: currentTab,
                preserveCurrentLeaseWhenMissing: true
            )
        }
    }
}
