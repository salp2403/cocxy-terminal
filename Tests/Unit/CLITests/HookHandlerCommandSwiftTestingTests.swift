// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyCLILib

@Suite("Hook handler forwarding")
struct HookHandlerCommandSwiftTestingTests {

    @Test("forwarding only runs inside Cocxy shells")
    func forwardingOnlyRunsInsideCocxyShell() {
        #expect(HookHandlerCommand.shouldForwardHook(environment: [
            "COCXY_CLAUDE_HOOKS": "1"
        ]))
        #expect(HookHandlerCommand.shouldForwardHook(environment: [
            "COCXY_RESOURCES_DIR": "/tmp/cocxy"
        ]))
        #expect(HookHandlerCommand.shouldForwardHook(environment: [
            "COCXY_SHELL_INTEGRATION_DIR": "/tmp/cocxy/shell-integration"
        ]))
        #expect(HookHandlerCommand.shouldForwardHook(environment: [
            "COCXY_RESOURCES_DIR": "/tmp/cocxy",
            "COCXY_SHELL_INTEGRATION_DIR": "/tmp/cocxy/shell-integration"
        ]))
        #expect(!HookHandlerCommand.shouldForwardHook(environment: [:]))
        #expect(!HookHandlerCommand.shouldForwardHook(environment: [
            "TERM_PROGRAM": "Apple_Terminal"
        ]))
    }

    @Test("forwarding honors global and per-agent disable variables")
    func forwardingHonorsHookDisableVariables() {
        #expect(!HookHandlerCommand.shouldForwardHook(environment: [
            "COCXY_CLAUDE_HOOKS": "1",
            "COCXY_HOOKS_DISABLED": "1"
        ]))
        #expect(!HookHandlerCommand.shouldForwardHook(environment: [
            "COCXY_CLAUDE_HOOKS": "1",
            "CLAUDE_CODE_SESSION_ID": "claude-session",
            "COCXY_CLAUDE_HOOKS_DISABLED": "1"
        ]))
        #expect(!HookHandlerCommand.shouldForwardHook(environment: [
            "COCXY_CLAUDE_HOOKS": "1",
            "PI_SESSION_ID": "pi-session",
            "COCXY_PI_HOOKS_DISABLED": "1"
        ]))
        #expect(!HookHandlerCommand.shouldForwardHook(environment: [
            "COCXY_CLAUDE_HOOKS": "1",
            "ROVODEV_SESSION_ID": "rovo-session",
            "COCXY_ROVODEV_HOOKS_DISABLED": "1"
        ]))
        #expect(HookHandlerCommand.shouldForwardHook(environment: [
            "COCXY_CLAUDE_HOOKS": "1",
            "PI_SESSION_ID": "pi-session"
        ]))
    }

    @Test("debug record uses canonical Claude and filesystem fields")
    func debugRecordUsesCanonicalFields() {
        let data = Data(#"{"hook_event_name":"FileChanged","session_id":"payload-session","new_cwd":"/tmp/new","file_path":"/tmp/new/App.swift","event":"change"}"#.utf8)

        let record = HookHandlerCommand.debugRecord(
            stage: "received",
            data: data,
            environment: ["CLAUDE_CODE_SESSION_ID": "environment-session"]
        )

        #expect(record.contains("stage=received"))
        #expect(record.contains("source=claude"))
        #expect(record.contains("event=FileChanged"))
        #expect(record.contains("session=payload-session"))
        #expect(record.contains("cwd=/tmp/new"))
        #expect(record.contains("file=/tmp/new/App.swift"))
    }
}
