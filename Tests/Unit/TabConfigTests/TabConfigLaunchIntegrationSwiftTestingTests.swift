// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Tab config launch integration")
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
        #expect(approvedRequest?.workingDirectory == fixture.workspace.path)
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

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-tab-config-launch-tests")
            .appendingPathComponent(UUID().uuidString)
        let workspace = root.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let store = TabConfigStore(
            rootDirectory: root.appendingPathComponent("configs"),
            socketExportDirectory: root.appendingPathComponent("exports")
        )
        try store.save(TabConfig(
            name: "api",
            workingDirectory: workspace.path,
            command: "npm run dev",
            environment: ["MODE": "test"]
        ))

        let engine = MockTerminalEngine()
        let controller = MainWindowController(bridge: engine)
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        return Fixture(
            root: root,
            workspace: workspace,
            store: store,
            engine: engine,
            controller: controller,
            delegate: delegate
        )
    }

    private func waitForSentText(in engine: MockTerminalEngine) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while engine.sentTexts.isEmpty, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private struct Fixture {
        let root: URL
        let workspace: URL
        let store: TabConfigStore
        let engine: MockTerminalEngine
        let controller: MainWindowController
        let delegate: AppDelegate

        @MainActor
        func cleanup() {
            controller.window?.orderOut(nil)
            try? FileManager.default.removeItem(at: root)
        }
    }
}
