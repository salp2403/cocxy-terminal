// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectTemplatePanelViewModel.swift - UI state for local project scaffolds.

import Combine
import Foundation

struct ProjectTemplatePresentation: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let source: ProjectTemplateSource
    let variableCount: Int
}

@MainActor
final class ProjectTemplatePanelViewModel: ObservableObject {
    @Published private(set) var templates: [ProjectTemplatePresentation] = []
    @Published var selectedTemplateID: String? {
        didSet {
            guard oldValue != selectedTemplateID else { return }
            populateDefaultsForSelectedTemplate()
        }
    }
    @Published var destinationName: String = "NewProject"
    @Published private(set) var createdFiles: [String] = []
    @Published private(set) var pendingHookCommands: [String] = []
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusText = "No templates"
    @Published private(set) var errorText: String?

    let destinationRootURL: URL

    private let registry: ProjectTemplateRegistry
    private let scaffolder: ProjectTemplateScaffolder
    private var loadedTemplates: [ProjectTemplate] = []
    private var valuesByVariableName: [String: String] = [:]

    init(
        registry: ProjectTemplateRegistry = .localDefault(),
        destinationRootURL: URL,
        scaffolder: ProjectTemplateScaffolder = ProjectTemplateScaffolder()
    ) {
        self.registry = registry
        self.destinationRootURL = destinationRootURL.standardizedFileURL
        self.scaffolder = scaffolder
    }

    var selectedTemplate: ProjectTemplatePresentation? {
        guard let selectedTemplateID else { return nil }
        return templates.first { $0.id == selectedTemplateID }
    }

    var selectedVariables: [ProjectTemplateVariable] {
        selectedLoadedTemplate?.variables ?? []
    }

    func refresh() throws {
        do {
            let loaded = try registry.loadTemplates()
            loadedTemplates = loaded
            templates = loaded.map { template in
                ProjectTemplatePresentation(
                    id: template.id,
                    name: template.name,
                    summary: template.summary,
                    source: template.source,
                    variableCount: template.variables.count
                )
            }
            selectedTemplateID = templates.first?.id
            populateDefaultsForSelectedTemplate()
            createdFiles = []
            pendingHookCommands = []
            progress = 0
            errorText = nil
            statusText = templates.count == 1 ? "1 template" : "\(templates.count) templates"
        } catch {
            loadedTemplates = []
            templates = []
            selectedTemplateID = nil
            valuesByVariableName = [:]
            createdFiles = []
            pendingHookCommands = []
            progress = 0
            errorText = error.localizedDescription
            statusText = "Load failed"
            throw error
        }
    }

    func select(templateID: String?) {
        selectedTemplateID = templateID
    }

    func value(for variableName: String) -> String {
        valuesByVariableName[variableName] ?? ""
    }

    func setValue(_ value: String, for variableName: String) {
        valuesByVariableName[variableName] = value
    }

    func scaffoldSelected() throws {
        guard let template = selectedLoadedTemplate else {
            statusText = "Select a template"
            return
        }

        do {
            let destination = destinationURL(for: destinationName, root: destinationRootURL)
            progress = 0
            createdFiles = []
            pendingHookCommands = []
            errorText = nil

            let result = try scaffolder.scaffold(
                template: template,
                values: valuesByVariableName,
                destinationURL: destination
            )

            createdFiles = result.createdFiles
            pendingHookCommands = result.hookPlan.pre + result.hookPlan.post
            progress = 1
            statusText = "Created \(result.createdFiles.count) \(result.createdFiles.count == 1 ? "file" : "files")"
        } catch {
            progress = 0
            errorText = error.localizedDescription
            statusText = "Scaffold failed"
            throw error
        }
    }

    private var selectedLoadedTemplate: ProjectTemplate? {
        guard let selectedTemplateID else { return nil }
        return loadedTemplates.first { $0.id == selectedTemplateID }
    }

    private func populateDefaultsForSelectedTemplate() {
        guard let template = selectedLoadedTemplate else {
            valuesByVariableName = [:]
            return
        }

        valuesByVariableName = Dictionary(
            uniqueKeysWithValues: template.variables.map { variable in
                (variable.name, valuesByVariableName[variable.name] ?? variable.defaultValue ?? "")
            }
        )
    }

    private func destinationURL(for destinationName: String, root: URL) -> URL {
        let trimmed = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = trimmed.isEmpty ? "NewProject" : trimmed
        return root.appendingPathComponent(safeName, isDirectory: true).standardizedFileURL
    }
}
