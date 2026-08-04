// Copyright (c) 2026 Said Arturo Lopez. MIT License.

@testable import CocxyTerminal
import CocxyShared

@MainActor
extension MainWindowController {
    /// Test-only convenience that keeps isolated fixtures out of app runtime wiring.
    convenience init(
        bridge: any TerminalEngine,
        configService: ConfigService? = nil,
        tabManager: TabManager? = nil,
        auroraWorkspaceTitleStore: AuroraWorkspaceTitleStore? = nil,
        projectRegistry: ProjectRegistry? = nil,
        commandBlockStore: TerminalBlockStore? = nil,
        gitInfoProvider: (any GitInfoProviding)? = nil,
        projectResolver: (any ProjectResolving)? = nil,
        worktreeService: WorktreeService? = nil,
        terminalEngineFactory: ((TerminalEnginePreference) -> (any TerminalEngine)?)? = nil,
        voiceConsentCoordinator: VoiceConsentCoordinator = VoiceConsentCoordinator(),
        deferContentSetup: Bool = false
    ) {
        let resolvedGitInfoProvider = gitInfoProvider ?? GitInfoProviderImpl()
        let resolvedWorktreeService = worktreeService
            ?? WorktreeService(gitInfoProvider: resolvedGitInfoProvider)
        self.init(
            bridge: bridge,
            configService: configService,
            tabManager: tabManager,
            appStores: MainWindowAppStores(
                auroraWorkspaceTitleStore: auroraWorkspaceTitleStore ?? AuroraWorkspaceTitleStore(),
                projectRegistry: projectRegistry,
                projectConfigWatcherRegistry: ProjectConfigWatcherRegistry(),
                tabConfigProjectContextStore: TabConfigProjectContextStore(),
                commandBlockStore: commandBlockStore ?? TerminalBlockStore(),
                worktreeService: resolvedWorktreeService
            ),
            gitInfoProvider: resolvedGitInfoProvider,
            projectResolver: projectResolver,
            terminalEngineFactory: terminalEngineFactory,
            voiceConsentCoordinator: voiceConsentCoordinator,
            deferContentSetup: deferContentSetup
        )
    }
}
