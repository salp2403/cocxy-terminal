// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorkflowTOMLCodec.swift - TOML parser and renderer for local workflows.

import Foundation

enum WorkflowTOMLCodecError: Error, Sendable, Equatable {
    case missingWorkflowTable
    case missingWorkflowID
    case noWorkflowSteps
    case missingStep(String)
    case missingCommand(String)
}

extension WorkflowTOMLCodecError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingWorkflowTable:
            return "Workflow TOML must include a [workflow] table."
        case .missingWorkflowID:
            return "Workflow TOML must include workflow.id."
        case .noWorkflowSteps:
            return "Workflow TOML must include at least one step."
        case .missingStep(let id):
            return "Workflow TOML references missing step: \(id)"
        case .missingCommand(let id):
            return "Workflow step must include a command: \(id)"
        }
    }
}

enum WorkflowTOMLCodec {
    static func parse(_ source: String) throws -> WorkflowDocument {
        let parsed = try TOMLParser().parse(source)
        guard case .table(let workflowTable) = parsed["workflow"] else {
            throw WorkflowTOMLCodecError.missingWorkflowTable
        }
        guard let id = stringValue(workflowTable["id"]),
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw WorkflowTOMLCodecError.missingWorkflowID
        }

        let stepIDs = stringArrayValue(workflowTable["steps"]) ?? []
        guard !stepIDs.isEmpty else {
            throw WorkflowTOMLCodecError.noWorkflowSteps
        }

        let steps = try stepIDs.map { rawStepID -> WorkflowStep in
            let stepID = WorkflowStep.normalizedID(rawStepID)
            guard case .table(let stepTable) = parsed["step.\(stepID)"] else {
                throw WorkflowTOMLCodecError.missingStep(stepID)
            }
            guard let command = stringValue(stepTable["command"]),
                  !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw WorkflowTOMLCodecError.missingCommand(stepID)
            }
            return WorkflowStep(
                id: stepID,
                title: stringValue(stepTable["title"]),
                command: command,
                shell: WorkflowShell(normalizing: stringValue(stepTable["shell"])),
                workingDirectory: stringValue(stepTable["working-directory"]),
                timeoutSeconds: doubleValue(stepTable["timeout-seconds"]),
                continueOnFailure: boolValue(stepTable["continue-on-failure"]) ?? false
            )
        }

        return WorkflowDocument(
            id: id,
            name: stringValue(workflowTable["name"]),
            description: stringValue(workflowTable["description"]),
            steps: steps
        )
    }

    static func render(_ workflow: WorkflowDocument) -> String {
        var lines: [String] = [
            "[workflow]",
            "id = \"\(escape(workflow.id))\"",
        ]
        if let name = workflow.name {
            lines.append("name = \"\(escape(name))\"")
        }
        if let description = workflow.description {
            lines.append("description = \"\(escape(description))\"")
        }
        lines.append("steps = [\(workflow.steps.map { "\"\(escape($0.id))\"" }.joined(separator: ", "))]")

        for step in workflow.steps {
            lines.append("")
            lines.append("[step.\(step.id)]")
            if let title = step.title {
                lines.append("title = \"\(escape(title))\"")
            }
            lines.append("command = \"\(escape(step.command))\"")
            if step.shell != .bash {
                lines.append("shell = \"\(step.shell.rawValue)\"")
            }
            if let workingDirectory = step.workingDirectory {
                lines.append("working-directory = \"\(escape(workingDirectory))\"")
            }
            if let timeoutSeconds = step.timeoutSeconds {
                lines.append("timeout-seconds = \(formatNumber(timeoutSeconds))")
            }
            if step.continueOnFailure {
                lines.append("continue-on-failure = true")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func stringValue(_ value: TOMLValue?) -> String? {
        guard case .string(let value) = value else { return nil }
        return value
    }

    private static func boolValue(_ value: TOMLValue?) -> Bool? {
        guard case .boolean(let value) = value else { return nil }
        return value
    }

    private static func doubleValue(_ value: TOMLValue?) -> Double? {
        switch value {
        case .integer(let value):
            return Double(value)
        case .float(let value):
            return value
        default:
            return nil
        }
    }

    private static func stringArrayValue(_ value: TOMLValue?) -> [String]? {
        guard case .array(let values) = value else { return nil }
        return values.compactMap { item in
            guard case .string(let value) = item else { return nil }
            return value
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func formatNumber(_ value: TimeInterval) -> String {
        value.rounded(.down) == value ? "\(Int(value))" : "\(value)"
    }
}
