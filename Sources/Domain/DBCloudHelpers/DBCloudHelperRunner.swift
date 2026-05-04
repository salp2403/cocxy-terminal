// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DBCloudHelperRunner.swift - Explicit local CLI execution for DB/cloud helper actions.

import Foundation

struct LocalDBCloudHelperRunner {
    func run(_ command: DBCloudHelperCommand) throws -> DBCloudHelperRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command.executable] + command.arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return DBCloudHelperRunResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}
