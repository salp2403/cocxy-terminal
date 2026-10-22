// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandRunner+ResponseFormatting.swift - Successful socket response formatting.

extension CommandRunner {
    static func makeSuccessResult(
        command: ParsedCommand,
        response: CLISocketResponse
    ) -> CLIResult {
        let output = OutputFormatter.formatSuccess(command: command, response: response)
        let warning = OutputFormatter.formatSuccessWarning(command: command, response: response)
        return CLIResult(exitCode: 0, stdout: output, stderr: warning ?? "")
    }
}
