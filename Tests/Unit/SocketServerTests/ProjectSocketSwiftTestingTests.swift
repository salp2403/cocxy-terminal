// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Project socket bridge")
struct ProjectSocketSwiftTestingTests {
    @Test("project-open requires one approval and reaches its provider once")
    func openRequiresApproval() {
        let approvals = ProjectSocketCounter()
        let providerCalls = ProjectSocketCounter()
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                approvals.increment()
                #expect(request.command == .projectOpen)
                #expect(request.category == .project)
                #expect(request.params == ["path": "/tmp/repo"])
                return .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            projectCLIProvider: { kind, params in
                providerCalls.increment()
                #expect(kind == "open")
                #expect(params == ["path": "/tmp/repo"])
                return (true, ["status": "opened", "path": "/tmp/repo"])
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "project-open",
            command: "project-open",
            params: ["path": "/tmp/repo"]
        ))

        #expect(response.success)
        #expect(approvals.value == 1)
        #expect(providerCalls.value == 1)
    }

    @Test("project-open denial and invalid input stop before provider work")
    func openFailsClosed() {
        let providerCalls = ProjectSocketCounter()
        let denied = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            projectCLIProvider: { _, _ in
                providerCalls.increment()
                return (true, [:])
            }
        ).handleCommand(SocketRequest(
            id: "denied",
            command: "project-open",
            params: ["path": "/tmp/repo"]
        ))
        #expect(!denied.success)
        #expect(providerCalls.value == 0)

        let approvalCalls = ProjectSocketCounter()
        let invalid = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                approvalCalls.increment()
                return .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            projectCLIProvider: { _, _ in
                providerCalls.increment()
                return (true, [:])
            }
        ).handleCommand(SocketRequest(
            id: "invalid",
            command: "project-open",
            params: nil
        ))
        #expect(!invalid.success)
        #expect(invalid.error == "Missing required param: path")
        #expect(approvalCalls.value == 0)
        #expect(providerCalls.value == 0)
    }

    @Test("project-clone requires one approval and reaches its provider once")
    func cloneRequiresApproval() {
        let approvals = ProjectSocketCounter()
        let providerCalls = ProjectSocketCounter()
        let params = [
            "remote": "https://example.com/team/repo.git",
            "parent": "/tmp",
        ]
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                approvals.increment()
                #expect(request.command == .projectClone)
                #expect(request.category == .project)
                #expect(request.params == params)
                return .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            projectCLIProvider: { kind, receivedParams in
                providerCalls.increment()
                #expect(kind == "clone")
                #expect(receivedParams == params)
                return (true, ["status": "cloned", "path": "/tmp/repo"])
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "project-clone",
            command: "project-clone",
            params: params
        ))

        #expect(response.success)
        #expect(approvals.value == 1)
        #expect(providerCalls.value == 1)
    }

    @Test("project-clone denial and invalid input stop before provider work")
    func cloneFailsClosed() {
        let providerCalls = ProjectSocketCounter()
        let params = [
            "remote": "https://example.com/team/repo.git",
            "parent": "/tmp",
        ]
        let denied = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            projectCLIProvider: { _, _ in
                providerCalls.increment()
                return (true, [:])
            }
        ).handleCommand(SocketRequest(
            id: "clone-denied",
            command: "project-clone",
            params: params
        ))
        #expect(!denied.success)
        #expect(providerCalls.value == 0)

        let approvalCalls = ProjectSocketCounter()
        let invalid = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                approvalCalls.increment()
                return .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            projectCLIProvider: { _, _ in
                providerCalls.increment()
                return (true, [:])
            }
        ).handleCommand(SocketRequest(
            id: "clone-invalid",
            command: "project-clone",
            params: ["remote": "file:///tmp/repo", "parent": "/tmp"]
        ))
        #expect(!invalid.success)
        #expect(approvalCalls.value == 0)
        #expect(providerCalls.value == 0)
    }

    @Test("six ordinary project commands route without approval")
    func ordinaryCommandsDoNotRequestApproval() {
        let approvals = ProjectSocketCounter()
        let providerCalls = ProjectSocketCounter()
        let cases: [(String, [String: String]?)] = [
            ("project-list", nil),
            ("project-pin", ["project": "/tmp/repo"]),
            ("project-unpin", ["project": "/tmp/repo"]),
            ("project-alias", ["project": "/tmp/repo", "alias": "API"]),
            ("project-forget", ["project": "/tmp/repo"]),
            ("project-tasks", ["project": "/tmp/repo"]),
        ]
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                approvals.increment()
                return .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            projectCLIProvider: { _, _ in
                providerCalls.increment()
                return (true, ["status": "ok"])
            }
        )

        for (command, params) in cases {
            let response = handler.handleCommand(SocketRequest(
                id: command,
                command: command,
                params: params
            ))
            #expect(response.success, "Expected \(command) to route")
        }
        #expect(approvals.value == 0)
        #expect(providerCalls.value == cases.count)
    }

    @Test("project handler rejects unsupported parameters before provider work")
    func parametersFailClosed() {
        let providerCalls = ProjectSocketCounter()
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            projectCLIProvider: { _, _ in
                providerCalls.increment()
                return (true, [:])
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "list-extra",
            command: "project-list",
            params: ["path": "/tmp/repo"]
        ))
        #expect(!response.success)
        #expect(response.error == "Unsupported parameter for project list: path")
        #expect(providerCalls.value == 0)
    }
}

private final class ProjectSocketCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
