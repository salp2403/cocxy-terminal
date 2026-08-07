// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectAuroraRegistrySwiftTestingTests.swift - Registry-backed Aurora behavior.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Project registry Aurora integration", .serialized)
struct ProjectAuroraRegistrySwiftTestingTests {
    @Test("project live in another window reaches Aurora with alias and pin state")
    func crossWindowLiveProjectProjection() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let root = sandbox.appendingPathComponent("product", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let registry = ProjectRegistry(store: ProjectRegistryStore(
            fileURL: sandbox.appendingPathComponent("registry.json")
        ))
        let descriptor = ProjectDescriptor(
            id: ProjectID(rootURL: root),
            rootURL: root,
            automaticName: "product",
            displayName: "product",
            parent: nil
        )
        try registry.recordOpen(descriptor)
        try registry.setPinned(true, projectID: descriptor.groupingID)

        let tabManager = TabManager()
        let store = AgentStatePerSurfaceStore()
        let controller = AuroraChromeController(
            tabManager: tabManager,
            store: store,
            projectResolver: CachedProjectResolver(),
            projectRegistry: registry
        )
        controller.workspaceTitlesProvider = { [root.path: "Product"] }
        controller.projectLiveIDsProvider = { [descriptor.groupingID.rawValue] }
        controller.projectAvailabilityProvider = { $0 == root }
        controller.beginObservingDomain()

        let project = try #require(controller.projects.first {
            $0.id == descriptor.groupingID.rawValue
        })
        #expect(project.name == "Product")
        #expect(project.isPinned)
        #expect(project.isLive)
        #expect(project.isAvailable)
    }

    @Test("registry load failure reaches Aurora as unavailable state")
    func registryFailureProjection() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let registryURL = sandbox.appendingPathComponent("registry.json")
        let redirectedURL = sandbox.appendingPathComponent("redirected.json")
        try Data("[]".utf8).write(to: redirectedURL)
        try FileManager.default.createSymbolicLink(
            at: registryURL,
            withDestinationURL: redirectedURL
        )
        let registry = ProjectRegistry(store: ProjectRegistryStore(fileURL: registryURL))
        let tabManager = TabManager()
        let store = AgentStatePerSurfaceStore()
        let controller = AuroraChromeController(
            tabManager: tabManager,
            store: store,
            projectRegistry: registry
        )

        controller.beginObservingDomain()

        #expect(controller.projectRegistryErrorDescription != nil)
        #expect(controller.projects.isEmpty)
    }

    @Test("registry recovery reaches Aurora as a localized nonblocking warning")
    func registryRecoveryProjection() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let registryURL = sandbox.appendingPathComponent("registry.json")
        try Data(#"[{"id":"/tmp/valid-project"},"invalid"]"#.utf8)
            .write(to: registryURL)
        let registry = ProjectRegistry(store: ProjectRegistryStore(fileURL: registryURL))
        let tabManager = TabManager()
        let store = AgentStatePerSurfaceStore()
        let controller = AuroraChromeController(
            tabManager: tabManager,
            store: store,
            projectRegistry: registry
        )

        controller.beginObservingDomain()

        let diagnostic = try #require(controller.projectRegistryRecoveryDiagnostic)
        #expect(diagnostic.discardedRecordCount == 1)
        #expect(controller.projectRegistryErrorDescription == nil)
        #expect(controller.projects.count == 1)
        #expect(controller.projects.first?.name == "valid-project")
        #expect(
            Design.AuroraProjectRegistrySection.localizedRecoveryMessage(
                count: diagnostic.discardedRecordCount,
                using: AppLocalizer(languagePreference: .english)
            )
                == "Some project metadata could not be read. Cocxy saved the rejected records (1) in a private recovery file."
        )
    }

    @Test("registry recovery warning renders localized text in the mounted sidebar")
    func registryRecoveryRendersInSidebarSurface() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let registryURL = sandbox.appendingPathComponent("registry.json")
        try Data(#"[{"id":"/tmp/valid-project"},"invalid"]"#.utf8)
            .write(to: registryURL)
        let registry = ProjectRegistry(store: ProjectRegistryStore(fileURL: registryURL))
        let tabManager = TabManager()
        let store = AgentStatePerSurfaceStore()
        let controller = AuroraChromeController(
            tabManager: tabManager,
            store: store,
            projectRegistry: registry
        )
        let localizationBundle = try #require(Bundle(url:
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/Localization", isDirectory: true)
        ))
        controller.localizer = AppLocalizer(
            languagePreference: .spanish,
            bundle: localizationBundle
        )
        controller.beginObservingDomain()
        let diagnostic = try #require(controller.projectRegistryRecoveryDiagnostic)
        #expect(diagnostic.discardedRecordCount == 1)
        let expectedMessage = "No se pudieron leer algunos metadatos de proyectos. Cocxy guardó los registros rechazados (1) en un archivo privado de recuperación."
        let sidebar = AuroraSidebarHost(controller: controller).makeSidebarView()
        let sidebarSurfaceStrings = renderedViewStrings(sidebar.body)

        #expect(sidebar.projectRegistryRecoveryMessage == expectedMessage)
        #expect(sidebarSurfaceStrings.contains(expectedMessage))
    }

    private func makeSandbox() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectAuroraRegistry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return ProjectPathCanonicalizer.canonicalURL(url)
    }
}

private func renderedViewStrings(
    _ value: Any,
    depth: Int = 0
) -> [String] {
    if let string = value as? String { return [string] }
    guard depth < 32 else { return [] }
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle != .class else { return [] }
    return mirror.children.flatMap {
        renderedViewStrings($0.value, depth: depth + 1)
    }
}
