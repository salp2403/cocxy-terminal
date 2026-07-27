// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorkflowExecution.swift - Sequential local workflow execution.

import Foundation

enum WorkflowExecutionError: Error, Sendable, Equatable {
    case workingDirectoryEscapesRoot(String)
    case workingDirectoryMissing(String)
    case sandboxUnavailable
}

extension WorkflowExecutionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .workingDirectoryEscapesRoot(let path):
            return "Workflow working directory escapes the workspace root: \(path)"
        case .workingDirectoryMissing(let path):
            return "Workflow working directory does not exist: \(path)"
        case .sandboxUnavailable:
            return "Workflow execution requires the macOS sandbox."
        }
    }
}

enum WorkflowSandboxPolicy: Sendable, Equatable {
    case workspace
    case none
}

enum WorkflowExecutionStatus: Sendable, Equatable {
    case completed
    case failed(stepID: String, exitCode: Int32)
}

struct WorkflowStepExecutionResult: Sendable, Equatable {
    let stepID: String
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

struct WorkflowExecutionSummary: Sendable, Equatable {
    let workflowID: String
    let status: WorkflowExecutionStatus
    let results: [WorkflowStepExecutionResult]
}

struct WorkflowExecutor: Sendable {
    private let processRunner: any AgentProcessRunning
    private let defaultTimeoutSeconds: TimeInterval
    private let sandboxPolicy: WorkflowSandboxPolicy
    private let sandboxExecutor: SandboxExecutor
    private let sandboxProfileBuilder: SandboxProfileBuilder

    init(
        processRunner: any AgentProcessRunning = NotebookProcessRunner(),
        defaultTimeoutSeconds: TimeInterval = 300,
        sandboxPolicy: WorkflowSandboxPolicy = .workspace,
        sandboxExecutor: SandboxExecutor = SandboxExecutor(),
        sandboxProfileBuilder: SandboxProfileBuilder = SandboxProfileBuilder()
    ) {
        self.processRunner = processRunner
        self.defaultTimeoutSeconds = defaultTimeoutSeconds
        self.sandboxPolicy = sandboxPolicy
        self.sandboxExecutor = sandboxExecutor
        self.sandboxProfileBuilder = sandboxProfileBuilder
    }

    func execute(
        _ workflow: WorkflowDocument,
        workspaceRoot: URL
    ) throws -> WorkflowExecutionSummary {
        var results: [WorkflowStepExecutionResult] = []
        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()

        for step in workflow.steps {
            let workingDirectory = try resolveWorkingDirectory(
                step.workingDirectory,
                workspaceRoot: root
            )
            let executionPlan = try WorkflowSandboxExecutionPlan(
                step: step,
                workspaceRoot: root,
                workingDirectory: workingDirectory,
                policy: sandboxPolicy,
                sandboxExecutor: sandboxExecutor,
                profileBuilder: sandboxProfileBuilder
            )
            defer { executionPlan.cleanup() }
            let processResult = try processRunner.run(
                executableURL: executionPlan.executableURL,
                arguments: executionPlan.arguments,
                workingDirectory: workingDirectory,
                timeoutSeconds: step.timeoutSeconds ?? defaultTimeoutSeconds
            )
            results.append(WorkflowStepExecutionResult(
                stepID: step.id,
                exitCode: processResult.exitCode,
                stdout: processResult.stdout,
                stderr: processResult.stderr
            ))

            if processResult.exitCode != 0, !step.continueOnFailure {
                return WorkflowExecutionSummary(
                    workflowID: workflow.id,
                    status: .failed(stepID: step.id, exitCode: processResult.exitCode),
                    results: results
                )
            }
        }

        return WorkflowExecutionSummary(
            workflowID: workflow.id,
            status: .completed,
            results: results
        )
    }

    private func resolveWorkingDirectory(
        _ rawPath: String?,
        workspaceRoot: URL
    ) throws -> URL {
        guard let rawPath,
              !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return workspaceRoot
        }

        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.hasPrefix("/")
            ? URL(fileURLWithPath: trimmed, isDirectory: true)
            : workspaceRoot.appendingPathComponent(trimmed, isDirectory: true)
        let standardized = candidate.standardizedFileURL.resolvingSymlinksInPath()

        guard isInsideWorkspace(standardized, root: workspaceRoot) else {
            throw WorkflowExecutionError.workingDirectoryEscapesRoot(rawPath)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw WorkflowExecutionError.workingDirectoryMissing(rawPath)
        }
        return standardized
    }

    private func isInsideWorkspace(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.path
        let candidatePath = candidate.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}

private struct WorkflowSandboxExecutionPlan {
    private static let environmentPath =
        "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
    private static let executableSubpaths = [
        URL(fileURLWithPath: "/bin", isDirectory: true),
        URL(fileURLWithPath: "/usr/bin", isDirectory: true),
        URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
        URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer", isDirectory: true),
        URL(fileURLWithPath: "/Library/Developer/CommandLineTools", isDirectory: true),
        URL(fileURLWithPath: "/Library/Developer/Toolchains", isDirectory: true),
        URL(fileURLWithPath: "/private/var/select", isDirectory: true),
        URL(fileURLWithPath: "/var/select", isDirectory: true),
    ]

    let executableURL: URL
    let arguments: [String]
    private let temporaryDirectory: URL?

    init(
        step: WorkflowStep,
        workspaceRoot: URL,
        workingDirectory: URL,
        policy: WorkflowSandboxPolicy,
        sandboxExecutor: SandboxExecutor,
        profileBuilder: SandboxProfileBuilder,
        fileManager: FileManager = .default
    ) throws {
        guard policy == .workspace else {
            executableURL = step.shell.executableURL
            arguments = step.shell.commandArguments(for: step.command)
            temporaryDirectory = nil
            return
        }

        let temporaryDirectory = workspaceRoot.appendingPathComponent(
            ".cocxy-workflow-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            for name in ["home", "cache", "clang-module-cache", "swiftpm-module-cache"] {
                try fileManager.createDirectory(
                    at: temporaryDirectory.appendingPathComponent(name, isDirectory: true),
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
            }

            let resolvedTemporaryDirectory = temporaryDirectory
                .resolvingSymlinksInPath()
                .standardizedFileURL
            guard Self.isInsideWorkspace(resolvedTemporaryDirectory, root: workspaceRoot) else {
                throw WorkflowExecutionError.workingDirectoryEscapesRoot(
                    resolvedTemporaryDirectory.path
                )
            }
            let environmentURL = URL(fileURLWithPath: "/usr/bin/env")
            let profile = profileBuilder.profile(
                capabilities: [.filesystemRead, .filesystemWrite, .processExec],
                readablePaths: [workspaceRoot, resolvedTemporaryDirectory],
                writablePaths: [workspaceRoot, resolvedTemporaryDirectory],
                executablePaths: [environmentURL, step.shell.executableURL],
                readableLiteralPaths: SandboxProfileBuilder.parentDirectoryLiterals(
                    for: workspaceRoot
                ),
                writableLiteralPaths: [URL(fileURLWithPath: "/dev/null")],
                executableSubpaths: Self.executableSubpaths + [workspaceRoot],
                includeSystemReadBaseline: true,
                basePolicy: .isolateFilesystemAndNetwork
            )
            let temporaryPath = resolvedTemporaryDirectory.path
            let innerArguments = [
                "-i",
                "HOME=\(temporaryPath)/home",
                "TMPDIR=\(temporaryPath)",
                "XDG_CACHE_HOME=\(temporaryPath)/cache",
                "CLANG_MODULE_CACHE_PATH=\(temporaryPath)/clang-module-cache",
                "SWIFTPM_MODULECACHE_OVERRIDE=\(temporaryPath)/swiftpm-module-cache",
                "PATH=\(Self.environmentPath)",
                "LANG=en_US.UTF-8",
                "COCXY_WORKFLOW=1",
                step.shell.executableURL.path,
            ] + step.shell.commandArguments(for: step.command)
            let plan = try sandboxExecutor.launchPlan(
                commandURL: environmentURL,
                arguments: innerArguments,
                profile: profile,
                environment: [:],
                currentDirectoryURL: workingDirectory
            )
            executableURL = plan.executableURL
            arguments = plan.arguments
            self.temporaryDirectory = resolvedTemporaryDirectory
        } catch SandboxExecutorError.sandboxExecUnavailable {
            try? fileManager.removeItem(at: temporaryDirectory)
            throw WorkflowExecutionError.sandboxUnavailable
        } catch {
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    func cleanup(fileManager: FileManager = .default) {
        guard let temporaryDirectory else { return }
        try? fileManager.removeItem(at: temporaryDirectory)
    }

    private static func isInsideWorkspace(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.path
        let candidatePath = candidate.path
        return candidatePath.hasPrefix(rootPath + "/")
    }
}
