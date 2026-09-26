// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Tab config launch integration", .serialized)
struct TabConfigLaunchIntegrationSwiftTestingTests {
    @Test("socket open of command-bearing config never writes terminal input")
    func socketOpenNeverWritesStartupInput() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let result = fixture.delegate.openTabConfigForCLI(
            named: "api",
            store: fixture.store
        )
        try await Task.sleep(for: .milliseconds(650))

        #expect(result != nil)
        #expect(fixture.engine.sentTexts.isEmpty)
    }

    @Test("visible one-time approval preserves deliberate UI startup behavior")
    func userInterfaceApprovalWritesExactStartupInputOnce() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        var approvedRequest: TabConfigStartupAuthorizationRequest?
        fixture.controller.tabConfigStartupAuthorizationPresenter = { request in
            approvedRequest = request
            guard let surfaceID = fixture.controller.tabSurfaceMap[request.destinationTabID] else {
                return false
            }
            fixture.controller.surfaceWorkingDirectories[surfaceID] = fixture.apiDirectory
            return true
        }

        let result = fixture.delegate.openTabConfigFromUserInterface(
            named: "api",
            store: fixture.store
        )
        try await waitForSentText(in: fixture.engine)
        try await Task.sleep(for: .milliseconds(200))

        #expect(result != nil)
        #expect(approvedRequest?.launchOrigin == .userInterface)
        #expect(fixture.apiDirectory.path != fixture.canonicalAPIDirectory.path)
        #expect(approvedRequest?.workingDirectory == fixture.canonicalAPIDirectory.path)
        #expect(fixture.engine.sentTexts.map(\.text) == ["MODE='test' npm run dev\r"])
    }

    @Test("denied UI approval opens safely without terminal input")
    func deniedUserInterfaceApprovalWritesNothing() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        fixture.controller.tabConfigStartupAuthorizationPresenter = { _ in false }

        let result = fixture.delegate.openTabConfigFromUserInterface(
            named: "api",
            store: fixture.store
        )
        try await Task.sleep(for: .milliseconds(650))

        #expect(result != nil)
        #expect(fixture.engine.sentTexts.isEmpty)
    }

    @Test("stored layout creates real panes, ratios, and terminal directories")
    func storedLayoutMaterializesEndToEnd() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let result = fixture.delegate.openTabConfigForCLI(named: "api", store: fixture.store)
        let tabID = try #require(fixture.controller.tabManager.activeTabID)
        let splitManager = fixture.controller.tabSplitCoordinator.splitManager(for: tabID)
        let requests = Array(
            fixture.engine.createSurfaceRequests.dropFirst(fixture.baselineCreateSurfaceCount)
        )

        #expect(result != nil)
        #expect(requests.map { $0.workingDirectory?.path } == [
            fixture.canonicalAPIDirectory.path,
            fixture.canonicalWorkerDirectory.path,
        ])
        #expect(fixture.controller.tabManager.tab(for: tabID)?.workingDirectory.path
            == fixture.canonicalWorkspace.path)
        #expect(fixture.controller.collectLeafViews().count == 3)

        guard case .split(_, .horizontal, let first, let second, let rootRatio) = splitManager.rootNode,
              case .leaf(_, let primaryContentID) = first,
              case .split(_, .vertical, let markdown, let worker, let nestedRatio) = second,
              case .leaf(_, let markdownContentID) = markdown,
              case .leaf(_, let workerContentID) = worker else {
            Issue.record("The materialized split tree did not preserve the stored topology")
            return
        }
        #expect(abs(rootRatio - 0.62) < 0.000_001)
        #expect(abs(nestedRatio - 0.4) < 0.000_001)
        #expect(splitManager.panelType(for: primaryContentID) == .terminal)
        #expect(splitManager.panelType(for: markdownContentID) == .markdown)
        #expect(splitManager.panelType(for: workerContentID) == .terminal)
        #expect(fixture.controller.panelContentViews[markdownContentID] != nil)
        #expect(fixture.engine.sentTexts.isEmpty)
    }

    @Test("saving a materialized layout captures the same project-relative topology")
    func materializedLayoutRoundTripsThroughSave() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        _ = fixture.delegate.openTabConfigForCLI(named: "api", store: fixture.store)
        let tabID = try #require(fixture.controller.tabManager.activeTabID)
        fixture.controller.tabManager.updateTab(id: tabID) { tab in
            tab.workingDirectory = fixture.apiDirectory
        }

        let saved = fixture.delegate.saveFocusedTabConfigForCLI(
            name: "captured",
            command: nil,
            theme: nil,
            environment: [:],
            store: fixture.store
        )
        let captured = try fixture.store.load(named: "captured")

        #expect(saved != nil)
        #expect(captured.workingDirectory == fixture.canonicalWorkspace.path)
        #expect(captured.layout == fixture.layout)
    }

    @Test("save keeps the config when the visible pane layout cannot be reused")
    func saveFallsBackWithoutLayout() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        _ = fixture.delegate.openTabConfigForCLI(named: "api", store: fixture.store)
        let tabID = try #require(fixture.controller.tabManager.activeTabID)
        let surfaceID = try #require(fixture.controller.tabSurfaceMap[tabID])
        fixture.controller.surfaceWorkingDirectories[surfaceID] = fixture.root

        let saved = fixture.delegate.saveFocusedTabConfigForCLI(
            name: "fallback",
            command: nil,
            theme: nil,
            environment: [:],
            store: fixture.store
        )
        let config = try fixture.store.load(named: "fallback")

        #expect(saved?.warning != nil)
        #expect(config.layout == nil)
        #expect(config.workingDirectory == fixture.canonicalWorkspace.path)
    }

    @Test("save omits a layout containing a remote browser URL")
    func saveOmitsRemoteBrowserLayout() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        _ = fixture.delegate.openTabConfigForCLI(named: "api", store: fixture.store)
        let remoteURL = try #require(URL(string: "https://example.com/dashboard"))
        #expect(fixture.controller.performVisualSplitWithPanel(
            isVertical: false,
            panel: .browser(url: remoteURL)
        ))

        let saved = fixture.delegate.saveFocusedTabConfigForCLI(
            name: "remote-browser",
            command: nil,
            theme: nil,
            environment: [:],
            store: fixture.store
        )
        let config = try fixture.store.load(named: "remote-browser")

        #expect(saved?.warning != nil)
        #expect(config.layout == nil)
        #expect(config.workingDirectory == fixture.canonicalWorkspace.path)
    }

    @Test("save omits a layout containing a live subagent pane")
    func saveOmitsSubagentLayout() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        _ = fixture.delegate.openTabConfigForCLI(named: "api", store: fixture.store)
        fixture.controller.injectedDashboardViewModel = AgentDashboardViewModel()
        #expect(fixture.controller.performVisualSplitWithPanel(
            isVertical: false,
            panel: .subagent(id: "sub-1", sessionId: "session-1")
        ))

        let saved = fixture.delegate.saveFocusedTabConfigForCLI(
            name: "subagent",
            command: nil,
            theme: nil,
            environment: [:],
            store: fixture.store
        )
        let config = try fixture.store.load(named: "subagent")

        #expect(saved?.warning != nil)
        #expect(config.layout == nil)
        #expect(config.workingDirectory == fixture.canonicalWorkspace.path)
    }

    @Test("open fails without creating resources when the project directory is missing")
    func openRejectsMissingProjectDirectory() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let originalTabIDs = Set(fixture.controller.tabManager.tabs.map(\.id))
        let originalSurfaceIDs = Set(fixture.engine.createdSurfaces.keys)
        try FileManager.default.removeItem(at: fixture.workspace)

        let result = fixture.delegate.openTabConfigForCLI(named: "api", store: fixture.store)

        #expect(result == nil)
        #expect(Set(fixture.controller.tabManager.tabs.map(\.id)) == originalTabIDs)
        #expect(Set(fixture.engine.createdSurfaces.keys) == originalSurfaceIDs)
    }

    @Test("open replaces only missing pane resources and reports the degradation")
    func openReplacesMissingPaneResources() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let degradedLayout = TabConfigLayout.split(
            direction: .horizontal,
            ratio: 0.5,
            first: .pane(TabConfigPane(workingDirectory: "api")),
            second: .pane(TabConfigPane(
                type: .markdown,
                filePath: "missing.md",
                title: "Missing"
            ))
        )
        try fixture.store.save(TabConfig(
            name: "degraded",
            workingDirectory: fixture.workspace.path,
            layout: degradedLayout
        ))

        let result = fixture.delegate.openTabConfigForCLI(
            named: "degraded",
            store: fixture.store
        )
        let tabID = try #require(fixture.controller.tabManager.activeTabID)
        let splitManager = fixture.controller.tabSplitCoordinator.splitManager(for: tabID)
        let paneTypes = splitManager.rootNode.allLeafIDs().map {
            splitManager.panelType(for: $0.terminalID)
        }

        #expect(result?.warning != nil)
        #expect(paneTypes == [.terminal, .terminal])
        #expect(fixture.controller.collectLeafViews().count == 2)
    }

    @Test("partial layout creation failure releases every created resource")
    func partialCreationFailureCleansUp() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let originalTabIDs = Set(fixture.controller.tabManager.tabs.map(\.id))
        let originalSurfaceIDs = Set(fixture.engine.createdSurfaces.keys)
        fixture.engine.createSurfaceFailureAfterSuccessCount =
            fixture.baselineCreateSurfaceCount + 1

        let result = fixture.delegate.openTabConfigForCLI(named: "api", store: fixture.store)

        #expect(result == nil)
        #expect(Set(fixture.controller.tabManager.tabs.map(\.id)) == originalTabIDs)
        #expect(Set(fixture.engine.createdSurfaces.keys) == originalSurfaceIDs)
        #expect(fixture.engine.destroyedSurfaces.count == 1)
        #expect(fixture.controller.panelContentViews.isEmpty)
        #expect(fixture.controller.splitSurfaceViews.isEmpty)
    }

    @Test("closing a configured tab releases its app-scoped project context")
    func closingTabReleasesProjectContext() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        _ = fixture.delegate.openTabConfigForCLI(named: "api", store: fixture.store)
        let tabID = try #require(fixture.controller.tabManager.activeTabID)

        #expect(fixture.controller.tabConfigProjectContextStore.projectRoot(for: tabID)?.path
            == fixture.canonicalWorkspace.path)
        fixture.controller.performCloseTab(tabID)
        #expect(fixture.controller.tabConfigProjectContextStore.projectRoot(for: tabID) == nil)
    }

    private func makeFixture() throws -> Fixture {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("cocxy-tab-config-launch-tests")
            .appendingPathComponent(UUID().uuidString)
        let workspace = root.appendingPathComponent("workspace")
        let apiDirectory = workspace.appendingPathComponent("api")
        let workerDirectory = workspace.appendingPathComponent("worker")
        let readme = workspace.appendingPathComponent("README.md")
        try FileManager.default.createDirectory(
            at: apiDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.createDirectory(
            at: workerDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Data("# Project\n".utf8).write(to: readme)
        let store = TabConfigStore(
            rootDirectory: root.appendingPathComponent("configs"),
            socketExportDirectory: root.appendingPathComponent("exports")
        )
        let layout = TabConfigLayout.split(
            direction: .horizontal,
            ratio: 0.62,
            first: .pane(TabConfigPane(
                workingDirectory: "api",
                title: "API"
            )),
            second: .split(
                direction: .vertical,
                ratio: 0.4,
                first: .pane(TabConfigPane(
                    type: .markdown,
                    filePath: "README.md",
                    title: "README"
                )),
                second: .pane(TabConfigPane(
                    workingDirectory: "worker",
                    title: "Worker"
                ))
            )
        )
        try store.save(TabConfig(
            name: "api",
            workingDirectory: workspace.path,
            command: "npm run dev",
            environment: ["MODE": "test"],
            layout: layout
        ))

        let engine = MockTerminalEngine()
        let controller = MainWindowController(bridge: engine)
        let baselineCreateSurfaceCount = engine.createSurfaceRequests.count
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        return Fixture(
            root: root,
            workspace: workspace,
            apiDirectory: apiDirectory,
            workerDirectory: workerDirectory,
            store: store,
            layout: layout,
            baselineCreateSurfaceCount: baselineCreateSurfaceCount,
            engine: engine,
            controller: controller,
            delegate: delegate
        )
    }

    private func waitForSentText(in engine: MockTerminalEngine) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(15))
        while engine.sentTexts.isEmpty, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private struct Fixture {
        let root: URL
        let workspace: URL
        let apiDirectory: URL
        let workerDirectory: URL
        let store: TabConfigStore
        let layout: TabConfigLayout
        let baselineCreateSurfaceCount: Int
        let engine: MockTerminalEngine
        let controller: MainWindowController
        let delegate: AppDelegate

        var canonicalWorkspace: URL {
            ProjectPathCanonicalizer.canonicalURL(workspace)
        }

        var canonicalAPIDirectory: URL {
            ProjectPathCanonicalizer.canonicalURL(apiDirectory)
        }

        var canonicalWorkerDirectory: URL {
            ProjectPathCanonicalizer.canonicalURL(workerDirectory)
        }

        @MainActor
        func cleanup() {
            for tab in controller.tabManager.tabs {
                controller.tabConfigProjectContextStore.removeProjectRoot(for: tab.id)
            }
            controller.window?.orderOut(nil)
            try? FileManager.default.removeItem(at: root)
        }
    }
}
