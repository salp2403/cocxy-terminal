// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CocxyShared
import Dispatch
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Privileged socket command authorization")
struct SocketPrivilegedCommandAuthorizationSwiftTestingTests {
    @Test("sensitive command fails closed before its provider when approval is unavailable")
    func missingApprovalFailsClosedBeforeProvider() {
        let sink = LockedFlag()
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            sendTextProvider: { _ in
                sink.setTrue()
                return true
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "privileged-denied",
            command: "send",
            params: ["text": "whoami"]
        ))

        #expect(!response.success)
        #expect(response.error == "This local CLI command requires approval in Cocxy Terminal.")
        #expect(!sink.value)
    }

    @Test("approved command carries the exact intent and reaches its provider once")
    func approvedCommandCarriesExactIntent() {
        let sink = LockedFlag()
        let observed = LockedAuthorizationRequest()
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                observed.set(request)
                return .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            sendTextProvider: { text in
                #expect(text == "printf 'approved'")
                sink.setTrue()
                return true
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "privileged-approved",
            command: "send",
            params: ["text": "printf 'approved'"]
        ))

        #expect(response.success)
        #expect(sink.value)
        #expect(observed.value?.command == .send)
        #expect(observed.value?.category == .terminalInput)
        #expect(observed.value?.params == ["text": "printf 'approved'"])
    }

    @Test("ordinary status remains available without privileged approval")
    func ordinaryStatusDoesNotRequestApproval() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil
        )

        let response = handler.handleCommand(SocketRequest(
            id: "ordinary-status",
            command: "status",
            params: nil
        ))

        #expect(response.success)
    }

    @Test("ordinary agent team list reaches its provider without privileged approval")
    func ordinaryAgentTeamListDoesNotRequireApproval() {
        let providerCalls = LockedCounter()
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            agentTeamCLIProvider: { kind, params in
                providerCalls.increment()
                #expect(kind == "list")
                #expect(params.isEmpty)
                return (true, ["status": "listed", "teams": "0"])
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "ordinary-agent-team-list",
            command: "agent-team-list",
            params: nil
        ))

        #expect(response.success)
        #expect(response.data?["status"] == "listed")
        #expect(providerCalls.value == 1)
    }

    @Test("authorization context fails closed when no privileged session exists")
    func missingExecutionSessionFailsClosed() {
        #expect(!SocketPrivilegedCommandExecutionContext.authorizeCurrentSession())
        #expect(SocketPrivilegedCommandExecutionContext.authorizeCurrentSession(
            allowWithoutSession: true
        ))
    }

    @Test("application policy is exhaustive and matches the shared CLI policy")
    func applicationPolicyMatchesSharedPolicy() {
        for command in CLICommandName.allCases {
            let sharedCategory = CocxyPrivilegedSocketCommandPolicy.category(
                forRawCommand: command.rawValue
            )
            let applicationCategory: SocketPrivilegedCommandCategory?
            switch SocketPrivilegedCommandSecurity.policy(for: command) {
            case .ordinary:
                applicationCategory = nil
            case .privileged(let category):
                applicationCategory = category
            }
            #expect(
                applicationCategory == sharedCategory,
                "Policy mismatch for \(command.rawValue)"
            )
        }
    }

    @Test("approval previews escape invisible controls and bind their digest to parameters")
    func previewEscapesControlsAndDigestBindsParameters() throws {
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "preview",
                command: "browser-eval",
                params: ["script": "line\\path\u{202E}\nnext\u{0007}"]
            )
        ))
        let changed = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "preview-changed",
                command: "browser-eval",
                params: ["script": "different"]
            )
        ))

        let preview = SocketPrivilegedCommandSecurity.approvalPreview(request)
        #expect(preview.contains("line\\\\path\\u{202E}\\n\nnext\\u{0007}"))
        #expect(!preview.contains("\u{202E}"))
        #expect(!preview.contains("\u{0007}"))
        #expect(request.authorizationDigest != changed.authorizationDigest)
    }

    @Test("a grant is exact, expires, and can be consumed only once")
    func grantIsExactExpiringAndOneUse() throws {
        let createdAt = Date()
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "grant",
                command: "send",
                params: ["text": "date"]
            ),
            createdAt: createdAt,
            lifetime: 10
        ))
        let differentRequest = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "grant-other",
                command: "send",
                params: ["text": "id"]
            ),
            createdAt: createdAt,
            lifetime: 10
        ))
        let grant = SocketPrivilegedCommandAuthorizationGrant(
            request: request,
            context: .internalTrusted(for: request),
            issuedAt: createdAt
        )

        #expect(!grant.consume(for: differentRequest, at: createdAt))
        #expect(grant.consume(for: request, at: createdAt))
        #expect(!grant.consume(for: request, at: createdAt))

        let expiredGrant = SocketPrivilegedCommandAuthorizationGrant(
            request: request,
            context: .internalTrusted(for: request),
            issuedAt: createdAt
        )
        #expect(!expiredGrant.consume(for: request, at: request.expiresAt))
    }

    @Test("concurrent authorization requests invoke the provider once")
    func concurrentAuthorizationInvokesProviderOnce() throws {
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "concurrent",
                command: "send",
                params: ["text": "pwd"]
            )
        ))
        let providerCalls = LockedCounter()
        let results = LockedBooleanResults()
        let session = SocketPrivilegedCommandExecutionSession(
            request: request,
            authorizationProvider: { request in
                providerCalls.increment()
                Thread.sleep(forTimeInterval: 0.05)
                return .internalTrusted(for: request)
            }
        )
        let group = DispatchGroup()

        let threads = (0..<8).map { _ in
            Thread {
                results.append(session.authorize())
                group.leave()
            }
        }
        for thread in threads {
            group.enter()
            thread.start()
        }

        #expect(group.wait(timeout: .now() + 5) == .success)
        #expect(providerCalls.value == 1)
        #expect(results.value.count == 8)
        #expect(results.value.allSatisfy { $0 })
    }

    @Test("invalid team, cell, and key requests never open approval")
    func invalidRequestsDoNotRequestApproval() {
        let approvalCalls = LockedCounter()
        let providerCalls = LockedCounter()
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                approvalCalls.increment()
                return .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            browserImportProvider: { _, _ in
                providerCalls.increment()
                return (true, [:])
            },
            sendKeyProvider: { _ in
                providerCalls.increment()
                return true
            },
            agentTeamCLIProvider: { _, _ in
                providerCalls.increment()
                return (true, [:])
            },
            cellCLIProvider: { _, _ in
                providerCalls.increment()
                return (true, [:])
            }
        )

        let requests = [
            SocketRequest(id: "bad-key", command: "send-key", params: ["key": "invalid"]),
            SocketRequest(id: "bad-team", command: "agent-team-launch", params: nil),
            SocketRequest(
                id: "bad-cell",
                command: "cell-exec",
                params: ["cell-id": "not-a-uuid", "argv-json": "[\"pwd\"]"]
            ),
            SocketRequest(
                id: "bad-browser-timeout",
                command: "browser-wait",
                params: ["selector": "#ready", "timeout": "later"]
            ),
            SocketRequest(
                id: "bad-browser-url",
                command: "browser-navigate",
                params: ["url": "http://[::1"]
            ),
            SocketRequest(
                id: "bad-screenshot-path",
                command: "browser-screenshot",
                params: ["output": ""]
            ),
            SocketRequest(
                id: "bad-browser-import-source",
                command: "browser-import-preview",
                params: ["source": "unknown"]
            ),
            SocketRequest(
                id: "bad-browser-import-param",
                command: "browser-import-run",
                params: ["source": "chrome", "source-profile": "Default"]
            ),
            SocketRequest(
                id: "bad-browser-import-path",
                command: "browser-import-run",
                params: ["source": "chrome", "history": ""]
            ),
            SocketRequest(
                id: "bad-browser-import-bool",
                command: "browser-import-run",
                params: ["source": "chrome", "import-history": "yes"]
            ),
            SocketRequest(
                id: "bad-browser-import-days",
                command: "browser-import-preview",
                params: ["source": "chrome", "max-history-days": "-1"]
            ),
        ]

        for request in requests {
            #expect(!handler.handleCommand(request).success)
        }
        #expect(approvalCalls.value == 0)
        #expect(providerCalls.value == 0)
    }

    @Test("local file existence is not disclosed before approval")
    func localFileExistenceIsNotDisclosedBeforeApproval() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil
        )
        let response = handler.handleCommand(SocketRequest(
            id: "notebook-no-approval",
            command: "notebook-run",
            params: ["input": "/tmp/cocxy-definitely-missing/notebook.cocxynb"]
        ))

        #expect(!response.success)
        #expect(response.error == "This local CLI command requires approval in Cocxy Terminal.")
    }

    @Test("local execution uses the canonical paths captured by approval")
    func localExecutionUsesApprovedCanonicalPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-approved-paths-\(UUID().uuidString)", isDirectory: true)
        let approvedInput = root.appendingPathComponent("approved.ipynb")
        let changedInput = root.appendingPathComponent("changed.ipynb")
        let inputLink = root.appendingPathComponent("input.ipynb")
        let output = root.appendingPathComponent("output.cocxynb")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try notebookJSON(marker: "APPROVED-CONTENT").write(
            to: approvedInput,
            atomically: true,
            encoding: .utf8
        )
        try notebookJSON(marker: "CHANGED-CONTENT").write(
            to: changedInput,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(at: inputLink, withDestinationURL: approvedInput)

        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                try? FileManager.default.removeItem(at: inputLink)
                try? FileManager.default.createSymbolicLink(
                    at: inputLink,
                    withDestinationURL: changedInput
                )
                let context = SocketPrivilegedCommandContext(
                    scope: .localExecution,
                    windowControllerIdentifier: nil,
                    tabID: nil,
                    workingDirectory: root.path,
                    localResourcePaths: [
                        "input": approvedInput.path,
                        "output": output.path,
                    ],
                    surfaceID: nil,
                    browserViewModelIdentifier: nil,
                    browserTabID: nil,
                    browserURL: nil,
                    targetDisplayName: inputLink.path
                )
                return SocketPrivilegedCommandAuthorizationGrant(
                    request: request,
                    context: context
                )
            },
            tabManager: nil,
            hookEventReceiver: nil
        )

        let response = handler.handleCommand(SocketRequest(
            id: "notebook-approved-path",
            command: "notebook-import",
            params: [
                "input": inputLink.path,
                "output": output.path,
                "force": "false",
            ]
        ))

        #expect(response.success)
        let rendered = try String(contentsOf: output, encoding: .utf8)
        #expect(rendered.contains("APPROVED-CONTENT"))
        #expect(!rendered.contains("CHANGED-CONTENT"))
    }

    @Test("oversized parameters fail before the authorization presenter")
    func oversizedParametersFailBeforePresenter() {
        let presenter = LockedFlag()
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                presenter.setTrue()
                return .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            sendTextProvider: { _ in true }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "oversized",
            command: "send",
            params: [
                "text": String(
                    repeating: "x",
                    count: SocketPrivilegedCommandSecurity.maxParameterValueBytes + 1
                )
            ]
        ))

        #expect(!response.success)
        #expect(!presenter.value)
    }

    private func notebookJSON(marker: String) -> String {
        """
        {
          "cells": [
            {
              "cell_type": "markdown",
              "metadata": {},
              "source": ["\(marker)"]
            }
          ],
          "metadata": {},
          "nbformat": 4,
          "nbformat_minor": 5
        }
        """
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false

    var value: Bool {
        lock.withLock { stored }
    }

    func setTrue() {
        lock.withLock { stored = true }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0

    var value: Int {
        lock.withLock { stored }
    }

    func increment() {
        lock.withLock { stored += 1 }
    }
}

private final class LockedBooleanResults: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Bool] = []

    var value: [Bool] {
        lock.withLock { stored }
    }

    func append(_ value: Bool) {
        lock.withLock { stored.append(value) }
    }
}

private final class LockedAuthorizationRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SocketPrivilegedCommandAuthorizationRequest?

    var value: SocketPrivilegedCommandAuthorizationRequest? {
        lock.withLock { stored }
    }

    func set(_ request: SocketPrivilegedCommandAuthorizationRequest) {
        lock.withLock { stored = request }
    }
}
