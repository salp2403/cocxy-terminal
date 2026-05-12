// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultSessionResumer.swift - Resume planning and execution without shell interpolation.

import Foundation

public enum VaultSessionResumer {
    public static func plan(agent: VaultAgent, session: VaultSession) throws -> VaultResumeInvocation {
        try plan(agent: agent, sessionID: session.sessionID, workingDirectory: session.workingDirectory)
    }

    public static func plan(
        agent: VaultAgent,
        sessionID: String,
        workingDirectory: String? = nil
    ) throws -> VaultResumeInvocation {
        let trimmedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSessionID.isEmpty else {
            throw VaultError.emptySessionID
        }
        guard !agent.resumeArgumentsTemplate.isEmpty else {
            throw VaultError.invalidResumeTemplate(agent.id.rawValue)
        }

        let arguments = agent.resumeArgumentsTemplate.map {
            $0.replacingOccurrences(of: "{{sessionID}}", with: trimmedSessionID)
        }
        return VaultResumeInvocation(
            executable: agent.primaryBinaryName,
            arguments: arguments,
            workingDirectory: workingDirectory
        )
    }

    public static func run(_ invocation: VaultResumeInvocation) throws -> VaultResumeResult {
        let process = Process()
        if invocation.executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: invocation.executable)
            process.arguments = invocation.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [invocation.executable] + invocation.arguments
        }
        if let workingDirectory = invocation.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        let stdout = String(
            decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        let stderr = String(
            decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        return VaultResumeResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}
