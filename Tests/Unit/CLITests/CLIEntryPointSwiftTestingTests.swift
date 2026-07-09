// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyCLILib

@Suite("CLI entry point")
struct CLIEntryPointSwiftTestingTests {
    @Test("exact hook-handler invocation bypasses full command runner construction")
    func exactHookHandlerBypassesCommandRunner() {
        var hookHandlerCalls = 0
        var commandRunnerConstructions = 0

        let result = CLIEntryPoint.run(
            arguments: ["hook-handler"],
            hookHandler: {
                hookHandlerCalls += 1
                return CLIResult(exitCode: 0, stdout: "", stderr: "")
            },
            commandRunnerFactory: {
                commandRunnerConstructions += 1
                return CommandRunner(socketClient: SocketClient(socketPath: "/tmp/unused.sock"))
            }
        )

        #expect(result.exitCode == 0)
        #expect(hookHandlerCalls == 1)
        #expect(commandRunnerConstructions == 0)
    }

    @Test("non-exact hook-handler invocations preserve command runner parsing")
    func nonExactHookHandlerInvocationsUseCommandRunner() {
        var hookHandlerCalls = 0
        var commandRunnerConstructions = 0

        let result = CLIEntryPoint.run(
            arguments: ["hook-handler", "unexpected"],
            hookHandler: {
                hookHandlerCalls += 1
                return CLIResult(exitCode: 0, stdout: "", stderr: "")
            },
            commandRunnerFactory: {
                commandRunnerConstructions += 1
                return CommandRunner(socketClient: SocketClient(socketPath: "/tmp/unused.sock"))
            }
        )

        #expect(result.exitCode == 0)
        #expect(hookHandlerCalls == 0)
        #expect(commandRunnerConstructions == 1)
    }
}
