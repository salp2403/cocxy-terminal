// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectTemplatePanelViewModelSwiftTestingTests.swift - UI state for local project scaffolds.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Project template panel view model")
struct ProjectTemplatePanelViewModelSwiftTestingTests {
    @Test("refresh loads templates and selects the first with default values")
    func refreshLoadsTemplatesAndSelectsFirstWithDefaultValues() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let templatesRoot = root.appendingPathComponent("templates", isDirectory: true)
        try writeTemplate(
            id: "swift-package",
            name: "Swift Package",
            summary: "Create a Swift package",
            in: templatesRoot
        )

        let viewModel = ProjectTemplatePanelViewModel(
            registry: ProjectTemplateRegistry(
                directories: [ProjectTemplateDirectory(url: templatesRoot, source: .builtIn)]
            ),
            destinationRootURL: root.appendingPathComponent("output", isDirectory: true)
        )

        try viewModel.refresh()

        #expect(viewModel.templates.map(\.id) == ["swift-package"])
        #expect(viewModel.selectedTemplateID == "swift-package")
        #expect(viewModel.value(for: "project_name") == "Demo")
        #expect(viewModel.value(for: "module_name") == "Demo")
        #expect(viewModel.statusText == "1 template")
    }

    @Test("scaffold selected template writes files and reports progress")
    func scaffoldSelectedTemplateWritesFilesAndReportsProgress() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let templatesRoot = root.appendingPathComponent("templates", isDirectory: true)
        let outputRoot = root.appendingPathComponent("output", isDirectory: true)
        try writeTemplate(
            id: "swift-package",
            name: "Swift Package",
            summary: "Create a Swift package",
            files: [
                "README.md": "# {{project_name}}\n",
                "Sources/{{module_name}}/main.swift": "print(\"{{project_name}}\")\n",
            ],
            hooks: ProjectTemplateHooks(post: ["swift test"]),
            in: templatesRoot
        )
        let viewModel = ProjectTemplatePanelViewModel(
            registry: ProjectTemplateRegistry(
                directories: [ProjectTemplateDirectory(url: templatesRoot, source: .builtIn)]
            ),
            destinationRootURL: outputRoot
        )
        try viewModel.refresh()
        viewModel.destinationName = "Generated"
        viewModel.setValue("Generated", for: "project_name")
        viewModel.setValue("GeneratedCore", for: "module_name")

        try viewModel.scaffoldSelected()

        #expect(viewModel.progress == 1)
        #expect(viewModel.createdFiles == ["README.md", "Sources/GeneratedCore/main.swift"])
        #expect(viewModel.pendingHookCommands == ["swift test"])
        #expect(viewModel.statusText == "Created 2 files")
        #expect(try String(
            contentsOf: outputRoot.appendingPathComponent("Generated/README.md"),
            encoding: .utf8
        ) == "# Generated\n")
    }

    @Test("Spanish localizer updates template panel statuses")
    func spanishLocalizerUpdatesTemplatePanelStatuses() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let templatesRoot = root.appendingPathComponent("templates", isDirectory: true)
        let outputRoot = root.appendingPathComponent("output", isDirectory: true)
        try writeTemplate(
            id: "swift-package",
            name: "Swift Package",
            summary: "Create a Swift package",
            files: ["README.md": "# {{project_name}}\n"],
            in: templatesRoot
        )
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let viewModel = ProjectTemplatePanelViewModel(
            registry: ProjectTemplateRegistry(
                directories: [ProjectTemplateDirectory(url: templatesRoot, source: .builtIn)]
            ),
            destinationRootURL: outputRoot,
            localizer: spanish
        )

        try viewModel.refresh()

        #expect(spanish.string("templates.scaffold", fallback: "Scaffold") == "Generar")
        #expect(spanish.string("templates.status.scaffoldFailed", fallback: "Scaffold failed") == "No se pudo generar")
        #expect(
            spanish.string(
                "command.workspace.templates.description",
                fallback: "Open local project scaffolds and template variables"
            ) == "Abrir plantillas de proyecto locales y sus variables"
        )
        #expect(ProjectTemplateSource.builtIn.localizedTitle(using: spanish) == "incluida")
        #expect(viewModel.statusText == "1 plantilla")

        viewModel.destinationName = "Generado"
        viewModel.setValue("Generado", for: "project_name")
        try viewModel.scaffoldSelected()

        #expect(viewModel.statusText == "1 archivo creado")

        viewModel.updateLocalizer(AppLocalizer(languagePreference: .english, bundle: bundle))

        #expect(viewModel.statusText == "Created 1 file")
    }

    @Test("Spanish localizer translates built-in template metadata")
    func spanishLocalizerTranslatesBuiltInTemplateMetadata() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let templatesRoot = root.appendingPathComponent("templates", isDirectory: true)
        try writeTemplate(
            id: "docker-service",
            name: "Docker Service",
            summary: "Creates a minimal local service with Docker assets.",
            variables: [
                ProjectTemplateVariable(name: "project_name", prompt: "Project name", defaultValue: "cocxy-service"),
                ProjectTemplateVariable(name: "service_name", prompt: "Service name", defaultValue: "cocxy-service"),
            ],
            in: templatesRoot
        )
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let viewModel = ProjectTemplatePanelViewModel(
            registry: ProjectTemplateRegistry(
                directories: [ProjectTemplateDirectory(url: templatesRoot, source: .builtIn)]
            ),
            destinationRootURL: root.appendingPathComponent("output", isDirectory: true),
            localizer: spanish
        )

        try viewModel.refresh()

        #expect(viewModel.templates.first?.name == "Servicio Docker")
        #expect(viewModel.templates.first?.summary == "Crea un servicio local mínimo con archivos Docker.")
        #expect(viewModel.selectedVariables.map(\.prompt) == ["Nombre del proyecto", "Nombre del servicio"])

        viewModel.updateLocalizer(AppLocalizer(languagePreference: .english, bundle: bundle))

        #expect(viewModel.templates.first?.name == "Docker Service")
        #expect(viewModel.templates.first?.summary == "Creates a minimal local service with Docker assets.")
        #expect(viewModel.selectedVariables.map(\.prompt) == ["Project name", "Service name"])
    }

    @Test("Spanish localizer translates the default destination folder")
    func spanishLocalizerTranslatesDefaultDestinationFolder() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let english = AppLocalizer(languagePreference: .english, bundle: bundle)
        let viewModel = ProjectTemplatePanelViewModel(
            registry: ProjectTemplateRegistry(directories: []),
            destinationRootURL: root.appendingPathComponent("output", isDirectory: true),
            localizer: spanish
        )

        #expect(viewModel.destinationName == "NuevoProyecto")

        viewModel.updateLocalizer(english)

        #expect(viewModel.destinationName == "NewProject")

        viewModel.destinationName = "MiHerramienta"
        viewModel.updateLocalizer(spanish)

        #expect(viewModel.destinationName == "MiHerramienta")
    }

    @Test("Spanish localizer pluralizes template row variable counts")
    func spanishLocalizerPluralizesTemplateRowVariableCounts() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let english = AppLocalizer(languagePreference: .english, bundle: bundle)
        let oneVariable = ProjectTemplatePresentation(
            id: "one",
            name: "One",
            summary: "",
            source: .builtIn,
            variableCount: 1
        )
        let manyVariables = ProjectTemplatePresentation(
            id: "many",
            name: "Many",
            summary: "",
            source: .builtIn,
            variableCount: 2
        )

        #expect(oneVariable.localizedRowDetail(using: spanish) == "incluida - 1 variable")
        #expect(manyVariables.localizedRowDetail(using: spanish) == "incluida - 2 variables")
        #expect(oneVariable.localizedRowDetail(using: english) == "built-in - 1 var")
        #expect(manyVariables.localizedRowDetail(using: english) == "built-in - 2 vars")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-template-panel-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }

    private func writeTemplate(
        id: String,
        name: String,
        summary: String,
        variables: [ProjectTemplateVariable] = [
            ProjectTemplateVariable(name: "project_name", prompt: "Project name", defaultValue: "Demo"),
            ProjectTemplateVariable(name: "module_name", prompt: "Module name", defaultValue: "Demo"),
        ],
        files: [String: String] = ["README.md": "# {{project_name}}\n"],
        hooks: ProjectTemplateHooks = ProjectTemplateHooks(),
        in root: URL
    ) throws {
        let directory = root.appendingPathComponent(id, isDirectory: true)
        let filesRoot = directory.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: filesRoot, withIntermediateDirectories: true)
        let manifest = ProjectTemplateManifest(
            id: id,
            name: name,
            description: summary,
            variables: variables,
            hooks: hooks
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("template.json"))
        for (relativePath, content) in files {
            let fileURL = filesRoot.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
