// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GuidedOnboarding.swift - Local guided onboarding state and artifact setup.

import Foundation

// MARK: - Onboarding Values

struct OnboardingSelection: Equatable, Sendable {
    let theme: String
    let agentAutoMode: Bool
    let lspEnabled: Bool
    let createTabConfig: Bool
    let createPrimerSkill: Bool
    let createFirstWorkflow: Bool

    init(
        theme: String = CocxyConfig.defaults.appearance.theme,
        agentAutoMode: Bool = CocxyConfig.defaults.agent.autoMode,
        lspEnabled: Bool = CocxyConfig.defaults.lsp.enabled,
        createTabConfig: Bool = true,
        createPrimerSkill: Bool = true,
        createFirstWorkflow: Bool = true
    ) {
        self.theme = theme
        self.agentAutoMode = agentAutoMode
        self.lspEnabled = lspEnabled
        self.createTabConfig = createTabConfig
        self.createPrimerSkill = createPrimerSkill
        self.createFirstWorkflow = createFirstWorkflow
    }
}

struct OnboardingResult: Equatable, Sendable {
    let createdTabConfigName: String?
    let createdSkillID: String?
    let createdWorkflowID: String?
}

// MARK: - Onboarding State

struct OnboardingStateStore {
    enum State: String, Sendable {
        case completed
        case skipped
    }

    static let defaultStateKey = "cocxy.onboarding.state"

    private let userDefaults: UserDefaults
    private let stateKey: String

    init(
        userDefaults: UserDefaults = .standard,
        stateKey: String = OnboardingStateStore.defaultStateKey
    ) {
        self.userDefaults = userDefaults
        self.stateKey = stateKey
    }

    var shouldPresentAutomatically: Bool {
        userDefaults.string(forKey: stateKey) == nil
    }

    func markCompleted() {
        userDefaults.set(State.completed.rawValue, forKey: stateKey)
    }

    func markSkipped() {
        userDefaults.set(State.skipped.rawValue, forKey: stateKey)
    }

    func reset() {
        userDefaults.removeObject(forKey: stateKey)
    }
}

// MARK: - Onboarding Applier

struct GuidedOnboardingApplier {
    let configFileProvider: ConfigFileProviding
    let tabConfigStore: TabConfigStore
    let skillDirectory: URL
    let workflowDirectory: URL
    private let fileManager: FileManager

    init(
        configFileProvider: ConfigFileProviding = DiskConfigFileProvider(),
        tabConfigStore: TabConfigStore = TabConfigStore(),
        skillDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy/skills", isDirectory: true),
        workflowDirectory: URL = WorkflowRegistry.defaultDirectory(),
        fileManager: FileManager = .default
    ) {
        self.configFileProvider = configFileProvider
        self.tabConfigStore = tabConfigStore
        self.skillDirectory = skillDirectory.standardizedFileURL
        self.workflowDirectory = workflowDirectory.standardizedFileURL
        self.fileManager = fileManager
    }

    func complete(
        _ selection: OnboardingSelection,
        workingDirectory: String
    ) throws -> OnboardingResult {
        try persistSettings(selection)

        let createdTabConfigName = try createStarterTabConfig(
            enabled: selection.createTabConfig,
            theme: selection.theme,
            workingDirectory: workingDirectory
        )
        let createdSkillID = try createPrimerSkill(enabled: selection.createPrimerSkill)
        let createdWorkflowID = try createFirstWorkflow(
            enabled: selection.createFirstWorkflow,
            workingDirectory: workingDirectory
        )

        return OnboardingResult(
            createdTabConfigName: createdTabConfigName,
            createdSkillID: createdSkillID,
            createdWorkflowID: createdWorkflowID
        )
    }

    private func persistSettings(_ selection: OnboardingSelection) throws {
        var content = configFileProvider.readConfigFile() ?? ConfigService.generateDefaultToml()
        content = OnboardingTOMLUpdater.upsertingValue(
            section: "appearance",
            key: "theme",
            value: "\"\(OnboardingTOMLUpdater.escape(selection.theme))\"",
            in: content
        )
        content = OnboardingTOMLUpdater.upsertingValue(
            section: "agent",
            key: "auto-mode",
            value: selection.agentAutoMode ? "true" : "false",
            in: content
        )
        content = OnboardingTOMLUpdater.upsertingValue(
            section: "lsp",
            key: "enabled",
            value: selection.lspEnabled ? "true" : "false",
            in: content
        )
        try configFileProvider.writeConfigFile(content)
    }

    private func createStarterTabConfig(
        enabled: Bool,
        theme: String,
        workingDirectory: String
    ) throws -> String? {
        guard enabled else { return nil }
        let config = TabConfig(
            name: "starter",
            workingDirectory: workingDirectory,
            theme: theme
        )
        try tabConfigStore.save(config)
        return config.name
    }

    private func createPrimerSkill(enabled: Bool) throws -> String? {
        guard enabled else { return nil }
        let skillID = "cocxy-primer"
        let directory = skillDirectory.appendingPathComponent(skillID, isDirectory: true)
        let skillFile = directory.appendingPathComponent("SKILL.md")
        if fileManager.fileExists(atPath: skillFile.path) {
            return skillID
        }

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try primerSkillMarkdown.write(to: skillFile, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: skillFile.path)
        return skillID
    }

    private func createFirstWorkflow(
        enabled: Bool,
        workingDirectory: String
    ) throws -> String? {
        guard enabled else { return nil }
        let workflow = WorkflowDocument(
            id: "first-check",
            name: "First Check",
            description: "Local project status check.",
            steps: [
                WorkflowStep(
                    id: "status",
                    title: "Project status",
                    command: "pwd && git status --short",
                    shell: .zsh,
                    workingDirectory: workingDirectory,
                    timeoutSeconds: 30
                ),
            ]
        )

        try fileManager.createDirectory(
            at: workflowDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let workflowFile = workflowDirectory.appendingPathComponent("\(workflow.id).toml")
        if !fileManager.fileExists(atPath: workflowFile.path) {
            try WorkflowTOMLCodec.render(workflow).write(
                to: workflowFile,
                atomically: true,
                encoding: .utf8
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: workflowFile.path
            )
        }
        return workflow.id
    }

    private var primerSkillMarkdown: String {
        """
        ---
        id: cocxy-primer
        name: Cocxy Primer
        description: Starter local workflow and project-orientation skill.
        ---

        Use local project files first. Prefer repository commands and existing scripts.
        Keep actions local, explicit, and reversible.
        """
    }
}

// MARK: - TOML Updating

private enum OnboardingTOMLUpdater {
    static func upsertingValue(
        section: String,
        key: String,
        value: String,
        in content: String
    ) -> String {
        var lines = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let header = "[\(section)]"

        guard let sectionIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == header
        }) else {
            if !lines.isEmpty, lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append(header)
            lines.append("\(key) = \(value)")
            return render(lines)
        }

        let sectionEnd = lines[(sectionIndex + 1)...].firstIndex(where: isTableHeader)
            ?? lines.endIndex
        if let keyIndex = lines[(sectionIndex + 1)..<sectionEnd].firstIndex(where: {
            tomlKey(in: $0) == key
        }) {
            lines[keyIndex] = "\(key) = \(value)"
        } else {
            lines.insert("\(key) = \(value)", at: sectionEnd)
        }

        return render(lines)
    }

    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private static func render(_ lines: [String]) -> String {
        let rendered = lines.joined(separator: "\n")
        return rendered.hasSuffix("\n") ? rendered : rendered + "\n"
    }

    private static func isTableHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
    }

    private static func tomlKey(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("#"),
              let equals = trimmed.firstIndex(of: "=") else {
            return nil
        }
        return String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
    }
}
