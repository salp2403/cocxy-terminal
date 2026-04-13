// Copyright (c) 2026 Said Arturo Lopez. MIT License.

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
}
