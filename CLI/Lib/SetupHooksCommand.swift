// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SetupHooksCommand.swift - Multi-agent hook setup for supported agent CLIs.

import Foundation

public enum SetupHooksTarget: String, CaseIterable, Equatable {
    case claude
    case codex
    case gemini
    case kiro
    case opencode
    case pi
    case cursor
    case rovoDev = "rovo-dev"
    case copilot
    case codebuddy
    case factory
    case qoder
    case all

    static func fromCLIArgument(_ rawValue: String) -> SetupHooksTarget? {
        switch rawValue.lowercased() {
        case "claude":
            return .claude
        case "codex":
            return .codex
        case "gemini":
            return .gemini
        case "kiro":
            return .kiro
        case "opencode":
            return .opencode
        case "pi":
            return .pi
        case "cursor":
            return .cursor
        case "rovo", "rovo-dev", "rovodev":
            return .rovoDev
        case "copilot":
            return .copilot
        case "codebuddy":
            return .codebuddy
        case "factory":
            return .factory
        case "qoder":
            return .qoder
        case "all":
            return .all
        default:
            return nil
        }
    }

    var agentSource: AgentSource? {
        switch self {
        case .claude:
            return .claudeCode
        case .codex:
            return .codex
        case .gemini:
            return .geminiCLI
        case .kiro:
            return .kiro
        case .opencode:
            return .opencode
        case .pi:
            return .pi
        case .cursor:
            return .cursor
        case .rovoDev:
            return .rovoDev
        case .copilot:
            return .copilot
        case .codebuddy:
            return .codebuddy
        case .factory:
            return .factory
        case .qoder:
            return .qoder
        case .all:
            return nil
        }
    }
}

enum SetupHooksCommand {
    typealias CommandExists = (String) -> Bool

    private static let setupSources: [AgentSource] = [
        .claudeCode,
        .codex,
        .geminiCLI,
        .kiro,
        .opencode,
        .pi,
        .cursor,
        .rovoDev,
        .copilot,
        .codebuddy,
        .factory,
        .qoder
    ]

    static func execute(
        target: SetupHooksTarget?,
        remove: Bool,
        dryRun: Bool = false,
        check: Bool = false,
        opencodeProject: Bool = false,
        projectDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        commandExists: @escaping CommandExists = commandExists,
        settingsFilePathResolver: @escaping (AgentSource) -> String? = { $0.hookSettingsFilePath }
    ) -> CLIResult {
        if opencodeProject {
            return executeOpenCodeProject(
                remove: remove,
                dryRun: dryRun,
                check: check,
                projectDirectory: projectDirectory
            )
        }

        let sources = resolveSources(target: target, remove: remove, commandExists: commandExists)
        guard !sources.isEmpty else {
            return CLIResult(
                exitCode: 0,
                stdout: "No supported agent CLIs detected for hook setup.",
                stderr: ""
            )
        }

        if check {
            return executeCheck(
                sources: sources,
                target: target,
                settingsFilePathResolver: settingsFilePathResolver
            )
        }

        if dryRun {
            return executeDryRun(
                sources: sources,
                target: target,
                remove: remove,
                settingsFilePathResolver: settingsFilePathResolver
            )
        }

        var lines: [String] = []
        var hadFailure = false

        for source in sources {
            switch source {
            case _ where !source.supportsAutomaticHookSetup:
                lines.append(
                    "\(source.displayName): automatic setup not available yet. manual hook wiring is required for this agent."
                )
                if target?.agentSource == source {
                    hadFailure = true
                }
            case .unknown:
                continue
            default:
                do {
                    let line = try performSetup(
                        for: source,
                        remove: remove,
                        settingsFilePathResolver: settingsFilePathResolver
                    )
                    lines.append(line)
                } catch {
                    hadFailure = true
                    lines.append("\(source.displayName): failed to update hooks (\(error.localizedDescription)).")
                }
            }
        }

        return CLIResult(
            exitCode: hadFailure ? 1 : 0,
            stdout: lines.joined(separator: "\n"),
            stderr: ""
        )
    }

    private static func executeDryRun(
        sources: [AgentSource],
        target: SetupHooksTarget?,
        remove: Bool,
        settingsFilePathResolver: (AgentSource) -> String?
    ) -> CLIResult {
        var lines: [String] = [HooksDryRunFormatter.header()]
        var hadFailure = false

        for source in sources {
            switch source {
            case _ where !source.supportsAutomaticHookSetup:
                lines.append(
                    "\(source.displayName): automatic setup not available yet. manual hook wiring is required for this agent."
                )
                if target?.agentSource == source {
                    hadFailure = true
                }
            case .unknown:
                continue
            default:
                do {
                    let path = try settingsFilePath(for: source, resolver: settingsFilePathResolver)
                    if let warning = try hookConflictWarning(for: source, settingsFilePath: path) {
                        lines.append("\(source.displayName): \(warning)")
                    }
                    lines.append(HooksDryRunFormatter.line(
                        for: source,
                        settingsFilePath: path,
                        hookEvents: expectedHookEvents(for: source),
                        remove: remove
                    ))
                } catch {
                    hadFailure = true
                    lines.append("\(source.displayName): failed to prepare dry run (\(error.localizedDescription)).")
                }
            }
        }

        return CLIResult(
            exitCode: hadFailure ? 1 : 0,
            stdout: lines.joined(separator: "\n"),
            stderr: ""
        )
    }

    private static func executeCheck(
        sources: [AgentSource],
        target: SetupHooksTarget?,
        settingsFilePathResolver: (AgentSource) -> String?
    ) -> CLIResult {
        var lines: [String] = []
        var hadFailure = false

        for source in sources {
            switch source {
            case _ where !source.supportsAutomaticHookSetup:
                lines.append("\(source.displayName): automatic hook integrity check is not available yet.")
                hadFailure = true
            case .unknown:
                continue
            default:
                do {
                    let result = try checkHooks(
                        for: source,
                        settingsFilePathResolver: settingsFilePathResolver
                    )
                    lines.append(result.line)
                    hadFailure = hadFailure || result.failed
                } catch {
                    hadFailure = true
                    lines.append("\(source.displayName): failed to check hooks (\(error.localizedDescription)).")
                }
            }
        }

        return CLIResult(
            exitCode: hadFailure ? 1 : 0,
            stdout: lines.joined(separator: "\n"),
            stderr: ""
        )
    }

    private static func executeOpenCodeProject(
        remove: Bool,
        dryRun: Bool,
        check: Bool,
        projectDirectory: URL
    ) -> CLIResult {
        let manager = OpenCodeProjectHooksManager(projectDirectory: projectDirectory)

        do {
            if check {
                let result = try manager.check()
                return CLIResult(
                    exitCode: result.failed ? 1 : 0,
                    stdout: result.line,
                    stderr: ""
                )
            }

            if dryRun {
                return CLIResult(
                    exitCode: 0,
                    stdout: manager.dryRun(remove: remove),
                    stderr: ""
                )
            }

            let line = try remove ? manager.remove() : manager.install()
            return CLIResult(exitCode: 0, stdout: line, stderr: "")
        } catch {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: "OpenCode: failed to update project plugin (\(error.localizedDescription))."
            )
        }
    }

    static func detectInstalledAgents(
        commandExists: @escaping CommandExists = commandExists
    ) -> [AgentSource] {
        var agents: [AgentSource] = []

        for source in setupSources {
            if source.executableCandidates.contains(where: commandExists) {
                agents.append(source)
            }
        }

        return agents
    }

    private static func resolveSources(
        target: SetupHooksTarget?,
        remove: Bool,
        commandExists: @escaping CommandExists
    ) -> [AgentSource] {
        if let target {
            if let source = target.agentSource {
                return [source]
            }

            if remove {
                return setupSources
            }

            return detectInstalledAgents(commandExists: commandExists)
        }

        if remove {
            return setupSources
        }

        return detectInstalledAgents(commandExists: commandExists)
    }

    private static func performSetup(
        for source: AgentSource,
        remove: Bool,
        settingsFilePathResolver: (AgentSource) -> String? = { $0.hookSettingsFilePath }
    ) throws -> String {
        switch source {
        case .claudeCode:
            let manager = ClaudeSettingsManager()
            if remove {
                let result = try manager.uninstallHooks()
                if result.nothingToRemove {
                    return "Claude Code: no Cocxy hooks found."
                }
                return "Claude Code: hooks removed for \(result.removedEvents.joined(separator: ", "))."
            }

            let result = try manager.installHooks()
            if result.alreadyInstalled {
                return "Claude Code: hooks already installed."
            }
            return "Claude Code: hooks installed for \(result.hookEvents.joined(separator: ", "))."

        case .codex, .geminiCLI, .cursor, .copilot, .codebuddy, .factory, .qoder:
            guard let path = settingsFilePathResolver(source) else {
                throw HooksError.fileSystemError(reason: "Missing settings path")
            }
            let manager = GroupedHooksSettingsManager(
                settingsFilePath: path,
                hookEvents: source.hookEventNames,
                hookCommand: ClaudeSettingsManager.hookCommand(for: source)
            )
            let warning = try HooksConflictDetector.warning(for: manager.hookConflicts()).map {
                "\(source.displayName): \($0)"
            }

            if remove {
                let result = try manager.uninstallHooks()
                if result.nothingToRemove {
                    return [warning, "\(source.displayName): no Cocxy hooks found."]
                        .compactMap { $0 }
                        .joined(separator: "\n")
                }
                return [warning, "\(source.displayName): hooks removed for \(result.removedEvents.joined(separator: ", "))."]
                    .compactMap { $0 }
                    .joined(separator: "\n")
            }

            let result = try manager.installHooks()
            if result.alreadyInstalled {
                return [warning, "\(source.displayName): hooks already installed."]
                    .compactMap { $0 }
                    .joined(separator: "\n")
            }
            return [warning, "\(source.displayName): hooks installed for \(result.hookEvents.joined(separator: ", "))."]
                .compactMap { $0 }
                .joined(separator: "\n")

        case .pi:
            let path = try settingsFilePath(for: source, resolver: settingsFilePathResolver)
            let manager = PiExtensionHooksManager(extensionFilePath: path)
            if remove {
                let result = try manager.uninstallHooks()
                if result.nothingToRemove {
                    return "Pi: no Cocxy hooks found."
                }
                return "Pi: hooks removed for \(result.removedEvents.joined(separator: ", "))."
            }

            let result = try manager.installHooks()
            if result.alreadyInstalled {
                return "Pi: hooks already installed."
            }
            return "Pi: hooks installed for \(result.hookEvents.joined(separator: ", "))."

        case .rovoDev:
            let path = try settingsFilePath(for: source, resolver: settingsFilePathResolver)
            let manager = RovoDevHooksSettingsManager(configFilePath: path)
            if remove {
                let result = try manager.uninstallHooks()
                if result.nothingToRemove {
                    return "Rovo Dev: no Cocxy hooks found."
                }
                return "Rovo Dev: hooks removed for \(result.removedEvents.joined(separator: ", "))."
            }

            let result = try manager.installHooks()
            if result.alreadyInstalled {
                return "Rovo Dev: hooks already installed."
            }
            return "Rovo Dev: hooks installed for \(result.hookEvents.joined(separator: ", "))."

        case .kiro, .opencode, .unknown:
            return "\(source.displayName): manual setup required."
        }
    }

    private static func checkHooks(
        for source: AgentSource,
        settingsFilePathResolver: (AgentSource) -> String?
    ) throws -> (line: String, failed: Bool) {
        let expectedEvents = expectedHookEvents(for: source)
        let status: HooksStatusResult

        switch source {
        case .claudeCode:
            status = try ClaudeSettingsManager().hooksStatus()
        case .codex, .geminiCLI, .cursor, .copilot, .codebuddy, .factory, .qoder:
            let path = try settingsFilePath(for: source, resolver: settingsFilePathResolver)
            let manager = GroupedHooksSettingsManager(
                settingsFilePath: path,
                hookEvents: source.hookEventNames,
                hookCommand: ClaudeSettingsManager.hookCommand(for: source)
            )
            status = try manager.hooksStatus()
        case .pi:
            let path = try settingsFilePath(for: source, resolver: settingsFilePathResolver)
            status = try PiExtensionHooksManager(extensionFilePath: path).hooksStatus()
        case .rovoDev:
            let path = try settingsFilePath(for: source, resolver: settingsFilePathResolver)
            status = try RovoDevHooksSettingsManager(configFilePath: path).hooksStatus()
        case .kiro, .opencode, .unknown:
            return ("\(source.displayName): automatic hook integrity check is not available yet.", true)
        }

        let installed = Set(status.installedEvents)
        let missing = expectedEvents.filter { !installed.contains($0) }
        guard missing.isEmpty else {
            if installed.isEmpty {
                return ("\(source.displayName): hooks missing for \(missing.joined(separator: ", ")).", true)
            }
            return ("\(source.displayName): hooks incomplete; missing \(missing.joined(separator: ", ")).", true)
        }

        return ("\(source.displayName): hooks OK for \(expectedEvents.joined(separator: ", ")).", false)
    }

    private static func expectedHookEvents(for source: AgentSource) -> [String] {
        switch source {
        case .claudeCode:
            return ClaudeSettingsManager.hookedEventTypes
        default:
            return source.hookEventNames
        }
    }

    private static func settingsFilePath(
        for source: AgentSource,
        resolver: (AgentSource) -> String?
    ) throws -> String {
        switch source {
        case .claudeCode:
            return ClaudeSettingsManager.defaultSettingsFilePath
        default:
            guard let path = resolver(source) else {
                throw HooksError.fileSystemError(reason: "Missing settings path")
            }
            return path
        }
    }

    private static func hookConflictWarning(
        for source: AgentSource,
        settingsFilePath: String
    ) throws -> String? {
        switch source {
        case .codex, .geminiCLI, .cursor, .copilot, .codebuddy, .factory, .qoder:
            let manager = GroupedHooksSettingsManager(
                settingsFilePath: settingsFilePath,
                hookEvents: source.hookEventNames,
                hookCommand: ClaudeSettingsManager.hookCommand(for: source)
            )
            return HooksConflictDetector.warning(for: try manager.hookConflicts())
        default:
            return nil
        }
    }

    private static func commandExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = Pipe()
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
