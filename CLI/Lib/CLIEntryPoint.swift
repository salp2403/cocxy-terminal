// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CLIEntryPoint.swift - Selects lightweight CLI startup paths before constructing the full runner.

import Foundation

public enum CLIEntryPoint {
    public static func run(
        arguments: [String],
        hookHandler: () -> CLIResult = {
            HookHandlerCommand.execute(socketClient: SocketClient())
        },
        commandRunnerFactory: () -> CommandRunner = { CommandRunner() }
    ) -> CLIResult {
        if arguments == ["hook-handler"] {
            return hookHandler()
        }
        return commandRunnerFactory().run(arguments: arguments)
    }
}
