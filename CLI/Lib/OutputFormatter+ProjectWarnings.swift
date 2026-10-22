// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// OutputFormatter+ProjectWarnings.swift - Project command warning output.

extension OutputFormatter {
    public static func formatSuccessWarning(
        command: ParsedCommand,
        response: CLISocketResponse
    ) -> String? {
        ProjectCLIOutputFormatter.successWarning(command: command, response: response)
    }
}
