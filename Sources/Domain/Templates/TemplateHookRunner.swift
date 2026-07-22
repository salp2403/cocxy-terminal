// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TemplateHookRunner.swift - Executes explicitly approved local scaffold hooks.

import Foundation

struct ProjectTemplateHookRunner {
    static let defaultTimeoutSeconds: TimeInterval = 300
    static let maximumRetainedBytesPerStream = 1 * 1_024 * 1_024

    private let sandbox: ProjectTemplateHookSandbox
    private let fileManager: FileManager
    private let timeoutSeconds: TimeInterval
    private let retainedBytesPerStream: Int

    init(
        sandbox: ProjectTemplateHookSandbox = ProjectTemplateHookSandbox(),
        fileManager: FileManager = .default,
        timeoutSeconds: TimeInterval = Self.defaultTimeoutSeconds,
        retainedBytesPerStream: Int = Self.maximumRetainedBytesPerStream
    ) {
        self.sandbox = sandbox
        self.fileManager = fileManager
        self.timeoutSeconds = timeoutSeconds
        self.retainedBytesPerStream = retainedBytesPerStream
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
        let result = try BoundedProcessRunner(
            maximumRetainedBytesPerStream: retainedBytesPerStream
        ).run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [command.executable] + command.arguments,
            workingDirectory: workingDirectory,
            environment: [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
                "COCXY_TEMPLATE_HOOK": "1",
            ],
            timeoutSeconds: timeoutSeconds,
            timeoutDiagnostic: "Template hook timed out."
        )

        let execution = ProjectTemplateHookExecution(
            phase: phase,
            command: originalCommand,
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
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
