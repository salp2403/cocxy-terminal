// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CocxyShared
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Mobile orchestration lease approval")
@MainActor
struct SocketOrchestrationMobileApprovalSwiftTestingTests {
    @Test("task-run authorization produces a mobile lease and preserves target revalidation")
    func taskRunProducesMobileLease() async throws {
        let fixture = try Self.fixture()
        defer { fixture.controller.close() }
        let registry = MobileMirrorApprovalRegistry()
        let coordinator = SocketPrivilegedCommandAuthorizationCoordinator(
            approvalRegistry: registry
        )
        var grant: SocketPrivilegedCommandAuthorizationGrant?
        var completionCount = 0

        coordinator.requestAuthorization(
            fixture.request,
            targetProvider: { fixture.target },
            completion: {
                grant = $0
                completionCount += 1
            }
        )

        let record = try #require(registry.currentRecords().first)
        #expect(record.kind == .orchestrationLease)
        #expect(record.sessionID == fixture.sessionID.rawValue.uuidString)
        #expect(record.body.contains(String(fixture.request.authorizationDigest.prefix(12))))
        #expect(await registry.resolve(id: record.id, decision: .approve(response: nil)))
        #expect(completionCount == 1)
        #expect(grant?.context == fixture.context)
        #expect(registry.currentRecords().isEmpty)
        #expect(!(await registry.resolve(id: record.id, decision: .approve(response: nil))))
        #expect(completionCount == 1)
    }

    @Test("mobile lease approval fails closed after target drift")
    func taskRunMobileLeaseRejectsTargetDrift() async throws {
        let fixture = try Self.fixture()
        defer { fixture.controller.close() }
        let registry = MobileMirrorApprovalRegistry()
        let coordinator = SocketPrivilegedCommandAuthorizationCoordinator(
            approvalRegistry: registry
        )
        var currentTarget: SocketPrivilegedCommandPresentationTarget? = fixture.target
        var completedGrant: SocketPrivilegedCommandAuthorizationGrant?
        var didComplete = false
        coordinator.requestAuthorization(
            fixture.request,
            targetProvider: { currentTarget },
            completion: {
                completedGrant = $0
                didComplete = true
            }
        )
        let record = try #require(registry.currentRecords().first)
        currentTarget = SocketPrivilegedCommandPresentationTarget(
            context: Self.context(
                controller: fixture.controller,
                tabID: fixture.tabID,
                workingDirectory: "/tmp/mobile-orchestration-drift"
            ),
            controller: fixture.controller
        )

        #expect(!(await registry.resolve(id: record.id, decision: .approve(response: nil))))
        #expect(didComplete)
        #expect(completedGrant == nil)
        #expect(registry.currentRecords().isEmpty)
    }

    private static func fixture() throws -> (
        controller: MainWindowController,
        tabID: TabID,
        sessionID: SessionID,
        request: SocketPrivilegedCommandAuthorizationRequest,
        context: SocketPrivilegedCommandContext,
        target: SocketPrivilegedCommandPresentationTarget
    ) {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        controller.showWindow(nil)
        let tabID = controller.createTab(
            workingDirectory: URL(fileURLWithPath: "/tmp/mobile-orchestration")
        )
        let sessionID = SessionID()
        controller.tabSessionMap[tabID] = sessionID
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "mobile-task-run",
                command: "task-run",
                params: [
                    "prompt": "Review this project",
                    "agents": "codex,claude",
                ]
            ),
            lifetime: 10
        ))
        let context = context(
            controller: controller,
            tabID: tabID,
            workingDirectory: "/tmp/mobile-orchestration"
        )
        return (
            controller,
            tabID,
            sessionID,
            request,
            context,
            SocketPrivilegedCommandPresentationTarget(
                context: context,
                controller: controller
            )
        )
    }

    private static func context(
        controller: MainWindowController,
        tabID: TabID,
        workingDirectory: String
    ) -> SocketPrivilegedCommandContext {
        SocketPrivilegedCommandContext(
            scope: .localExecution,
            windowControllerIdentifier: ObjectIdentifier(controller),
            tabID: tabID.rawValue,
            workingDirectory: workingDirectory,
            authorityDetails: ["operation": "launch"],
            surfaceID: nil,
            browserViewModelIdentifier: nil,
            browserTabID: nil,
            browserURL: nil,
            targetDisplayName: "Parallel task"
        )
    }
}
