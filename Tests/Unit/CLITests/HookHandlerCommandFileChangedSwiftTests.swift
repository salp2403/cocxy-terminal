// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HookHandlerCommandFileChangedSwiftTests.swift
// Verifies the hook handler builds valid CLI requests for the new
// CwdChanged and FileChanged events and respects the environment guard.

import Foundation
import Testing
@testable import CocxyCLILib

@Suite("Hook handler payload building (CwdChanged / FileChanged)")
struct HookHandlerCommandFileChangedSwiftTests {

    private static let cocxyEnv: [String: String] = [
        "COCXY_CLAUDE_HOOKS": "1"
    ]

    @Test("CwdChanged payload yields a hook-event request with all fields preserved")
    func cwdChangedRequestPreservesPayload() throws {
        let raw = #"""
        {
            "hook_event_name": "CwdChanged",
            "session_id": "sess-cwd-handler-001",
            "cwd": "/Users/dev/project/sub",
            "previous_cwd": "/Users/dev/project"
        }
        """#

        let request = try HookHandlerCommand.buildRequest(
            from: Data(raw.utf8),
            environment: Self.cocxyEnv
        )

        #expect(request.command == "hook-event")
        let payload = try requirePayload(from: request)
        #expect(payload["hook_event_name"] as? String == "CwdChanged")
        #expect(payload["session_id"] as? String == "sess-cwd-handler-001")
        #expect(payload["cwd"] as? String == "/Users/dev/project/sub")
        #expect(payload["previous_cwd"] as? String == "/Users/dev/project")
    }

    @Test("FileChanged payload yields a hook-event request with all fields preserved")
    func fileChangedRequestPreservesPayload() throws {
        let raw = #"""
        {
            "hook_event_name": "FileChanged",
            "session_id": "sess-file-handler-001",
            "cwd": "/Users/dev/project",
            "file_path": "/Users/dev/project/src/main.swift",
            "change_type": "edit"
        }
        """#

        let request = try HookHandlerCommand.buildRequest(
            from: Data(raw.utf8),
            environment: Self.cocxyEnv
        )

        let payload = try requirePayload(from: request)
        #expect(payload["hook_event_name"] as? String == "FileChanged")
        #expect(payload["file_path"] as? String == "/Users/dev/project/src/main.swift")
        #expect(payload["change_type"] as? String == "edit")
    }

    @Test("Empty stdin still throws emptyInput, regardless of event name")
    func emptyInputRejected() {
        #expect(throws: HooksError.self) {
            _ = try HookHandlerCommand.buildRequest(
                from: Data(),
                environment: Self.cocxyEnv
            )
        }
    }

    @Test("Guard rejects events from non-Cocxy shells without COCXY_CLAUDE_HOOKS")
    func guardDropsEventsOutsideCocxyShell() {
        let allowed = HookHandlerCommand.shouldForwardHook(environment: Self.cocxyEnv)
        let blocked = HookHandlerCommand.shouldForwardHook(environment: [:])
        #expect(allowed)
        #expect(!blocked)
    }

    // MARK: - Helpers

    private func requirePayload(from request: CLISocketRequest) throws -> [String: Any] {
        guard let payloadString = request.params?["payload"],
              let data = payloadString.data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            Issue.record("Missing or unparsable payload in CLISocketRequest")
            throw HooksError.invalidHookJSON(reason: "missing payload")
        }
        return payload
    }
}
