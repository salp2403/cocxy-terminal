// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Privileged socket command native approval")
struct MainWindowSocketPrivilegedCommandAuthorizationSwiftTestingTests {
    @Test("specialized browser approval can resolve the active model without a generic grant")
    func specializedBrowserApprovalResolvesActiveModel() {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let viewModel = BrowserViewModel()
        controller.browserViewModel = viewModel
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)

        #expect(delegate.socketBrowserViewModel(for: nil) === viewModel)
    }

    @Test("approval is one-use and bound to the presented context")
    func approvalIsOneUseAndContextBound() throws {
        let fixture = makeFixture()
        let request = try makeGitAssistantRequest()
        let coordinator = SocketPrivilegedCommandAuthorizationCoordinator()
        var presentationCount = 0
        var firstGrant: SocketPrivilegedCommandAuthorizationGrant?
        var secondGrant: SocketPrivilegedCommandAuthorizationGrant?
        coordinator.presenter = { received, context in
            presentationCount += 1
            return received == request
                && context.tabID == fixture.tabID.rawValue
                && context.workingDirectory == fixture.directory.path
        }

        coordinator.requestAuthorization(
            request,
            targetProvider: { fixture.target },
            completion: { firstGrant = $0 }
        )
        coordinator.requestAuthorization(
            request,
            targetProvider: { fixture.target },
            completion: { secondGrant = $0 }
        )

        #expect(firstGrant?.requestID == request.id)
        #expect(firstGrant?.context == fixture.context)
        #expect(secondGrant == nil)
        #expect(presentationCount == 1)
    }

    @Test("changing the target during approval fails closed")
    func changedContextFailsClosed() throws {
        let fixture = makeFixture()
        let request = try makeGitAssistantRequest()
        let coordinator = SocketPrivilegedCommandAuthorizationCoordinator()
        var context = fixture.context
        var grant: SocketPrivilegedCommandAuthorizationGrant?
        coordinator.presenter = { _, _ in
            context = SocketPrivilegedCommandContext(
                scope: .repository,
                windowControllerIdentifier: ObjectIdentifier(fixture.controller),
                tabID: fixture.tabID.rawValue,
                workingDirectory: "/tmp/cocxy-privileged-after",
                surfaceID: nil,
                browserViewModelIdentifier: nil,
                browserTabID: nil,
                browserURL: nil,
                targetDisplayName: "/tmp/cocxy-privileged-after"
            )
            return true
        }

        coordinator.requestAuthorization(
            request,
            targetProvider: {
                SocketPrivilegedCommandPresentationTarget(
                    context: context,
                    controller: fixture.controller
                )
            },
            completion: { grant = $0 }
        )

        #expect(grant == nil)
    }

    @Test("expired authorization never reaches the presenter")
    func expiredRequestNeverReachesPresenter() throws {
        let fixture = makeFixture()
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "expired",
                command: "git-assistant-commit-message",
                params: nil
            ),
            createdAt: Date(timeIntervalSince1970: 0),
            lifetime: 1
        ))
        let coordinator = SocketPrivilegedCommandAuthorizationCoordinator()
        var presentationCount = 0
        var grant: SocketPrivilegedCommandAuthorizationGrant?
        coordinator.presenter = { _, _ in
            presentationCount += 1
            return true
        }

        coordinator.requestAuthorization(
            request,
            targetProvider: { fixture.target },
            completion: { grant = $0 }
        )

        #expect(grant == nil)
        #expect(presentationCount == 0)
    }

    @Test("a reentrant approval request is rejected while another is active")
    func reentrantApprovalIsRejected() throws {
        let fixture = makeFixture()
        let firstRequest = try makeGitAssistantRequest()
        let secondRequest = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "second",
                command: "git-assistant-pr-draft",
                params: ["base": "main"]
            )
        ))
        let coordinator = SocketPrivilegedCommandAuthorizationCoordinator()
        var presentationCount = 0
        var firstGrant: SocketPrivilegedCommandAuthorizationGrant?
        var secondGrant: SocketPrivilegedCommandAuthorizationGrant?
        coordinator.presenter = { _, _ in
            presentationCount += 1
            coordinator.requestAuthorization(
                secondRequest,
                targetProvider: { fixture.target },
                completion: { secondGrant = $0 }
            )
            return true
        }

        coordinator.requestAuthorization(
            firstRequest,
            targetProvider: { fixture.target },
            completion: { firstGrant = $0 }
        )

        #expect(firstGrant != nil)
        #expect(secondGrant == nil)
        #expect(presentationCount == 1)
    }

    @Test("approval preview exposes resolved profile and local paths")
    func approvalPreviewIncludesResolvedAuthority() throws {
        let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "browser-import-preview",
                command: "browser-import-preview",
                params: ["source": "chrome"]
            )
        ))
        let context = SocketPrivilegedCommandContext(
            scope: .browserGlobal,
            windowControllerIdentifier: nil,
            tabID: nil,
            workingDirectory: "Cocxy application",
            localResourcePaths: [
                "browser-import.0.history": "/Users/test/Library/Application Support/Browser/History",
            ],
            localResourceDigests: [
                "browser-import.0.history": String(repeating: "a", count: 64),
            ],
            surfaceID: nil,
            browserViewModelIdentifier: nil,
            browserTabID: nil,
            browserURL: nil,
            browserProfileID: profileID,
            targetDisplayName: "Import Chrome into Default (1 location)"
        )

        let preview = MainWindowController.privilegedSocketCommandApprovalPreview(
            request: request,
            context: context
        )

        #expect(preview.contains("Resolved authority:"))
        #expect(preview.contains("browser-profile: \(profileID.uuidString)"))
        #expect(preview.contains("browser-import.0.history"))
        #expect(preview.contains("/Users/test/Library/Application Support/Browser/History"))
        #expect(preview.contains("browser-import.0.history-sha256"))
        #expect(preview.contains(String(repeating: "a", count: 64)))
    }

    private func makeFixture() -> (
        controller: MainWindowController,
        tabID: TabID,
        directory: URL,
        context: SocketPrivilegedCommandContext,
        target: SocketPrivilegedCommandPresentationTarget
    ) {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let directory = URL(fileURLWithPath: "/tmp/cocxy-privileged-approval")
        let tab = controller.tabManager.addTab(workingDirectory: directory)
        let context = SocketPrivilegedCommandContext(
            scope: .repository,
            windowControllerIdentifier: ObjectIdentifier(controller),
            tabID: tab.id.rawValue,
            workingDirectory: directory.path,
            surfaceID: nil,
            browserViewModelIdentifier: nil,
            browserTabID: nil,
            browserURL: nil,
            targetDisplayName: directory.path
        )
        return (
            controller,
            tab.id,
            directory,
            context,
            SocketPrivilegedCommandPresentationTarget(
                context: context,
                controller: controller
            )
        )
    }

    private func makeGitAssistantRequest() throws -> SocketPrivilegedCommandAuthorizationRequest {
        try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "git-assistant",
                command: "git-assistant-commit-message",
                params: nil
            )
        ))
    }
}
