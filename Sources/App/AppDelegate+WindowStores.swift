// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+WindowStores.swift - Main-window app store ownership boundary.

extension AppDelegate {
    var mainWindowAppStores: MainWindowAppStores {
        MainWindowAppStores(
            auroraWorkspaceTitleStore: auroraWorkspaceTitleStore,
            projectRegistry: projectRegistry,
            projectConfigWatcherRegistry: projectConfigWatcherRegistry,
            tabConfigProjectContextStore: tabConfigProjectContextStore,
            commandBlockStore: terminalBlockStore,
            worktreeService: sharedWorktreeService
        )
    }
}
