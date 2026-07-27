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
            authorityDetails: [
                "operation": "pr-draft",
                "provider": "openai",
                "repository": "/tmp/project",
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
        #expect(preview.contains("authority.operation: pr-draft"))
        #expect(preview.contains("authority.provider: openai"))
        #expect(preview.contains("authority.repository: /tmp/project"))
    }

    @Test("cell cloud-init reads and binds bytes only after approval")
    func cellCloudInitApprovalBindsPathAndDigest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-cell-approval-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let source = root.appendingPathComponent("cloud-init.yml")
        let data = Data("#cloud-config\nruncmd:\n  - echo ready\n".utf8)
        try data.write(to: source)

        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "cell-cloud-init",
                command: "cell-create",
                params: [
                    "provider": "gcp",
                    "project": "project-a",
                    "zone": "us-central1-a",
                    "cloud-init": source.path,
                ]
            )
        ))

        let presentedTarget = try #require(
            delegate.privilegedSocketCommandPresentationTarget(for: request)
        )
        let canonicalPath = source.resolvingSymlinksInPath().standardizedFileURL.path
        let expectedDigest = SocketPrivilegedCommandSecurity.digest(data: data)
        let coordinator = SocketPrivilegedCommandAuthorizationCoordinator()
        var grant: SocketPrivilegedCommandAuthorizationGrant?
        coordinator.presenter = { _, context in
            #expect(context.localResourceDigests["cloud-init"] == nil)
            return true
        }
        coordinator.requestAuthorization(
            request,
            targetProvider: {
                delegate.privilegedSocketCommandPresentationTarget(for: request)
            },
            completion: { grant = $0 }
        )

        #expect(presentedTarget.context.scope == .computeCell)
        #expect(presentedTarget.context.localResourcePaths["cloud-init"] == canonicalPath)
        #expect(presentedTarget.context.localResourceDigests["cloud-init"] == nil)
        #expect(presentedTarget.context.authorityDetails["cloud-init-bytes"] == "\(data.count)")
        #expect(grant?.context.localResourceDigests["cloud-init"] == expectedDigest)
    }

    @Test("denied approval never resolves post-approval resources")
    func deniedApprovalSkipsApprovedContextProvider() throws {
        let fixture = makeFixture()
        let request = try makeGitAssistantRequest()
        let coordinator = SocketPrivilegedCommandAuthorizationCoordinator()
        var approvedContextCalls = 0
        var grant: SocketPrivilegedCommandAuthorizationGrant?
        let target = SocketPrivilegedCommandPresentationTarget(
            context: fixture.context,
            controller: fixture.controller,
            approvedContextProvider: {
                approvedContextCalls += 1
                return fixture.context
            }
        )
        coordinator.presenter = { _, _ in false }

        coordinator.requestAuthorization(
            request,
            targetProvider: { target },
            completion: { grant = $0 }
        )

        #expect(grant == nil)
        #expect(approvedContextCalls == 0)
    }

    @Test("missing post-approval resources fail closed")
    func missingApprovedContextFailsClosed() throws {
        let fixture = makeFixture()
        let request = try makeGitAssistantRequest()
        let coordinator = SocketPrivilegedCommandAuthorizationCoordinator()
        var grant: SocketPrivilegedCommandAuthorizationGrant?
        let target = SocketPrivilegedCommandPresentationTarget(
            context: fixture.context,
            controller: fixture.controller,
            approvedContextProvider: { nil }
        )
        coordinator.presenter = { _, _ in true }

        coordinator.requestAuthorization(
            request,
            targetProvider: { target },
            completion: { grant = $0 }
        )

        #expect(grant == nil)
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
