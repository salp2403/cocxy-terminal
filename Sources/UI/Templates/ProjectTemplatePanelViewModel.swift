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
    private enum StatusState: Equatable {
        case noTemplates
        case templates(Int)
        case loadFailed
        case selectTemplate
        case createdFiles(Int)
        case scaffoldFailed
    }

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
    @Published private(set) var statusText: String
    @Published private(set) var errorText: String?

    let destinationRootURL: URL

    private let registry: ProjectTemplateRegistry
    private let scaffolder: ProjectTemplateScaffolder
    private var localizer: AppLocalizer
    private var statusState: StatusState = .noTemplates
    private var currentError: Error?
    private var loadedTemplates: [ProjectTemplate] = []
    private var valuesByVariableName: [String: String] = [:]

    init(
        registry: ProjectTemplateRegistry = .localDefault(),
        destinationRootURL: URL,
        scaffolder: ProjectTemplateScaffolder = ProjectTemplateScaffolder(),
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.registry = registry
        self.destinationRootURL = destinationRootURL.standardizedFileURL
        self.scaffolder = scaffolder
        self.localizer = localizer
        self.statusText = Self.localizedStatusText(.noTemplates, localizer: localizer)
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        statusText = Self.localizedStatusText(statusState, localizer: localizer)
        if let currentError {
            errorText = Self.localizedErrorDescription(currentError, localizer: localizer)
        }
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
            currentError = nil
            errorText = nil
            setStatus(.templates(templates.count))
        } catch {
            loadedTemplates = []
            templates = []
            selectedTemplateID = nil
            valuesByVariableName = [:]
            createdFiles = []
            pendingHookCommands = []
            progress = 0
            currentError = error
            errorText = Self.localizedErrorDescription(error, localizer: localizer)
            setStatus(.loadFailed)
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
            setStatus(.selectTemplate)
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
            currentError = nil
            setStatus(.createdFiles(result.createdFiles.count))
        } catch {
            progress = 0
            currentError = error
            errorText = Self.localizedErrorDescription(error, localizer: localizer)
            setStatus(.scaffoldFailed)
            throw error
        }
    }

    func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            currentError = error
            errorText = Self.localizedErrorDescription(error, localizer: localizer)
        }
    }

    private func setStatus(_ status: StatusState) {
        statusState = status
        statusText = Self.localizedStatusText(status, localizer: localizer)
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

    private static func localizedStatusText(
        _ status: StatusState,
        localizer: AppLocalizer
    ) -> String {
        switch status {
        case .noTemplates:
            return localizer.string("templates.status.noTemplates", fallback: "No templates")
        case .templates(let count):
            return String(
                format: localizer.string(
                    count == 1 ? "templates.count.template.one" : "templates.count.template.many",
                    fallback: count == 1 ? "%d template" : "%d templates"
                ),
                count
            )
        case .loadFailed:
            return localizer.string("templates.status.loadFailed", fallback: "Load failed")
        case .selectTemplate:
            return localizer.string("templates.status.selectTemplate", fallback: "Select a template")
        case .createdFiles(let count):
            return String(
                format: localizer.string(
                    count == 1 ? "templates.status.created.one" : "templates.status.created.many",
                    fallback: count == 1 ? "Created %d file" : "Created %d files"
                ),
                count
            )
        case .scaffoldFailed:
            return localizer.string("templates.status.scaffoldFailed", fallback: "Scaffold failed")
        }
    }

    private static func localizedErrorDescription(
        _ error: Error,
        localizer: AppLocalizer
    ) -> String {
        if let templateError = error as? ProjectTemplateError {
            switch templateError {
            case .missingManifest(let url):
                return String(format: localizer.string("templates.error.missingManifest", fallback: "Missing template manifest: %@"), url.path)
            case .invalidIdentifier(let id):
                return String(format: localizer.string("templates.error.invalidIdentifier", fallback: "Invalid template identifier: %@"), id)
            case .missingFilesDirectory(let url):
                return String(format: localizer.string("templates.error.missingFilesDirectory", fallback: "Missing template files directory: %@"), url.path)
            case .missingRequiredVariable(let name):
                return String(format: localizer.string("templates.error.missingRequiredVariable", fallback: "Missing required template variable: %@"), name)
            case .unresolvedVariables(let names):
                return String(format: localizer.string("templates.error.unresolvedVariables", fallback: "Unresolved template variables: %@"), names.joined(separator: ", "))
            case .destinationExists(let path):
                return String(format: localizer.string("templates.error.destinationExists", fallback: "Template destination already exists: %@"), path)
            case .unsafeOutputPath(let path):
                return String(format: localizer.string("templates.error.unsafeOutputPath", fallback: "Template output path escapes the destination: %@"), path)
            case .nonUTF8TemplateFile(let path):
                return String(format: localizer.string("templates.error.nonUTF8TemplateFile", fallback: "Template file is not valid UTF-8: %@"), path)
            case .unreadableTemplateFile(let path):
                return String(format: localizer.string("templates.error.unreadableTemplateFile", fallback: "Template file cannot be read: %@"), path)
            }
        }
        return error.localizedDescription
    }
}
