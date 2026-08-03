// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Project identity in Aurora", .serialized)
struct ProjectAuroraIntegrationSwiftTestingTests {
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
            workingDirectory: child,
            gitBranch: "feature/search"
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

        #expect(aliases == Set([linked.standardizedFileURL.path]))
    }
}
