// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowAppStores.swift - App-scoped state injected into every main window.

@MainActor
struct MainWindowAppStores {
    let auroraWorkspaceTitleStore: AuroraWorkspaceTitleStore
    let projectRegistry: ProjectRegistry?
    let projectConfigWatcherRegistry: ProjectConfigWatcherRegistry
    let tabConfigProjectContextStore: TabConfigProjectContextStore
    let commandBlockStore: TerminalBlockStore
}
