// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CocxyShared
import Testing
@testable import CocxyCLILib

@Suite("Privileged socket approval timeouts")
struct PrivilegedSocketApprovalTimeoutSwiftTestingTests {
    @Test("privileged commands retain a full native approval window")
    func privilegedCommandsReceiveApprovalGrace() {
        let runner = CommandRunner(socketClient: SocketClient(
            socketPath: "/tmp/cocxy-timeout-test.sock",
            timeoutSeconds: 5
        ))

        #expect(runner.socketClient(for: .send(text: "id")).timeoutSeconds == 70)
        #expect(runner.socketClient(for: .browserEval(script: "1 + 1")).timeoutSeconds == 70)
        #expect(runner.socketClient(for: .browserWait(selector: "#ready", timeoutMilliseconds: nil)).timeoutSeconds == 73)
        #expect(runner.socketClient(for: .browserWait(selector: "#ready", timeoutMilliseconds: 30_000)).timeoutSeconds == 98)
        #expect(runner.socketClient(for: .browserWait(selector: "#ready", timeoutMilliseconds: 90_000)).timeoutSeconds == 98)
        #expect(runner.socketClient(for: .gitAssistantCommitMessage).timeoutSeconds == 130)
        #expect(runner.socketClient(for: .cellList).timeoutSeconds == 365)
        #expect(runner.socketClient(for: .status).timeoutSeconds == 5)
        #expect(runner.socketClient(for: .browserInitScriptAdd(script: "1")).timeoutSeconds == 605)
    }

    @Test("browser exclusions match specialized or non-privileged routes")
    func browserExclusionsRemainExplicit() {
        #expect(CommandRunner.requiresPrivilegedSocketApproval("browser-eval"))
        #expect(!CommandRunner.requiresPrivilegedSocketApproval("browser-split"))
        #expect(!CommandRunner.requiresPrivilegedSocketApproval("browser-init-script-add"))
        #expect(CommandRunner.requiresPrivilegedSocketApproval("web-start"))
        #expect(CommandRunner.requiresPrivilegedSocketApproval("web-stop"))
        #expect(CommandRunner.requiresPrivilegedSocketApproval("web-status"))
        #expect(CommandRunner.requiresPrivilegedSocketApproval("timeline-show"))
        #expect(CommandRunner.requiresPrivilegedSocketApproval("protocol-capabilities"))
        #expect(CommandRunner.requiresPrivilegedSocketApproval("core-font-metrics"))
        #expect(CommandRunner.requiresPrivilegedSocketApproval("image-list"))
        #expect(CommandRunner.requiresPrivilegedSocketApproval("notebook-run"))
        #expect(CommandRunner.requiresPrivilegedSocketApproval("workflow-run"))
        #expect(CommandRunner.requiresPrivilegedSocketApproval("cell-list"))
        #expect(CommandRunner.requiresPrivilegedSocketApproval("ssh"))
        #expect(!CommandRunner.requiresPrivilegedSocketApproval("agent-team-list"))
        #expect(!CommandRunner.requiresPrivilegedSocketApproval("status"))

        for command in [
            "browser-eval",
            "browser-split",
            "timeline-show",
            "cell-list",
            "agent-team-list",
            "status",
        ] {
            #expect(
                CommandRunner.requiresPrivilegedSocketApproval(command)
                    == CocxyPrivilegedSocketCommandPolicy.requiresApproval(command)
            )
        }
    }
}
