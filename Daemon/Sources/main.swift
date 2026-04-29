// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// main.swift - Local PTY daemon helper entrypoint.

import CocxyDaemonLib
#if canImport(Darwin)
import Darwin
#endif
import Foundation

#if canImport(Darwin)
_ = signal(SIGPIPE, SIG_IGN)
#endif

let server = PTYDaemonServer()
let arguments = Set(CommandLine.arguments.dropFirst())

if arguments.contains("--stdio") {
    server.runStdioLoop()
} else if arguments.contains("--hello") {
    server.writeHelloResponse()
} else {
    FileHandle.standardError.write(
        "Usage: cocxyd --stdio | --hello\n".data(using: .utf8)!
    )
    exit(64)
}
