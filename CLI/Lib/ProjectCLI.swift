// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectCLI.swift - Project command parsing, socket requests, and output.

import Foundation

extension CLIArgumentParser {
    static func parseProjectCommand(
        _ command: String,
        arguments: [String]
    ) throws -> ParsedCommand {
        switch command {
        case "project-open":
            return .projectOpen(path: try singleValue(command, arguments, name: "path"))
        case "project-list":
            return .projectList(json: try parseJSONFlag(command, arguments))
        case "project-pin":
            return .projectPin(reference: try singleValue(command, arguments, name: "path"))
        case "project-unpin":
            return .projectUnpin(reference: try singleValue(command, arguments, name: "path"))
        case "project-forget":
            return .projectForget(reference: try singleValue(command, arguments, name: "path"))
        case "project-alias":
            guard let reference = arguments.first, !reference.isEmpty else {
                throw CLIError.missingArgument(command: command, argument: "path")
            }
            let alias = arguments.dropFirst().joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !alias.isEmpty else {
                throw CLIError.missingArgument(command: command, argument: "name")
            }
            return .projectAlias(reference: reference, alias: alias)
        case "project-clone":
            guard let remote = arguments.first, !remote.isEmpty else {
                throw CLIError.missingArgument(command: command, argument: "url")
            }
            guard arguments.count == 3, arguments[1] == "--into", !arguments[2].isEmpty else {
                throw CLIError.invalidArgument(
                    command: command,
                    argument: arguments.dropFirst().first ?? "",
                    reason: "Use <url> --into <directory>"
                )
            }
            return .projectClone(remote: remote, parentDirectory: arguments[2])
        case "project-tasks":
            var project: String?
            var json = false
            var index = 0
            while index < arguments.count {
                switch arguments[index] {
                case "--json" where !json:
                    json = true
                    index += 1
                case "--project" where project == nil:
                    guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                        throw CLIError.missingArgument(command: command, argument: "path")
                    }
                    project = arguments[index + 1]
                    index += 2
                default:
                    throw CLIError.invalidArgument(
                        command: command,
                        argument: arguments[index],
                        reason: "Use --project <path> and/or --json once"
                    )
                }
            }
            return .projectTasks(project: project, json: json)
        default:
            throw CLIError.unknownCommand(command)
        }
    }

    private static func singleValue(
        _ command: String,
        _ arguments: [String],
        name: String
    ) throws -> String {
        guard let value = arguments.first, !value.isEmpty else {
            throw CLIError.missingArgument(command: command, argument: name)
        }
        guard arguments.count == 1 else {
            throw CLIError.invalidArgument(
                command: command,
                argument: arguments[1],
                reason: "Unexpected extra argument"
            )
        }
        return value
    }

    private static func parseJSONFlag(_ command: String, _ arguments: [String]) throws -> Bool {
        guard arguments.isEmpty || arguments == ["--json"] else {
            throw CLIError.invalidArgument(
                command: command,
                argument: arguments.first ?? "",
                reason: "Only --json is supported"
            )
        }
        return !arguments.isEmpty
    }
}

enum ProjectCLIRequestBuilder {
    static func request(
        for command: ParsedCommand,
        id: String,
        currentDirectory: String
    ) -> CLISocketRequest {
        switch command {
        case .projectOpen(let path):
            return make(id, "project-open", ["path": absolute(path, from: currentDirectory)])
        case .projectList:
            return make(id, "project-list")
        case .projectPin(let reference):
            return make(id, "project-pin", ["project": absolute(reference, from: currentDirectory)])
        case .projectUnpin(let reference):
            return make(id, "project-unpin", ["project": absolute(reference, from: currentDirectory)])
        case .projectAlias(let reference, let alias):
            return make(id, "project-alias", [
                "project": absolute(reference, from: currentDirectory),
                "alias": alias,
            ])
        case .projectForget(let reference):
            return make(id, "project-forget", ["project": absolute(reference, from: currentDirectory)])
        case .projectClone(let remote, let parentDirectory):
            return make(id, "project-clone", [
                "remote": remote,
                "parent": absolute(parentDirectory, from: currentDirectory),
            ])
        case .projectTasks(let project, _):
            let params = project.map { ["project": absolute($0, from: currentDirectory)] }
            return make(id, "project-tasks", params)
        default:
            preconditionFailure("Project request builder received a non-project command")
        }
    }

    private static func make(
        _ id: String,
        _ command: String,
        _ params: [String: String]? = nil
    ) -> CLISocketRequest {
        CLISocketRequest(id: id, command: command, params: params)
    }

    private static func absolute(_ rawPath: String, from currentDirectory: String) -> String {
        let expanded = (rawPath as NSString).expandingTildeInPath
        let candidate = NSString(string: expanded).isAbsolutePath
            ? URL(fileURLWithPath: expanded)
            : URL(fileURLWithPath: currentDirectory, isDirectory: true)
                .appendingPathComponent(expanded)
        return candidate.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

enum ProjectCLIOutputFormatter {
    static func format(command: ParsedCommand, response: CLISocketResponse) -> String {
        switch command {
        case .projectOpen:
            return "Project opened: \(response.data?["path"] ?? "unknown")"
        case .projectList(let json):
            return collection(response, key: "projects", json: json, empty: "No registered projects.")
        case .projectPin:
            return "Project pinned: \(response.data?["path"] ?? "unknown")"
        case .projectUnpin:
            return "Project unpinned: \(response.data?["path"] ?? "unknown")"
        case .projectAlias:
            return "Project alias updated: \(response.data?["name"] ?? "project")"
        case .projectForget:
            return "Project forgotten: \(response.data?["path"] ?? "unknown")"
        case .projectClone:
            let output = "Project cloned: \(response.data?["path"] ?? "unknown")"
            return appendingWarning(response, to: output)
        case .projectTasks(_, let json):
            let output = collection(response, key: "tasks", json: json, empty: "No project tasks.")
            return json ? output : appendingWarning(response, to: output)
        default:
            return ""
        }
    }

    static func successWarning(command: ParsedCommand, response: CLISocketResponse) -> String? {
        guard case .projectTasks(_, json: true) = command,
              let warning = response.data?["warning"],
              !warning.isEmpty else {
            return nil
        }
        return warning
    }

    private static func appendingWarning(_ response: CLISocketResponse, to output: String) -> String {
        guard let warning = response.data?["warning"], !warning.isEmpty else { return output }
        return "\(output)\n\(warning)"
    }

    private static func collection(
        _ response: CLISocketResponse,
        key: String,
        json: Bool,
        empty: String
    ) -> String {
        guard let data = response.data else { return json ? "[]" : empty }
        if json { return prettyJSON(data[key] ?? "[]") }
        return data["summary"] ?? empty
    }

    private static func prettyJSON(_ value: String) -> String {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ) else {
            return value
        }
        return String(decoding: pretty, as: UTF8.self)
    }
}
