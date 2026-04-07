// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// main.swift - Entry point for the cocxy CLI companion.

import CocxyCLILib
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
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

// Prevent SIGPIPE from killing the process during socket communication.
// Without this, a broken socket connection terminates the process with
// exit code 141 (128 + SIGPIPE) before Swift's error handling can catch it.
// With SIG_IGN, write() returns -1 with errno EPIPE instead, which the
// existing SocketClient error handling catches gracefully.
_ = signal(SIGPIPE, SIG_IGN)

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
