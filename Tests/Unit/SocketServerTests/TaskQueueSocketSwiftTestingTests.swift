// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Task queue socket bridge")
struct TaskQueueSocketSwiftTestingTests {
    @Test("list is paginated and remains read-only")
    func listDoesNotRequireApproval() {
        let approvals = TaskQueueLockedCounter()
        let providerCalls = TaskQueueLockedCounter()
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                approvals.increment()
                return .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            taskQueueCLIProvider: { kind, params in
                providerCalls.increment()
                #expect(kind == "list")
                #expect(params == ["limit": "25", "offset": "50"])
                return (true, ["status": "listed", "total": "0", "returned": "0"])
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "task-list",
            command: "task-list",
            params: ["limit": "25", "offset": "50"]
        ))

        #expect(response.success)
        #expect(providerCalls.value == 1)
        #expect(approvals.value == 0)
    }

    @Test("invalid enqueue is rejected before approval and provider work")
    func invalidEnqueuePrecedesApproval() {
        let approvals = TaskQueueLockedCounter()
        let providerCalls = TaskQueueLockedCounter()
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                approvals.increment()
                return .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            taskQueueCLIProvider: { _, _ in
                providerCalls.increment()
                return (true, [:])
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "task-enqueue-invalid",
            command: "task-enqueue",
            params: [
                "task-id": "ambiguous",
                "input": "/tmp/pipeline.json",
                "prompt": "Review",
                "cwd": "/tmp/project",
                "trigger": "manual",
            ]
        ))

        #expect(!response.success)
        #expect(response.error == "Use exactly one pipeline input or inline prompt")
        #expect(providerCalls.value == 0)
        #expect(approvals.value == 0)
    }

    @Test("approved enqueue carries its exact bounded parameters once")
    func approvedEnqueueCarriesExactParams() {
        let approvals = TaskQueueLockedCounter()
        let providerCalls = TaskQueueLockedCounter()
        let expected = [
            "task-id": "nightly-review",
            "provider": "codex",
            "prompt": "Review and test",
            "cwd": "/tmp/project",
            "project": "/tmp/project",
            "trigger": "cron",
            "cron": "0 2 * * *",
            "timezone": "UTC",
            "retries": "2",
            "concurrency": "3",
        ]
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                approvals.increment()
                #expect(request.command == .taskEnqueue)
                #expect(request.category == .localExecution)
                #expect(request.params == expected)
                return .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            taskQueueCLIProvider: { kind, params in
                providerCalls.increment()
                #expect(kind == "enqueue")
                #expect(params == expected)
                return (true, ["status": "enqueued", "task-id": "nightly-review"])
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "task-enqueue-approved",
            command: "task-enqueue",
            params: expected
        ))

        #expect(response.success)
        #expect(providerCalls.value == 1)
        #expect(approvals.value == 1)
    }

    @Test("enqueue rejects a relative project before requesting approval")
    func enqueueRejectsRelativeProject() {
        for project in [
            "relative/project",
            "/tmp/project\0swapped",
            "/" + String(repeating: "p", count: AgentPipelineStep.maximumWorktreePathBytes),
        ] {
            let approvals = TaskQueueLockedCounter()
            let providerCalls = TaskQueueLockedCounter()
            let handler = AppSocketCommandHandler(
                privilegedCommandAuthorizationProvider: { request in
                    approvals.increment()
                    return .internalTrusted(for: request)
                },
                tabManager: nil,
                hookEventReceiver: nil,
                taskQueueCLIProvider: { _, _ in
                    providerCalls.increment()
                    return (true, [:])
                }
            )

            let response = handler.handleCommand(SocketRequest(
                id: "task-enqueue-invalid-project",
                command: "task-enqueue",
                params: [
                    "task-id": "review",
                    "provider": "codex",
                    "prompt": "Review",
                    "cwd": "/tmp/project",
                    "project": project,
                    "trigger": "manual",
                ]
            ))

            #expect(!response.success)
            #expect(approvals.value == 0)
            #expect(providerCalls.value == 0)
        }
    }

    @Test("only emitted plugin events can trigger queued tasks")
    func unavailableEventsAreRejectedAsTriggers() {
        for event in [
            "agent-detected",
            "agent-state-changed",
            "command-complete",
            "directory-changed",
            "task-run-started",
            "task-run-finished",
        ] {
            let approvals = TaskQueueLockedCounter()
            let providerCalls = TaskQueueLockedCounter()
            let handler = AppSocketCommandHandler(
                privilegedCommandAuthorizationProvider: { request in
                    approvals.increment()
                    return .internalTrusted(for: request)
                },
                tabManager: nil,
                hookEventReceiver: nil,
                taskQueueCLIProvider: { _, _ in
                    providerCalls.increment()
                    return (true, [:])
                }
            )

            let response = handler.handleCommand(SocketRequest(
                id: "task-enqueue-\(event)",
                command: "task-enqueue",
                params: [
                    "task-id": "dead-event",
                    "provider": "codex",
                    "prompt": "Do not run",
                    "cwd": "/tmp/project",
                    "trigger": "on-event",
                    "event": event,
                ]
            ))

            #expect(!response.success)
            #expect(providerCalls.value == 0)
            #expect(approvals.value == 0)
        }
    }

    @Test("task mutations require approval and preserve the exact identifier")
    func taskMutationsRequireApproval() {
        for (command, expectedCommand, kind) in [
            ("task-cancel", CLICommandName.taskCancel, "cancel"),
            ("task-rerun", .taskRerun, "rerun"),
            ("task-remove", .taskRemove, "remove"),
        ] {
            let approvals = TaskQueueLockedCounter()
            let providerCalls = TaskQueueLockedCounter()
            let handler = AppSocketCommandHandler(
                privilegedCommandAuthorizationProvider: { request in
                    approvals.increment()
                    #expect(request.command == expectedCommand)
                    #expect(request.params == ["task-id": "nightly-review"])
                    return .internalTrusted(for: request)
                },
                tabManager: nil,
                hookEventReceiver: nil,
                taskQueueCLIProvider: { receivedKind, params in
                    providerCalls.increment()
                    #expect(receivedKind == kind)
                    #expect(params == ["task-id": "nightly-review"])
                    return (true, ["status": kind, "task-id": "nightly-review"])
                }
            )

            let response = handler.handleCommand(SocketRequest(
                id: "\(command)-approved",
                command: command,
                params: ["task-id": "nightly-review"]
            ))

            #expect(response.success)
            #expect(providerCalls.value == 1)
            #expect(approvals.value == 1)
        }
    }
}

private final class TaskQueueLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func increment() {
        lock.lock()
        storedValue += 1
        lock.unlock()
    }
}
