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
        commandExists: @escaping CommandExists = commandExists
    ) -> CLIResult {
        let sources = resolveSources(target: target, remove: remove, commandExists: commandExists)
        guard !sources.isEmpty else {
            return CLIResult(
                exitCode: 0,
                stdout: "No supported agent CLIs detected for hook setup.",
                stderr: ""
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
                    let line = try performSetup(for: source, remove: remove)
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
        remove: Bool
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

        case .codex, .geminiCLI:
            guard let path = source.hookSettingsFilePath else {
                throw HooksError.fileSystemError(reason: "Missing settings path")
            }
            let manager = GroupedHooksSettingsManager(
                settingsFilePath: path,
                hookEvents: source.hookEventNames,
                hookCommand: ClaudeSettingsManager.hookCommand(for: source)
            )

            if remove {
                let result = try manager.uninstallHooks()
                if result.nothingToRemove {
                    return "\(source.displayName): no Cocxy hooks found."
                }
                return "\(source.displayName): hooks removed for \(result.removedEvents.joined(separator: ", "))."
            }

            let result = try manager.installHooks()
            if result.alreadyInstalled {
                return "\(source.displayName): hooks already installed."
            }
            return "\(source.displayName): hooks installed for \(result.hookEvents.joined(separator: ", "))."

        case .kiro, .opencode, .pi, .cursor, .rovoDev, .copilot, .codebuddy, .factory, .qoder, .unknown:
            return "\(source.displayName): manual setup required."
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
