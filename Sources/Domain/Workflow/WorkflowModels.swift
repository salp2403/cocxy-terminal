// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorkflowModels.swift - Local reusable workflow domain values.

import Foundation

enum WorkflowShell: String, Codable, Sendable, Equatable, CaseIterable {
    case bash
    case zsh
    case sh

    init(normalizing rawValue: String?) {
        let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        self = WorkflowShell(rawValue: normalized) ?? .bash
    }

    var executableURL: URL {
        switch self {
        case .bash:
            return URL(fileURLWithPath: "/bin/bash")
        case .zsh:
            return URL(fileURLWithPath: "/bin/zsh")
        case .sh:
            return URL(fileURLWithPath: "/bin/sh")
        }
    }

    func commandArguments(for command: String) -> [String] {
        switch self {
        case .bash, .sh:
            return ["-c", command]
        case .zsh:
            return ["-f", "-c", command]
        }
    }
}

struct WorkflowStep: Codable, Sendable, Equatable {
    let id: String
    let title: String?
    let command: String
    let shell: WorkflowShell
    let workingDirectory: String?
    let timeoutSeconds: TimeInterval?
    let continueOnFailure: Bool

    init(
        id: String,
        title: String? = nil,
        command: String,
        shell: WorkflowShell = .bash,
        workingDirectory: String? = nil,
        timeoutSeconds: TimeInterval? = nil,
        continueOnFailure: Bool = false
    ) {
        self.id = Self.normalizedID(id)
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmedTitle?.isEmpty == false ? trimmedTitle : nil
        self.command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        self.shell = shell
        let trimmedDirectory = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.workingDirectory = trimmedDirectory?.isEmpty == false ? trimmedDirectory : nil
        self.timeoutSeconds = timeoutSeconds.map { max(1, $0) }
        self.continueOnFailure = continueOnFailure
    }

    static func normalizedID(_ rawID: String) -> String {
        rawID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct WorkflowDocument: Codable, Sendable, Equatable {
    let id: String
    let name: String?
    let description: String?
    let steps: [WorkflowStep]

    init(
        id: String,
        name: String? = nil,
        description: String? = nil,
        steps: [WorkflowStep]
    ) {
        self.id = WorkflowStep.normalizedID(id)
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmedName?.isEmpty == false ? trimmedName : nil
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = trimmedDescription?.isEmpty == false ? trimmedDescription : nil
        self.steps = steps
    }
}
