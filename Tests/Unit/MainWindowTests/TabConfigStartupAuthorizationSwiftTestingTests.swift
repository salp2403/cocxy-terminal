// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Tab config startup authorization")
struct TabConfigStartupAuthorizationSwiftTestingTests {
    @Test("approval is bound to an existing tab and consumed once")
    func approvalIsContextBoundAndSingleUse() {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let directory = URL(fileURLWithPath: "/tmp/cocxy-tab-config-approval")
        let tab = controller.tabManager.addTab(workingDirectory: directory)
        let request = makeRequest(tabID: tab.id, workingDirectory: directory.path)
        var presentationCount = 0
        controller.tabConfigStartupAuthorizationPresenter = { received in
            presentationCount += 1
            return received == request
        }

        #expect(controller.authorizeTabConfigStartup(request))
        #expect(!controller.authorizeTabConfigStartup(request))
        #expect(presentationCount == 1)
    }

    @Test("context changes during approval fail closed")
    func contextChangesDuringApprovalFailClosed() {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let directory = URL(fileURLWithPath: "/tmp/cocxy-tab-config-before")
        let tab = controller.tabManager.addTab(workingDirectory: directory)
        let request = makeRequest(tabID: tab.id, workingDirectory: directory.path)
        controller.tabConfigStartupAuthorizationPresenter = { _ in
            controller.tabManager.updateTab(id: tab.id) {
                $0.workingDirectory = URL(fileURLWithPath: "/tmp/cocxy-tab-config-after")
            }
            return true
        }

        #expect(!controller.authorizeTabConfigStartup(request))
    }

    @Test("expired and unknown-tab requests never reach the presenter")
    func invalidContextNeverReachesPresenter() {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        var presentationCount = 0
        controller.tabConfigStartupAuthorizationPresenter = { _ in
            presentationCount += 1
            return true
        }
        let expired = makeRequest(
            tabID: TabID(),
            workingDirectory: "/tmp/missing",
            expiresAt: Date(timeIntervalSince1970: 0)
        )

        #expect(!controller.authorizeTabConfigStartup(expired))
        #expect(presentationCount == 0)
    }

    @Test("socket-origin authorization objects are rejected even for an existing tab")
    func socketOriginAuthorizationIsRejected() {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let directory = URL(fileURLWithPath: "/tmp/cocxy-tab-config-socket")
        let tab = controller.tabManager.addTab(workingDirectory: directory)
        let request = makeRequest(
            tabID: tab.id,
            workingDirectory: directory.path,
            launchOrigin: .localSocket
        )
        var presentationCount = 0
        controller.tabConfigStartupAuthorizationPresenter = { _ in
            presentationCount += 1
            return true
        }

        #expect(!controller.authorizeTabConfigStartup(request))
        #expect(presentationCount == 0)
    }

    private func makeRequest(
        tabID: TabID,
        workingDirectory: String,
        launchOrigin: TabConfigLaunchOrigin = .userInterface,
        expiresAt: Date = Date().addingTimeInterval(60)
    ) -> TabConfigStartupAuthorizationRequest {
        TabConfigStartupAuthorizationRequest(
            id: UUID(),
            configName: "api",
            sourceDigest: String(repeating: "a", count: 64),
            workingDirectory: workingDirectory,
            destinationTabID: tabID,
            launchOrigin: launchOrigin,
            command: "npm run dev",
            environment: [:],
            startupInput: "npm run dev\r",
            expiresAt: expiresAt
        )
    }
}
