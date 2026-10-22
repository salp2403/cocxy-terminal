// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+CurrentDirectory.swift - Canonical OSC 7 state updates.

import Foundation

extension MainWindowController {
    func handleCurrentDirectoryChange(
        _ directoryURL: URL,
        tabID: TabID,
        surfaceID: SurfaceID?
    ) {
        let previousDirectory = tabManager.tab(for: tabID).map {
            ProjectPathCanonicalizer.canonicalURL($0.workingDirectory)
        }
        let canonicalDirectory = ProjectPathCanonicalizer.canonicalURL(directoryURL)
        if let surfaceID {
            surfaceWorkingDirectories[surfaceID] = directoryURL
        }
        if previousDirectory != canonicalDirectory {
            invalidateProjectCaches(previousDirectory)
            invalidateProjectCaches(canonicalDirectory)
        }
        observeProjectDirectory(canonicalDirectory, previousDirectory: previousDirectory)
        let branch = gitInfoProvider.currentBranch(at: directoryURL)
        tabManager.updateTab(id: tabID) { tab in
            tab.workingDirectory = directoryURL
            tab.gitBranch = branch
            tab.lastActivityAt = Date()
        }
        tabBarViewModel?.syncWithManager()
        refreshStatusBar()
        refreshTabStrip()
        sessionRegistry?.updateWorkingDirectory(
            sessionIDForTab(tabID),
            directory: directoryURL
        )
        if previousDirectory != canonicalDirectory {
            var metadata = ["source": "osc7"]
            if let surfaceID {
                metadata["surface_id"] = surfaceID.rawValue.uuidString
            }
            recordLocalActivity(
                kind: .projectSwitched,
                summary: projectSwitchActivitySummary(canonicalDirectory),
                workingDirectory: directoryURL,
                sessionID: sessionIDForTab(tabID).rawValue.uuidString,
                metadata: metadata
            )
        }
        reloadProjectConfig(for: tabID, directoryURL: directoryURL)
    }

    private func invalidateProjectCaches(_ directory: URL?) {
        guard let directory else { return }
        projectResolver.invalidate(directory: directory)
        (gitInfoProvider as? GitInfoProviderImpl)?.invalidateCache(for: directory)
    }

    private func reloadProjectConfig(for tabID: TabID, directoryURL: URL) {
        let tabSnapshot = tabManager.tab(for: tabID)
        let inheritProjectConfig = configService?.current.worktree.inheritProjectConfig ?? true
        let originRepo = inheritProjectConfig ? tabSnapshot?.worktreeOriginRepo : nil
        let newProjectConfig = ProjectConfigService().loadConfig(
            for: directoryURL,
            originRepo: originRepo
        )
        tabManager.updateTab(id: tabID) { tab in
            tab.projectConfig = newProjectConfig
        }
        applyProjectConfig(for: tabID)
    }
}
