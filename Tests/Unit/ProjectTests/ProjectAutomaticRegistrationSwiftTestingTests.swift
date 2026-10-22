// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectAutomaticRegistrationSwiftTestingTests.swift - Which visited folders become projects.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Automatic project registration", .serialized)
struct ProjectAutomaticRegistrationSwiftTestingTests {
    private final class InMemoryConfigProvider: ConfigFileProviding, @unchecked Sendable {
        private var content: String?

        init(content: String?) {
            self.content = content
        }

        func readConfigFile() -> String? { content }

        func writeConfigFile(_ content: String) throws {
            self.content = content
        }
    }

    @Test("changing into folders without a repository under home registers nothing and keeps their notes visible")
    func plainHomeFoldersStayOutOfTheRegistry() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectAutoRegistration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let home = sandbox.appendingPathComponent("home", isDirectory: true)
        let firstFolder = home.appendingPathComponent("Documents/notes-a", isDirectory: true)
        let secondFolder = home.appendingPathComponent("Downloads/notes-b", isDirectory: true)
        let repository = home.appendingPathComponent("Code/app", isDirectory: true)
        let repositoryChild = repository.appendingPathComponent("Sources", isDirectory: true)
        let storageRoot = sandbox.appendingPathComponent("notes", isDirectory: true)
        let registryURL = sandbox.appendingPathComponent("registry.json")
        for directory in [firstFolder, secondFolder, repositoryChild] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )

        let registry = ProjectRegistry(store: ProjectRegistryStore(fileURL: registryURL))
        let resolver = CachedProjectResolver(
            projectRegistry: registry,
            rootResolver: GitAncestorWorkspaceRootResolver(homeDirectory: home),
            homeDirectory: home
        )
        let tabManager = TabManager()
        let firstTabID = try #require(tabManager.tabs.first?.id)
        tabManager.updateTab(id: firstTabID) { $0.workingDirectory = home }
        let secondTab = tabManager.addTab(workingDirectory: home)
        let configService = ConfigService(fileProvider: InMemoryConfigProvider(content: """
        [notes]
        enabled = true
        storage-dir = "\(storageRoot.path)"
        format = "markdown"
        """))
        try configService.reload()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService,
            tabManager: tabManager,
            projectRegistry: registry,
            projectResolver: resolver
        )

        controller.observeProjectDirectory(home)
        controller.handleCurrentDirectoryChange(firstFolder, tabID: firstTabID, surfaceID: nil)
        controller.handleCurrentDirectoryChange(secondFolder, tabID: secondTab.id, surfaceID: nil)

        #expect(registry.records.isEmpty)
        #expect(try ProjectRegistryStore(fileURL: registryURL).load().isEmpty)

        let store = NoteStore(storageRoot: storageRoot, format: .markdown)
        let firstNote = try await store.create(
            in: NoteWorkspaceID(workspaceRoot: firstFolder),
            body: "# First folder"
        )
        let secondNote = try await store.create(
            in: NoteWorkspaceID(workspaceRoot: secondFolder),
            body: "# Second folder"
        )
        let workspaces = Design.AuroraWorkspaceAdapter.workspaces(
            from: AuroraSourceBuilder.buildSources(
                tabs: tabManager.tabs,
                surfaceIDsByTab: [:],
                store: AgentStatePerSurfaceStore(),
                projectResolver: resolver
            )
        )
        let summaries = await controller.fetchAuroraNotesSummaries(
            for: Set(workspaces.flatMap(\.notesWorkspaceIDs))
        )
        let visibleNoteIDs = Set(workspaces.flatMap {
            $0.aggregatedNotesSummary(from: summaries)?.recentNotes.map(\.id) ?? []
        })
        #expect(visibleNoteIDs == Set([firstNote.id.uuidString, secondNote.id.uuidString]))

        controller.handleCurrentDirectoryChange(repositoryChild, tabID: secondTab.id, surfaceID: nil)

        #expect(registry.records.map(\.id) == [ProjectID(rootURL: repository)])
    }

    @Test("changing into a subfolder of a registered folder without a repository counts the visit")
    func registeredPlainFolderCountsVisitsFromSubfolders() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectRegisteredPlainFolder-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let home = sandbox.appendingPathComponent("home", isDirectory: true)
        let workFolder = home.appendingPathComponent("Documents/work", isDirectory: true)
        let child = workFolder.appendingPathComponent("drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let registry = ProjectRegistry(store: ProjectRegistryStore(
            fileURL: sandbox.appendingPathComponent("registry.json")
        ))
        let resolver = CachedProjectResolver(
            projectRegistry: registry,
            rootResolver: GitAncestorWorkspaceRootResolver(homeDirectory: home),
            homeDirectory: home
        )
        try registry.recordOpen(resolver.resolveProject(for: workFolder), incrementOpenCount: false)
        let tabManager = TabManager()
        let tabID = try #require(tabManager.tabs.first?.id)
        tabManager.updateTab(id: tabID) { $0.workingDirectory = home }
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            tabManager: tabManager,
            projectRegistry: registry,
            projectResolver: resolver,
            deferContentSetup: true
        )

        controller.handleCurrentDirectoryChange(child, tabID: tabID, surfaceID: nil)

        #expect(registry.records.map(\.id) == [ProjectID(rootURL: workFolder)])
        #expect(registry.records.first?.openCount == 1)
    }

    @Test("Open Project registers a folder without a repository without counting a visit")
    func openProjectRegistersPlainFolder() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectOpenPlainFolder-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let folder = sandbox.appendingPathComponent("plain-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let registry = ProjectRegistry(store: ProjectRegistryStore(
            fileURL: sandbox.appendingPathComponent("registry.json")
        ))
        let appDelegate = AppDelegate(projectIdentityServices: ProjectIdentityServices(registry: registry))
        #expect(appDelegate.projectResolver.resolveProject(for: folder).rootSource == .workingDirectory)

        let projectID = appDelegate.registerChosenProjectFolder(folder)

        #expect(projectID == ProjectID(rootURL: folder))
        #expect(registry.records.map(\.id) == [projectID])
        #expect(registry.records.first?.openCount == 0)
    }
}
