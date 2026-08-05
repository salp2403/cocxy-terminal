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
        #expect(project.notesWorkspaceID == originID.storageKey)

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

    @Test("a symlinked worktree migrates canonical legacy notes into the folded sidebar identity")
    func worktreeNotesMigrateBeforeSidebarAndOverlayLoads() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectNotesMigration-\(UUID().uuidString)", isDirectory: true)
        let storageRoot = sandbox.appendingPathComponent("notes", isDirectory: true)
        let origin = sandbox.appendingPathComponent("origin", isDirectory: true)
        let child = sandbox.appendingPathComponent("worktree", isDirectory: true)
        let childAlias = sandbox.appendingPathComponent("worktree-alias", isDirectory: true)
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
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
        let legacyID = NoteWorkspaceID(
            workspaceRoot: ProjectPathCanonicalizer.canonicalURL(childAlias)
        )
        let canonicalID = NoteWorkspaceID(workspaceRoot: origin)
        let seedStore = NoteStore(storageRoot: storageRoot, format: .markdown)
        let first = try await seedStore.create(in: legacyID, body: "# Worktree note")
        _ = try await seedStore.create(in: legacyID, body: "# Another note")

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
        #expect(try await seedStore.notes(in: legacyID).isEmpty)
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
