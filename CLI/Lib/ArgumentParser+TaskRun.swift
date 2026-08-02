// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ArgumentParser+TaskRun.swift - Parallel task command parsing.

import Foundation

extension CLIArgumentParser {
    static func parseTaskRun(arguments: [String]) throws -> ParsedCommand {
        if arguments.first == "list" {
            return try parseTaskRunList(arguments: Array(arguments.dropFirst()))
        }
        if arguments.first == "promote" {
            return try parseTaskRunPromotion(arguments: Array(arguments.dropFirst()))
        }

        var arguments = arguments
        if arguments.first == "launch" { arguments.removeFirst() }
        var prompt: String?
        var agents: String?
        var count: Int?
        var baseRef: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--prompt":
                prompt = try value(after: argument, in: arguments, at: &index, command: "task-run")
            case "--agents":
                agents = try value(after: argument, in: arguments, at: &index, command: "task-run")
            case "--count":
                let rawCount = try value(
                    after: argument,
                    in: arguments,
                    at: &index,
                    command: "task-run"
                )
                guard let parsedCount = Int(rawCount), (2...8).contains(parsedCount) else {
                    throw CLIError.invalidArgument(
                        command: "task-run",
                        argument: rawCount,
                        reason: "--count must be an integer from 2 through 8."
                    )
                }
                count = parsedCount
            case "--base-ref":
                baseRef = try value(after: argument, in: arguments, at: &index, command: "task-run")
            default:
                throw CLIError.invalidArgument(
                    command: "task-run",
                    argument: argument,
                    reason: "Use --prompt <text>, --agents <provider,...>, --count <2...8>, or --base-ref <ref>."
                )
            }
            index += 1
        }

        guard let prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty else {
            throw CLIError.missingArgument(command: "task-run", argument: "--prompt <text>")
        }
        guard let agents = agents?.trimmingCharacters(in: .whitespacesAndNewlines),
              !agents.isEmpty else {
            throw CLIError.missingArgument(command: "task-run", argument: "--agents <provider,...>")
        }
        let normalizedBaseRef = baseRef?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .taskRun(TaskRunCLIOptions(
            prompt: prompt,
            agents: agents,
            count: count,
            baseRef: normalizedBaseRef?.isEmpty == false ? normalizedBaseRef : nil
        ))
    }

    private static func parseTaskRunList(arguments: [String]) throws -> ParsedCommand {
        guard arguments.isEmpty || arguments.first == "--project" else {
            throw CLIError.invalidArgument(
                command: "task-run-list",
                argument: arguments.joined(separator: " "),
                reason: "Use --project <path>."
            )
        }
        guard !arguments.isEmpty else { return .taskRunList(project: nil) }
        var index = 0
        let rawProject = try value(
            after: "--project",
            in: arguments,
            at: &index,
            command: "task-run-list"
        )
        guard index == arguments.count - 1 else {
            throw CLIError.invalidArgument(
                command: "task-run-list",
                argument: arguments[(index + 1)...].joined(separator: " "),
                reason: "Use --project <path>."
            )
        }
        let project = rawProject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty else {
            throw CLIError.invalidArgument(
                command: "task-run-list",
                argument: "--project",
                reason: "Project cannot be empty."
            )
        }
        return .taskRunList(project: project)
    }

    private static func parseTaskRunPromotion(arguments: [String]) throws -> ParsedCommand {
        guard let runID = arguments.first,
              !runID.isEmpty,
              !runID.hasPrefix("-") else {
            throw CLIError.missingArgument(command: "task-run promote", argument: "run-id")
        }
        let remaining = Array(arguments.dropFirst())
        var candidateID: String?
        var index = 0
        while index < remaining.count {
            let argument = remaining[index]
            guard argument == "--candidate" else {
                throw CLIError.invalidArgument(
                    command: "task-run promote",
                    argument: argument,
                    reason: "Use --candidate <candidate-id>."
                )
            }
            candidateID = try value(
                after: argument,
                in: remaining,
                at: &index,
                command: "task-run promote"
            )
            index += 1
        }
        guard let candidateID else {
            throw CLIError.missingArgument(
                command: "task-run promote",
                argument: "--candidate <candidate-id>"
            )
        }
        return .taskRunPromote(runID: runID, candidateID: candidateID)
    }
}
