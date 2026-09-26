// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Project identity in Aurora", .serialized)
struct ProjectAuroraIntegrationSwiftTestingTests {
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

    private final class StubProjectResolver: ProjectResolving {
        var descriptors: [String: ProjectDescriptor]
        private(set) var invalidatedPaths: [String] = []

        init(descriptors: [String: ProjectDescriptor]) {
            self.descriptors = descriptors
        }

        func resolveProject(for directory: URL) -> ProjectDescriptor {
            if let descriptor = descriptors[directory.standardizedFileURL.path] {
                return descriptor
            }
            let root = directory.standardizedFileURL
            let name = ProjectDescriptor.automaticName(for: root)
            return ProjectDescriptor(
                id: ProjectID(rootURL: root),
                rootURL: root,
                automaticName: name,
                displayName: name,
                parent: nil
            )
        }

        func invalidate(directory: URL) {
            invalidatedPaths.append(directory.standardizedFileURL.path)
        }

        func invalidateAll() {
            invalidatedPaths.append("*")
        }
    }

    private final class StubGitInfoProvider: GitInfoProviding, @unchecked Sendable {
        let branches: [String: String]

        init(branches: [String: String]) {
            self.branches = branches
        }

        func currentBranch(at directory: URL) -> String? {
            branches[directory.standardizedFileURL.path]
        }

        func isGitRepository(at directory: URL) -> Bool {
            branches[directory.standardizedFileURL.path] != nil
        }

        func observeBranch(
            at directory: URL,
            handler: @escaping @Sendable (String?) -> Void
        ) -> AnyCancellable {
            handler(currentBranch(at: directory))
            return AnyCancellable {}
        }
    }

    @Test("worktree session folds under origin and retains its own branch")
    func sourceAndAdapterPreserveOriginAndChildMetadata() {
        let origin = URL(fileURLWithPath: "/repo/product", isDirectory: true)
        let child = URL(fileURLWithPath: "/tmp/product-feature", isDirectory: true)
        let outside = URL(fileURLWithPath: "/tmp/unrelated-project", isDirectory: true)
        let childID = ProjectID(rootURL: child)
        let originID = ProjectID(rootURL: origin)
        let descriptor = ProjectDescriptor(
            id: childID,
            rootURL: child,
            automaticName: "product-feature",
            displayName: "product-feature",
            parent: originID
        )
        let resolver = StubProjectResolver(descriptors: [child.path: descriptor])
        let git = StubGitInfoProvider(branches: [origin.path: "main"])
        let tab = Tab(
            title: "Feature",
            workingDirectory: outside,
            gitBranch: "feature/search",
            worktreeID: "product-feature",
            worktreeRoot: child,
            worktreeOriginRepo: origin,
            worktreeBranch: "feature/search"
        )

        let sources = AuroraSourceBuilder.buildSources(
            tabs: [tab],
            surfaceIDsByTab: [:],
            store: AgentStatePerSurfaceStore(),
            projectResolver: resolver,
            gitInfoProvider: git,
            workspaceTitlesByIdentity: [
                childID.rawValue: "Legacy Product",
                originID.rawValue: "Current Product",
            ]
        )
        let source = sources[0]
        let project = Design.AuroraWorkspaceAdapter.workspaces(from: sources)[0]

        #expect(source.workspaceGroup == originID.rawValue)
        #expect(source.workspaceRootPath == origin.path)
        #expect(source.workspaceTitle == "Current Product")
        #expect(source.workspaceBranch == "main")
        #expect(source.branch == "feature/search")
        #expect(project.id == originID.rawValue)
        #expect(project.name == "Current Product")
        #expect(project.branch == "main")
        #expect(project.sessions[0].branch == "feature/search")
        #expect(project.sessions[0].notesWorkspaceID == originID.storageKey)
        #expect(project.notesWorkspaceIDs == [originID.storageKey])

        let tabManager = TabManager(gitInfoProvider: git)
        let liveTabID = tabManager.tabs[0].id
        tabManager.updateTab(id: liveTabID) { liveTab in
            liveTab.workingDirectory = outside
            liveTab.worktreeRoot = child
        }
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            tabManager: tabManager,
            gitInfoProvider: git,
            projectResolver: resolver
        )
        #expect(controller.currentNotesWorkingDirectory() == origin.standardizedFileURL)
        #expect(controller.tabForNotesWorkspace(rawID: originID.storageKey)?.id == liveTabID)
        #expect(controller.tabForNotesWorkspace(rawID: childID.storageKey) == nil)
    }

    @Test("a symlinked worktree migrates published and development note identities")
    func worktreeNotesMigrateBeforeSidebarAndOverlayLoads() async throws {
        let caches = try #require(
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        )
        let sandbox = caches
            .appendingPathComponent("ProjectNotesMigration-\(UUID().uuidString)", isDirectory: true)
        let storageRoot = sandbox.appendingPathComponent("notes", isDirectory: true)
        let origin = sandbox.appendingPathComponent("origin", isDirectory: true)
        let child = sandbox.appendingPathComponent("worktree", isDirectory: true)
        let childAlias = sandbox.appendingPathComponent("worktree-alias", isDirectory: true)
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: child.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: childAlias,
            withDestinationURL: child
        )
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let childID = ProjectID(rootURL: child)
        let originID = ProjectID(rootURL: origin)
        let descriptor = ProjectDescriptor(
            id: childID,
            rootURL: child,
            automaticName: "worktree",
            displayName: "worktree",
            parent: originID
        )
        let resolver = StubProjectResolver(descriptors: [childAlias.path: descriptor])
        let git = StubGitInfoProvider(branches: [
            origin.path: "main",
            childAlias.path: "feature/notes",
        ])
        let tabManager = TabManager(gitInfoProvider: git)
        let tabID = try #require(tabManager.tabs.first?.id)
        tabManager.updateTab(id: tabID) { tab in
            tab.workingDirectory = childAlias
            tab.worktreeRoot = childAlias
        }

        let provider = InMemoryConfigProvider(content: """
        [notes]
        enabled = true
        storage-dir = "\(storageRoot.path)"
        format = "markdown"
        """)
        let configService = ConfigService(fileProvider: provider)
        try configService.reload()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService,
            tabManager: tabManager,
            gitInfoProvider: git,
            projectResolver: resolver
        )
        let publishedLegacyID = NoteWorkspaceID(workspaceRoot: childAlias.standardizedFileURL)
        let developmentLegacyID = NoteWorkspaceID(
            workspaceRoot: childAlias.resolvingSymlinksInPath()
        )
        let canonicalID = NoteWorkspaceID(workspaceRoot: origin)
        #expect(publishedLegacyID != developmentLegacyID)
        let seedStore = NoteStore(storageRoot: storageRoot, format: .markdown)
        let first = try await seedStore.create(
            in: publishedLegacyID,
            body: "# Published worktree note"
        )
        _ = try await seedStore.create(
            in: developmentLegacyID,
            body: "# Development worktree note"
        )

        let summaries = await controller.fetchAuroraNotesSummaries(for: [canonicalID.rawValue])
        let viewModel = controller.resolveNotesViewModel(config: configService.current.notes)
        await controller.loadNotesForVisibleTab(using: viewModel)
        controller.isNotesVisible = true
        controller.openNote(workspaceIDRaw: canonicalID.rawValue, noteIDRaw: first.id.uuidString)

        #expect(summaries[canonicalID.rawValue]?.count == 2)
        #expect(controller.tabForNotesWorkspace(rawID: canonicalID.rawValue)?.id == tabID)
        #expect(viewModel.workspace?.workspaceID == canonicalID)
        #expect(viewModel.notes.count == 2)
        #expect(viewModel.selectedNote?.id == first.id)
        #expect(try await seedStore.notes(in: publishedLegacyID).isEmpty)
        #expect(try await seedStore.notes(in: developmentLegacyID).isEmpty)
    }

    @Test("forgetting a non-git project root does not change its tab's notes workspace")
    func notesIdentitySurvivesRegisteredRootForget() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectNotesForget-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let projectRoot = sandbox.appendingPathComponent("project", isDirectory: true)
        let tabDirectory = projectRoot.appendingPathComponent("Sources/Feature", isDirectory: true)
        let storageRoot = sandbox.appendingPathComponent("notes", isDirectory: true)
        let registryURL = sandbox.appendingPathComponent("registry.json")
        try FileManager.default.createDirectory(at: tabDirectory, withIntermediateDirectories: true)

        let projectID = ProjectID(rootURL: projectRoot)
        let projectName = ProjectDescriptor.automaticName(for: projectRoot)
        let registry = ProjectRegistry(store: ProjectRegistryStore(fileURL: registryURL))
        try registry.recordOpen(ProjectDescriptor(
            id: projectID,
            rootURL: ProjectPathCanonicalizer.canonicalURL(projectRoot),
            automaticName: projectName,
            displayName: projectName,
            parent: nil
        ))
        let resolver = CachedProjectResolver(projectRegistry: registry, cacheTTL: 60)

        let provider = InMemoryConfigProvider(content: """
        [notes]
        enabled = true
        storage-dir = "\(storageRoot.path)"
        format = "markdown"
        """)
        let configService = ConfigService(fileProvider: provider)
        try configService.reload()
        let tabManager = TabManager()
        let tabID = try #require(tabManager.tabs.first?.id)
        tabManager.updateTab(id: tabID) { tab in
            tab.workingDirectory = tabDirectory
            tab.worktreeRoot = nil
            tab.worktreeOriginRepo = nil
        }
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService,
            tabManager: tabManager,
            projectResolver: resolver
        )
        let canonicalTabRoot = ProjectPathCanonicalizer.canonicalURL(tabDirectory)
        let workspaceID = NoteWorkspaceID(workspaceRoot: canonicalTabRoot)
        let seedStore = NoteStore(storageRoot: storageRoot, format: .markdown)
        let note = try await seedStore.create(in: workspaceID, body: "# Stable after forget")

        let beforeSource = try #require(AuroraSourceBuilder.buildSources(
            tabs: tabManager.tabs,
            surfaceIDsByTab: [:],
            store: AgentStatePerSurfaceStore(),
            projectResolver: resolver
        ).first)
        #expect(beforeSource.workspaceGroup == projectID.rawValue)
        #expect(beforeSource.workspaceRootPath == canonicalTabRoot.path)

        let viewModel = controller.resolveNotesViewModel(config: configService.current.notes)
        await controller.loadNotesForVisibleTab(using: viewModel)
        #expect(viewModel.workspace?.workspaceID == workspaceID)
        #expect(viewModel.notes.map(\.id) == [note.id])

        try registry.forget(projectID)
        #expect(resolver.resolveProject(for: tabDirectory).id == ProjectID(rootURL: tabDirectory))
        await controller.loadNotesForVisibleTab(using: viewModel)
        let afterSource = try #require(AuroraSourceBuilder.buildSources(
            tabs: tabManager.tabs,
            surfaceIDsByTab: [:],
            store: AgentStatePerSurfaceStore(),
            projectResolver: resolver
        ).first)

        #expect(afterSource.workspaceRootPath == beforeSource.workspaceRootPath)
        #expect(viewModel.workspace?.workspaceID == workspaceID)
        #expect(viewModel.notes.map(\.id) == [note.id])
    }

    @Test("two non-git tabs under one registered root expose both notes collections in one sidebar section")
    func registeredRootAggregatesNotesFromEveryTab() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectNotesAggregation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let home = sandbox.appendingPathComponent("home", isDirectory: true)
        let registeredRoot = home.appendingPathComponent("Documents/work", isDirectory: true)
        let firstRoot = registeredRoot.appendingPathComponent("notes-a", isDirectory: true)
        let secondRoot = registeredRoot.appendingPathComponent("notes-b", isDirectory: true)
        let storageRoot = sandbox.appendingPathComponent("notes", isDirectory: true)
        let registryURL = sandbox.appendingPathComponent("projects.json")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)

        let registry = ProjectRegistry(store: ProjectRegistryStore(fileURL: registryURL))
        let registeredID = ProjectID(rootURL: registeredRoot)
        let registeredName = ProjectDescriptor.automaticName(for: registeredRoot)
        try registry.recordOpen(ProjectDescriptor(
            id: registeredID,
            rootURL: ProjectPathCanonicalizer.canonicalURL(registeredRoot),
            automaticName: registeredName,
            displayName: registeredName,
            parent: nil
        ))
        let resolver = CachedProjectResolver(
            projectRegistry: registry,
            homeDirectory: home
        )
        let tabManager = TabManager()
        let firstTabID = try #require(tabManager.tabs.first?.id)
        tabManager.updateTab(id: firstTabID) { tab in
            tab.workingDirectory = firstRoot
        }
        let secondTab = tabManager.addTab(workingDirectory: secondRoot)

        let provider = InMemoryConfigProvider(content: """
        [notes]
        enabled = true
        storage-dir = "\(storageRoot.path)"
        format = "markdown"
        """)
        let configService = ConfigService(fileProvider: provider)
        try configService.reload()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService,
            tabManager: tabManager,
            projectRegistry: registry,
            projectResolver: resolver
        )
        let firstID = NoteWorkspaceID(workspaceRoot: firstRoot)
        let secondID = NoteWorkspaceID(workspaceRoot: secondRoot)
        let store = NoteStore(storageRoot: storageRoot, format: .markdown)
        let firstNote = try await store.create(in: firstID, body: "# First root")
        let secondNote = try await store.create(in: secondID, body: "# Second root")

        let sources = AuroraSourceBuilder.buildSources(
            tabs: tabManager.tabs,
            surfaceIDsByTab: [:],
            store: AgentStatePerSurfaceStore(),
            projectResolver: resolver
        )
        let workspaces = Design.AuroraWorkspaceAdapter.workspaces(from: sources)
        let workspace = try #require(workspaces.first)
        let summaries = await controller.fetchAuroraNotesSummaries(
            for: Set(workspace.notesWorkspaceIDs)
        )
        let aggregate = try #require(workspace.aggregatedNotesSummary(from: summaries))

        #expect(workspaces.count == 1)
        #expect(workspace.id == registeredID.rawValue)
        #expect(Set(workspace.notesWorkspaceIDs) == Set([firstID.rawValue, secondID.rawValue]))
        #expect(aggregate.count == 2)
        #expect(Set(aggregate.recentNotes.map { $0.id }) == Set([
            firstNote.id.uuidString,
            secondNote.id.uuidString,
        ]))
        #expect(Set(aggregate.recentNotes.map { $0.workspaceID }) == Set([
            firstID.rawValue,
            secondID.rawValue,
        ]))
        #expect(controller.tabForNotesWorkspace(rawID: firstID.rawValue)?.id == firstTabID)
        #expect(controller.tabForNotesWorkspace(rawID: secondID.rawValue)?.id == secondTab.id)

        let sidebar = Design.AuroraSidebarView(
            workspaces: workspaces,
            activeSessionID: nil,
            notesByWorkspace: summaries,
            onTogglePalette: {},
            onCreateTab: {},
            onActivateSession: { _ in },
            onOpenNote: { _, _ in }
        )
        let renderedNotes = reflectedStrings(sidebar.notesSection(for: workspace))
        #expect(renderedNotes.contains("First root"))
        #expect(renderedNotes.contains("Second root"))
    }

    @Test("a symlinked non-worktree migrates when one legacy identity is already canonical")
    func symlinkNotesMigrationSkipsOnlyCanonicalCandidate() async throws {
        let caches = try #require(
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        )
        let sandbox = caches
            .appendingPathComponent("ProjectNotesSymlink-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let physical = sandbox.appendingPathComponent("physical", isDirectory: true)
        let alias = sandbox.appendingPathComponent("alias", isDirectory: true)
        let storageRoot = sandbox.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: physical, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: physical)

        let provider = InMemoryConfigProvider(content: """
        [notes]
        enabled = true
        storage-dir = "\(storageRoot.path)"
        format = "markdown"
        """)
        let configService = ConfigService(fileProvider: provider)
        try configService.reload()
        let tabManager = TabManager()
        let tabID = try #require(tabManager.tabs.first?.id)
        tabManager.updateTab(id: tabID) { tab in
            tab.workingDirectory = alias
            tab.worktreeRoot = nil
            tab.worktreeOriginRepo = nil
        }
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService,
            tabManager: tabManager,
            projectResolver: CachedProjectResolver()
        )
        let canonicalRoot = ProjectPathCanonicalizer.canonicalURL(alias)
        let canonicalID = NoteWorkspaceID(workspaceRoot: canonicalRoot)
        let publishedLegacyID = NoteWorkspaceID(workspaceRoot: alias.standardizedFileURL)
        let developmentLegacyID = NoteWorkspaceID(
            workspaceRoot: ProjectPathCanonicalizer.canonicalURL(alias)
        )
        #expect(publishedLegacyID != canonicalID)
        #expect(developmentLegacyID == canonicalID)
        let seedStore = NoteStore(storageRoot: storageRoot, format: .markdown)
        let note = try await seedStore.create(
            in: publishedLegacyID,
            body: "# Published symlink note"
        )

        let summaries = await controller.fetchAuroraNotesSummaries(for: [canonicalID.rawValue])
        let viewModel = controller.resolveNotesViewModel(config: configService.current.notes)
        await controller.loadNotesForVisibleTab(using: viewModel)

        #expect(summaries[canonicalID.rawValue]?.count == 1)
        #expect(viewModel.workspace?.workspaceID == canonicalID)
        #expect(viewModel.notes.map(\.id) == [note.id])
        #expect(try await seedStore.notes(in: publishedLegacyID).isEmpty)
    }

    @Test("workspace rename migrates every open worktree alias to the folded identity")
    func renameMigratesLegacyWorktreeAlias() throws {
        let suiteName = "ProjectAuroraRenameTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let titleStore = AuroraWorkspaceTitleStore(defaults: defaults, storageKey: "titles")
        let origin = URL(fileURLWithPath: "/repo/product", isDirectory: true)
        let child = URL(fileURLWithPath: "/tmp/product-feature", isDirectory: true)
        let originID = ProjectID(rootURL: origin)
        let childID = ProjectID(rootURL: child)
        let resolver = StubProjectResolver(descriptors: [
            origin.path: ProjectDescriptor(
                id: originID,
                rootURL: origin,
                automaticName: "product",
                displayName: "product",
                parent: nil
            ),
            child.path: ProjectDescriptor(
                id: childID,
                rootURL: child,
                automaticName: "product-feature",
                displayName: "product-feature",
                parent: originID
            ),
        ])
        let git = StubGitInfoProvider(branches: [origin.path: "main", child.path: "feature/search"])
        let tabManager = TabManager(gitInfoProvider: git)
        let firstID = try #require(tabManager.tabs.first?.id)
        tabManager.updateTab(id: firstID) { tab in
            tab.workingDirectory = origin
            tab.gitBranch = "main"
        }
        _ = tabManager.addTab(workingDirectory: child)
        titleStore.setTitle("Old Feature Alias", for: childID.rawValue)
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            tabManager: tabManager,
            auroraWorkspaceTitleStore: titleStore,
            gitInfoProvider: git,
            projectResolver: resolver
        )

        controller.applyAuroraWorkspaceRename(
            workspaceID: originID.rawValue,
            newTitle: "Product Suite"
        )

        #expect(titleStore.title(for: originID.rawValue) == "Product Suite")
        #expect(titleStore.snapshot[childID.rawValue] == nil)
        #expect(tabManager.tabs.allSatisfy { $0.workspaceCustomTitle == nil })
    }

    @Test("canonical alias migration includes symlink identities from every live directory")
    func aliasMigrationIncludesSymlinkIdentities() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectAliasTests-\(UUID().uuidString)", isDirectory: true)
        let physical = sandbox.appendingPathComponent("physical", isDirectory: true)
        let linked = sandbox.appendingPathComponent("linked", isDirectory: true)
        let nested = linked.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(
            at: physical.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: physical)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let resolver = CachedProjectResolver()
        let projectID = resolver.resolveProject(for: physical).groupingID

        let aliases = ProjectAliasMigrationPlanner.legacyIdentities(
            for: projectID,
            directories: [physical, nested],
            requestedDirectory: linked,
            projectResolver: resolver
        )

        var expectedAliases = Set([linked.standardizedFileURL.path])
        if physical.standardizedFileURL.path != projectID.rawValue {
            expectedAliases.insert(physical.standardizedFileURL.path)
        }
        #expect(aliases == expectedAliases)
    }
}

private func reflectedStrings(_ value: Any, depth: Int = 0) -> [String] {
    if let string = value as? String { return [string] }
    guard depth < 32 else { return [] }
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle != .class else { return [] }
    return mirror.children.flatMap { reflectedStrings($0.value, depth: depth + 1) }
}
