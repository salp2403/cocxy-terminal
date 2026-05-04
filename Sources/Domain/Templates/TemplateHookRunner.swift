// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TemplateHookRunner.swift - Executes explicitly approved local scaffold hooks.

import Foundation

struct ProjectTemplateHookRunner {
    private let sandbox: ProjectTemplateHookSandbox
    private let fileManager: FileManager

    init(
        sandbox: ProjectTemplateHookSandbox = ProjectTemplateHookSandbox(),
        fileManager: FileManager = .default
    ) {
        self.sandbox = sandbox
        self.fileManager = fileManager
    }

    func run(
        _ plan: ProjectTemplateHookPlan,
        phases: Set<ProjectTemplateHookPhase> = [.pre, .post]
    ) throws -> [ProjectTemplateHookExecution] {
        let workingDirectory = plan.workingDirectory.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: workingDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProjectTemplateHookError.workingDirectoryMissing(workingDirectory)
        }

        var executions: [ProjectTemplateHookExecution] = []
        if phases.contains(.pre) {
            executions.append(contentsOf: try run(plan.pre, phase: .pre, workingDirectory: workingDirectory))
        }
        if phases.contains(.post) {
            executions.append(contentsOf: try run(plan.post, phase: .post, workingDirectory: workingDirectory))
        }
        return executions
    }

    private func run(
        _ commands: [String],
        phase: ProjectTemplateHookPhase,
        workingDirectory: URL
    ) throws -> [ProjectTemplateHookExecution] {
        var executions: [ProjectTemplateHookExecution] = []
        for command in commands {
            let parsed = try sandbox.validate(command)
            let execution = try execute(
                parsed,
                originalCommand: command,
                phase: phase,
                workingDirectory: workingDirectory
            )
            executions.append(execution)
        }
        return executions
    }

    private func execute(
        _ command: ProjectTemplateHookCommand,
        originalCommand: String,
        phase: ProjectTemplateHookPhase,
        workingDirectory: URL
    ) throws -> ProjectTemplateHookExecution {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command.executable] + command.arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
            "COCXY_TEMPLATE_HOOK": "1",
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutText = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderrText = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        let execution = ProjectTemplateHookExecution(
            phase: phase,
            command: originalCommand,
            exitCode: process.terminationStatus,
            stdout: stdoutText,
            stderr: stderrText
        )
        guard execution.exitCode == 0 else {
            throw ProjectTemplateHookError.commandFailed(
                command: originalCommand,
                exitCode: execution.exitCode,
                stderr: execution.stderr
            )
        }
        return execution
    }
}
