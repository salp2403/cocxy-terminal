// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// main.swift - Entry point for the cocxy CLI companion.

import CocxyCLILib
import Foundation

// MARK: - Entry Point

/// Entry point for the `cocxy` CLI companion.
///
/// Parses command-line arguments, sends commands to the running Cocxy Terminal
/// app via its Unix Domain Socket, and prints the results.
///
/// Exit codes:
/// - 0: Success.
/// - 1: Error (connection failure, invalid arguments, server error).

let arguments = Array(CommandLine.arguments.dropFirst())
let runner = CommandRunner()
let result = runner.run(arguments: arguments)

if !result.stdout.isEmpty {
    print(result.stdout)
}

if !result.stderr.isEmpty {
    FileHandle.standardError.write((result.stderr + "\n").data(using: .utf8)!)
}

exit(result.exitCode)
