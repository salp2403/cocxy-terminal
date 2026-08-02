// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SwiftSourceLineBudgetSwiftTestingTests.swift - Contain growth in oversized Swift sources.

import Foundation
import Testing

@Suite("Swift source line budget")
struct SwiftSourceLineBudgetSwiftTestingTests {
    private static let maximumNewFileLines = 600

    private static let existingOversizedFileBudgets: [String: Int] = [
        "CLI/Lib/ArgumentParser.swift": 7086,
        "CLI/Lib/CommandRunner.swift": 2331,
        "CLI/Lib/OutputFormatter.swift": 954,
        "CLI/Lib/Shared/CLICommandDefinition.swift": 947,
        "Daemon/Lib/PTYDaemonSurface.swift": 784,
        "Sources/App/AppDelegate+AgentWiring.swift": 1176,
        "Sources/App/AppDelegate+CLICommands.swift": 1041,
        "Sources/App/AppDelegate+GitHubCLI.swift": 649,
        "Sources/App/AppDelegate+MenuSetup.swift": 726,
        "Sources/App/AppDelegate+SessionManagement.swift": 913,
        "Sources/App/AppDelegate.swift": 3457,
        "Sources/Core/Infrastructure/AppSocketCommandHandler.swift": 6863,
        "Sources/Core/Infrastructure/BrowserAutomationScriptLibrary.swift": 2028,
        "Sources/Core/Infrastructure/CocxyCoreBridge.swift": 5073,
        "Sources/Core/Infrastructure/MetalTerminalRenderer.swift": 1058,
        "Sources/Core/Infrastructure/SocketServer.swift": 935,
        "Sources/Domain/Agent/AgentLocalToolExecutor.swift": 868,
        "Sources/Domain/Agent/AgentProviderClient.swift": 1694,
        "Sources/Domain/Agent/AgentReadOnlyToolExecutor.swift": 916,
        "Sources/Domain/Agent/AgentToolPermission.swift": 880,
        "Sources/Domain/AgentConfigService.swift": 985,
        "Sources/Domain/AgentDetection/AgentDetectionEngine.swift": 895,
        "Sources/Domain/AgentDetection/CocxyCoreSemanticAdapter.swift": 646,
        "Sources/Domain/AgentTeams/Providers/AgentTeamProviderAdapters.swift": 693,
        "Sources/Domain/Browser/Import/BrowserImportModels.swift": 917,
        "Sources/Domain/Browser/Import/BrowserImporter.swift": 685,
        "Sources/Domain/Browser/Import/BrowserSourceImporters.swift": 963,
        "Sources/Domain/Cells/CellCLICommandService.swift": 731,
        "Sources/Domain/Cells/CommandBackedCloudCellProvider.swift": 1397,
        "Sources/Domain/CodeReview/CodeReviewPanelViewModel.swift": 1526,
        "Sources/Domain/ConfigService.swift": 1991,
        "Sources/Domain/DBCloudHelpers/DBCloudHelperRunner.swift": 637,
        "Sources/Domain/Dashboard/AgentDashboardViewModel.swift": 1358,
        "Sources/Domain/GitHub/GitHubModels.swift": 1035,
        "Sources/Domain/GitHub/GitHubPaneViewModel.swift": 1928,
        "Sources/Domain/GitHub/GitHubService.swift": 1031,
        "Sources/Domain/HookIntegration/HookEvent.swift": 649,
        "Sources/Domain/Markdown/MarkdownRenderer.swift": 628,
        "Sources/Domain/Models/KeybindingAction.swift": 671,
        "Sources/Domain/PTYDaemon/PTYDaemonClient.swift": 889,
        "Sources/Domain/PluginMarketplace/PluginMarketplace.swift": 990,
        "Sources/Domain/Process/BoundedProcessRunner.swift": 1147,
        "Sources/Domain/Process/LaunchdCoalitionProcessRunner.swift": 713,
        "Sources/Domain/Process/LaunchdCoalitionProcessSupport.swift": 3465,
        "Sources/Domain/Process/LaunchdProcessBroker.swift": 1902,
        "Sources/Domain/Process/LaunchdProcessSupervisor.swift": 686,
        "Sources/Domain/Protocols/CLISocketServing.swift": 647,
        "Sources/Domain/Protocols/ConfigProviding.swift": 3055,
        "Sources/Domain/Protocols/TerminalEngine.swift": 624,
        "Sources/Domain/RemoteWorkspace/Proxy/SOCKS5Proxy.swift": 604,
        "Sources/Domain/RemoteWorkspace/Relay/RelayAuthBroker.swift": 875,
        "Sources/Domain/RemoteWorkspace/Relay/RelayManager.swift": 720,
        "Sources/Domain/RemoteWorkspace/RemoteConnectionManager.swift": 1091,
        "Sources/Domain/RemoteWorkspace/SFTPClient.swift": 2701,
        "Sources/Domain/RemoteWorkspace/SFTPMuxSession.swift": 638,
        "Sources/Domain/RemoteWorkspace/SSHDirectTCPTransport.swift": 1117,
        "Sources/Domain/RemoteWorkspace/SSHMultiplexer.swift": 2140,
        "Sources/Domain/SocketPrivilegedCommandAuthorization.swift": 818,
        "Sources/Domain/SplitManager.swift": 727,
        "Sources/Domain/Templates/ProjectTemplateSecureDestinationWriter.swift": 655,
        "Sources/Domain/ThemeEngine.swift": 695,
        "Sources/Domain/Vim/VimController.swift": 3207,
        "Sources/Domain/Worktree/WorktreeService.swift": 856,
        "Sources/Domain/iCloudSync/ICloudSyncArtifacts.swift": 662,
        "Sources/UI/Agent/AgentPanelView.swift": 849,
        "Sources/UI/Agent/AgentPanelViewModel.swift": 661,
        "Sources/UI/Browser/BrowserContentView.swift": 991,
        "Sources/UI/Browser/BrowserDevToolsView.swift": 737,
        "Sources/UI/Browser/BrowserPanelView.swift": 1364,
        "Sources/UI/Browser/BrowserViewModel.swift": 1790,
        "Sources/UI/Browser/BrowserWebKitAutomationBridge.swift": 692,
        "Sources/UI/Browser/Import/BrowserImportWizardView.swift": 984,
        "Sources/UI/CodeReview/CodeReviewPanelView.swift": 1232,
        "Sources/UI/CodeReview/DiffContentView.swift": 665,
        "Sources/UI/CodeReview/ReviewToolbarView.swift": 612,
        "Sources/UI/Design/AuroraChromeController.swift": 921,
        "Sources/UI/Design/AuroraModels.swift": 618,
        "Sources/UI/Design/AuroraSidebarView.swift": 1663,
        "Sources/UI/Design/AuroraStatusBarView.swift": 701,
        "Sources/UI/Editor/EditorView.swift": 1301,
        "Sources/UI/GitHub/GitHubPaneView.swift": 830,
        "Sources/UI/Markdown/MarkdownContentView.swift": 754,
        "Sources/UI/Markdown/MarkdownFileExplorerView.swift": 657,
        "Sources/UI/Markdown/MarkdownSourceView.swift": 669,
        "Sources/UI/PluginMarketplace/PluginMarketplaceView.swift": 690,
        "Sources/UI/Preferences/PreferencesView.swift": 3915,
        "Sources/UI/Preferences/PreferencesViewModel.swift": 3212,
        "Sources/UI/RemoteWorkspace/DaemonControlView.swift": 787,
        "Sources/UI/RemoteWorkspace/ProxyControlView.swift": 637,
        "Sources/UI/RemoteWorkspace/RelayControlView.swift": 674,
        "Sources/UI/RemoteWorkspace/RemoteConnectionView.swift": 1550,
        "Sources/UI/RemoteWorkspace/RemoteProfileEditor.swift": 841,
        "Sources/UI/RemoteWorkspace/SFTPBrowserView.swift": 1638,
        "Sources/UI/TabBar/TabBarView.swift": 818,
        "Sources/UI/TabBar/TabItemView.swift": 965,
        "Sources/UI/Terminal/Block/TerminalBlockOverlayView.swift": 627,
        "Sources/UI/Terminal/CocxyCoreView.swift": 3027,
        "Sources/UI/Terminal/PTYDaemonHostView.swift": 1701,
        "Sources/UI/Toolbar/HorizontalTabStripView.swift": 1496,
        "Sources/UI/Vault/VaultSidebarView.swift": 911,
        "Sources/UI/Window/MainWindowController+AuroraIntegration.swift": 1108,
        "Sources/UI/Window/MainWindowController+GitHubPane.swift": 617,
        "Sources/UI/Window/MainWindowController+Overlays.swift": 2948,
        "Sources/UI/Window/MainWindowController+SocketCommandAuthorization.swift": 1184,
        "Sources/UI/Window/MainWindowController+SplitActions.swift": 1576,
        "Sources/UI/Window/MainWindowController+SurfaceLifecycle.swift": 1319,
        "Sources/UI/Window/MainWindowController.swift": 3093,
        "Tests/Unit/AgentDetectionTests/AgentConfigTests.swift": 664,
        "Tests/Unit/AgentDetectionTests/AgentDetectionEngineSurfaceRoutingSwiftTestingTests.swift": 988,
        "Tests/Unit/AgentDetectionTests/AgentDetectionEngineTests.swift": 633,
        "Tests/Unit/AgentDetectionTests/AgentStateMachineTests.swift": 609,
        "Tests/Unit/AgentDetectionTests/PatternMatchingDetectorTests.swift": 758,
        "Tests/Unit/AgentDetectionTests/Phase3IntegrationTests.swift": 1091,
        "Tests/Unit/AgentDetectionTests/RealisticAgentDetectionTests.swift": 682,
        "Tests/Unit/AgentDetectionTests/SurfaceAgentStateResolverSwiftTestingTests.swift": 672,
        "Tests/Unit/AgentTeamsTests/AgentTeamSwiftTestingTests.swift": 855,
        "Tests/Unit/AgentTests/AgentLocalToolExecutorSwiftTestingTests.swift": 946,
        "Tests/Unit/AgentTests/AgentPanelViewModelSwiftTestingTests.swift": 761,
        "Tests/Unit/AgentTests/AgentProviderClientSwiftTestingTests.swift": 1271,
        "Tests/Unit/AgentTests/AgentReadOnlyToolExecutorSwiftTestingTests.swift": 966,
        "Tests/Unit/AgentTests/AgentSessionRunnerSwiftTestingTests.swift": 1740,
        "Tests/Unit/AuroraTests/AuroraChromeControllerSwiftTestingTests.swift": 623,
        "Tests/Unit/BrowserImportTests/BrowserImportSwiftTestingTests.swift": 2811,
        "Tests/Unit/BrowserTests/BrowserScriptableTests.swift": 3450,
        "Tests/Unit/BrowserTests/BrowserViewModelTests.swift": 844,
        "Tests/Unit/BuildToolingTests/CITestGateScriptSwiftTestingTests.swift": 7347,
        "Tests/Unit/CLITests/AgentHooksParitySwiftTestingTests.swift": 1434,
        "Tests/Unit/CLITests/CLICommandTests.swift": 2847,
        "Tests/Unit/CLITests/ExtendedCLITests.swift": 921,
        "Tests/Unit/CLITests/HooksCommandTests.swift": 626,
        "Tests/Unit/CLITests/PTYDaemonHelperIntegrationSwiftTestingTests.swift": 1637,
        "Tests/Unit/CellsTests/CommandBackedCloudCellProviderSwiftTestingTests.swift": 617,
        "Tests/Unit/CocxyCoreTests/CocxyCoreBridgeLockingTests.swift": 701,
        "Tests/Unit/CocxyCoreTests/CocxyCoreBridgeTests.swift": 2459,
        "Tests/Unit/CocxyCoreTests/CocxyCoreCompatibilityMatrixTests.swift": 639,
        "Tests/Unit/CocxyCoreTests/CocxyCoreHostWiringTests.swift": 1528,
        "Tests/Unit/CocxyCoreTests/CocxyCoreViewTests.swift": 2782,
        "Tests/Unit/CodeReviewTests/SessionDiffTrackerSwiftTestingTests.swift": 716,
        "Tests/Unit/CodebaseIndexTests/CodebaseIndexSwiftTestingTests.swift": 666,
        "Tests/Unit/ConfigServiceTests/ConfigServiceTests.swift": 604,
        "Tests/Unit/DBCloudHelperTests/DBCloudHelperSwiftTestingTests.swift": 789,
        "Tests/Unit/DashboardTests/AgentDashboardViewModelTests.swift": 1087,
        "Tests/Unit/EditorTests/EditorViewSwiftTestingTests.swift": 1188,
        "Tests/Unit/FinalQATests/EdgeCaseTests.swift": 942,
        "Tests/Unit/GitHubTests/GitHubMergeModelsSwiftTestingTests.swift": 602,
        "Tests/Unit/GitHubTests/GitHubPaneViewModelSwiftTestingTests.swift": 1490,
        "Tests/Unit/GitHubTests/GitHubServiceMergeSwiftTestingTests.swift": 946,
        "Tests/Unit/GitHubTests/GitHubServiceSwiftTestingTests.swift": 791,
        "Tests/Unit/GitHubTests/GitMergeAftermathServiceSwiftTestingTests.swift": 604,
        "Tests/Unit/IntegrationTests/EndToEndIntegrationTests.swift": 1040,
        "Tests/Unit/LocalizationTests/AppLocalizationSwiftTestingTests.swift": 1610,
        "Tests/Unit/MCPTests/MCPFoundationSwiftTestingTests.swift": 1458,
        "Tests/Unit/MainWindowTests/MainWindowControllerEnhancedTests.swift": 945,
        "Tests/Unit/MainWindowTests/MainWindowSocketPrivilegedCommandAuthorizationSwiftTestingTests.swift": 786,
        "Tests/Unit/MainWindowTests/MainWindowTabSurfaceTests.swift": 2980,
        "Tests/Unit/MainWindowTests/MainWindowUIIntegrationTests.swift": 959,
        "Tests/Unit/MainWindowTests/PTYDaemonClientSwiftTestingTests.swift": 1135,
        "Tests/Unit/MarkdownTests/MarkdownContentViewTests.swift": 812,
        "Tests/Unit/MemoryTests/MemoryLeakTests.swift": 694,
        "Tests/Unit/NotebookTests/NotebookProcessRunnerSwiftTestingTests.swift": 3671,
        "Tests/Unit/NotificationTests/NotificationManagerTests.swift": 707,
        "Tests/Unit/PerformanceTests/PerformanceTests.swift": 827,
        "Tests/Unit/Phase2AdditionalTests/Phase2EdgeCaseTests.swift": 1148,
        "Tests/Unit/Phase4AdditionalTests/Phase4IntegrationTests.swift": 1041,
        "Tests/Unit/Phase5AdditionalTests/Phase5QATests.swift": 878,
        "Tests/Unit/PluginMarketplaceTests/PluginMarketplaceSwiftTestingTests.swift": 2309,
        "Tests/Unit/PreferencesTests/PreferencesViewModelTests.swift": 754,
        "Tests/Unit/RemoteWorkspaceTests/DaemonScriptTests.swift": 965,
        "Tests/Unit/RemoteWorkspaceTests/HTTPConnectProxyTests.swift": 771,
        "Tests/Unit/RemoteWorkspaceTests/ProxyManagerTests.swift": 1035,
        "Tests/Unit/RemoteWorkspaceTests/ProxyTransportTests.swift": 767,
        "Tests/Unit/RemoteWorkspaceTests/RelayAuthBrokerTests.swift": 889,
        "Tests/Unit/RemoteWorkspaceTests/RelayManagerTests.swift": 853,
        "Tests/Unit/RemoteWorkspaceTests/RemoteConnectionManagerTests.swift": 1476,
        "Tests/Unit/RemoteWorkspaceTests/SFTPClientTests.swift": 3027,
        "Tests/Unit/RemoteWorkspaceTests/SOCKS5ProxyTests.swift": 773,
        "Tests/Unit/RemoteWorkspaceTests/SSHMultiplexerTests.swift": 1627,
        "Tests/Unit/SandboxTests/SandboxFoundationSwiftTestingTests.swift": 605,
        "Tests/Unit/SessionManagerTests/SessionManagerTests.swift": 652,
        "Tests/Unit/SessionRegistryTests/SessionRegistryTests.swift": 697,
        "Tests/Unit/SessionRestorerTests/AppDelegateLazySessionRestoreSwiftTestingTests.swift": 698,
        "Tests/Unit/SessionRestorerTests/SessionRestorerTests.swift": 626,
        "Tests/Unit/SocketServerTests/AppSocketCommandHandlerTests.swift": 4220,
        "Tests/Unit/SocketServerTests/Phase7SecurityTests.swift": 785,
        "Tests/Unit/SocketServerTests/SocketServerTests.swift": 1246,
        "Tests/Unit/SplitNodeTests/SplitNavigationTests.swift": 613,
        "Tests/Unit/SplitNodeTests/SplitNodeTests.swift": 659,
        "Tests/Unit/SyntaxTreeTests/SyntaxTreeDomainSwiftTestingTests.swift": 2491,
        "Tests/Unit/TaskQueueTests/AgentPipelineRuntimeSwiftTestingTests.swift": 625,
        "Tests/Unit/TemplatesTests/ProjectTemplateSwiftTestingTests.swift": 609,
        "Tests/Unit/ThemeTests/Phase6AdditionalTests.swift": 793,
        "Tests/Unit/ThemeTests/ThemeEngineTests.swift": 641,
        "Tests/Unit/ToolbarTests/HorizontalTabStripActionTests.swift": 665,
        "Tests/Unit/VimTests/VimControllerSwiftTestingTests.swift": 2202,
        "Tests/Unit/WorktreeTests/WorktreeServiceTests.swift": 896,
    ]

    @Test("new Swift files stay bounded and oversized files do not grow")
    func sourceLineBudgetsRemainContained() throws {
        let repositoryRoot = Self.repositoryRoot()
        let sourceFiles = try Self.swiftSourceFiles(in: repositoryRoot)
        var violations: [String] = []

        for fileURL in sourceFiles {
            let relativePath = Self.relativePath(for: fileURL, under: repositoryRoot)
            let lineCount = try Self.lineCount(at: fileURL)

            if let existingBudget = Self.existingOversizedFileBudgets[relativePath] {
                if lineCount > existingBudget {
                    violations.append(
                        "\(relativePath) grew from its \(existingBudget)-line budget to \(lineCount)"
                    )
                }
            } else if lineCount > Self.maximumNewFileLines {
                violations.append(
                    "\(relativePath) has \(lineCount) lines; new Swift files are limited to \(Self.maximumNewFileLines)"
                )
            }
        }

        #expect(
            violations.isEmpty,
            Comment(rawValue: violations.sorted().joined(separator: "\n"))
        )
    }

    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func swiftSourceFiles(in repositoryRoot: URL) throws -> [URL] {
        let fileManager = FileManager.default
        var files = [repositoryRoot.appendingPathComponent("Package.swift")]
        let sourceRoots = [
            "CLI",
            "Daemon",
            "QuickLook",
            "Resources",
            "Shared",
            "Sources",
            "Tests",
            "scripts",
        ]

        for sourceRoot in sourceRoots {
            let rootURL = repositoryRoot.appendingPathComponent(sourceRoot, isDirectory: true)
            var enumerationError: Error?
            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                }
            ) else {
                throw CocoaError(.fileReadUnknown)
            }

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if values.isRegularFile == true {
                    files.append(fileURL)
                }
            }
            if let enumerationError {
                throw enumerationError
            }
        }

        return files.sorted { $0.path < $1.path }
    }

    private static func relativePath(for fileURL: URL, under repositoryRoot: URL) -> String {
        let prefix = repositoryRoot.path + "/"
        return String(fileURL.path.dropFirst(prefix.count))
    }

    private static func lineCount(at fileURL: URL) throws -> Int {
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return 0 }
        let newlineCount = data.reduce(into: 0) { count, byte in
            if byte == 0x0A {
                count += 1
            }
        }
        return data.last == 0x0A ? newlineCount : newlineCount + 1
    }
}
