// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookSystemToolProcessRunner.swift - Stable system-tool environment for notebook E2E tests.

import Foundation
@testable import CocxyTerminal

struct NotebookSystemToolProcessRunner: AgentProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval?
    ) throws -> AgentProcessResult {
        let result = try LaunchdProcessBrokerClient(
            maximumRetainedBytesPerStream: NotebookProcessRunner.maximumRetainedBytesPerStream
        ).run(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: [
                "PATH": "/usr/bin:/bin",
                "HOME": workingDirectory.path,
                "LANG": "C",
            ],
            timeoutSeconds: timeoutSeconds
        )
        return AgentProcessResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }
}
