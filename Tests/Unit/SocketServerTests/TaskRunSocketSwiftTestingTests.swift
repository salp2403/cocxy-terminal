// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("TaskRun socket bridge")
struct TaskRunSocketSwiftTestingTests {
    @Test("list remains read-only and reaches its provider without approval")
    func listDoesNotRequireApproval() {
        let approvalCalls = TaskRunLockedCounter()
        let providerCalls = TaskRunLockedCounter()
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                approvalCalls.increment()
                return .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            taskRunCLIProvider: { kind, params in
                providerCalls.increment()
                #expect(kind == "list")
                #expect(params.isEmpty)
                return (true, ["status": "listed", "count": "0", "runs": "[]"])
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "task-run-list",
            command: "task-run-list",
            params: nil
        ))

        #expect(response.success)
        #expect(providerCalls.value == 1)
        #expect(approvalCalls.value == 0)
    }

    @Test("invalid launch is rejected before approval or provider work")
    func invalidLaunchPrecedesApproval() {
        let approvalCalls = TaskRunLockedCounter()
        let providerCalls = TaskRunLockedCounter()
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                approvalCalls.increment()
                return .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            taskRunCLIProvider: { _, _ in
                providerCalls.increment()
                return (true, [:])
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "task-run-invalid",
            command: "task-run",
            params: [
                "prompt": "Compare",
                "agents": "codex,claude",
                "count": "9",
            ]
        ))

        #expect(!response.success)
        #expect(response.error == "Task candidate count cannot exceed 8")
        #expect(providerCalls.value == 0)
        #expect(approvalCalls.value == 0)
    }

    @Test("approved launch carries exact params to the provider once")
    func approvedLaunchCarriesExactParams() {
        let approvalCalls = TaskRunLockedCounter()
        let providerCalls = TaskRunLockedCounter()
        let expected = [
            "prompt": "Implement and verify",
            "agents": "claude,codex",
            "count": "3",
            "base-ref": "main",
        ]
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                approvalCalls.increment()
                #expect(request.command == .taskRun)
                #expect(request.category == .localExecution)
                #expect(request.params == expected)
                return .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            taskRunCLIProvider: { kind, params in
                providerCalls.increment()
                #expect(kind == "launch")
                #expect(params == expected)
                return (true, ["status": "launched", "run-id": "task-1"])
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "task-run-approved",
            command: "task-run",
            params: expected
        ))

        #expect(response.success)
        #expect(providerCalls.value == 1)
        #expect(approvalCalls.value == 1)
    }

    @Test("promotion requires approval and validates both identifiers")
    func promotionRequiresApprovalAndIdentifiers() {
        let providerCalls = TaskRunLockedCounter()
        let deniedHandler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            taskRunCLIProvider: { _, _ in
                providerCalls.increment()
                return (true, [:])
            }
        )
        let denied = deniedHandler.handleCommand(SocketRequest(
            id: "task-run-promote-denied",
            command: "task-run-promote",
            params: [
                "run-id": "task-1",
                "candidate-id": "task-1-candidate-1",
            ]
        ))
        #expect(!denied.success)
        #expect(providerCalls.value == 0)

        let approvalCalls = TaskRunLockedCounter()
        let invalidHandler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                approvalCalls.increment()
                return .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            taskRunCLIProvider: { _, _ in
                providerCalls.increment()
                return (true, [:])
            }
        )
        let invalid = invalidHandler.handleCommand(SocketRequest(
            id: "task-run-promote-invalid",
            command: "task-run-promote",
            params: ["run-id": "task-1"]
        ))
        #expect(!invalid.success)
        #expect(approvalCalls.value == 0)
        #expect(providerCalls.value == 0)
    }

    @Test("approved promotion carries both bound identifiers to the provider")
    func approvedPromotionCarriesBoundIdentifiers() {
        let approvalCalls = TaskRunLockedCounter()
        let providerCalls = TaskRunLockedCounter()
        let expected = [
            "run-id": "task-1",
            "candidate-id": "task-1-candidate-2",
        ]
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                approvalCalls.increment()
                #expect(request.command == .taskRunPromote)
                #expect(request.category == .localExecution)
                #expect(request.params == expected)
                return .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            taskRunCLIProvider: { kind, params in
                providerCalls.increment()
                #expect(kind == "promote")
                #expect(params == expected)
                return (true, [
                    "status": "promoted",
                    "run-id": "task-1",
                    "candidate-id": "task-1-candidate-2",
                ])
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "task-run-promote-approved",
            command: "task-run-promote",
            params: expected
        ))

        #expect(response.success)
        #expect(providerCalls.value == 1)
        #expect(approvalCalls.value == 1)
    }
}

private final class TaskRunLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func increment() {
        lock.lock()
        stored += 1
        lock.unlock()
    }
}
