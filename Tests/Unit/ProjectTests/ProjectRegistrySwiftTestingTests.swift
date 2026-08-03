// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Project registry", .serialized)
struct ProjectRegistrySwiftTestingTests {
    private final class RootResolver: AuroraWorkspaceRootResolver, @unchecked Sendable {
        let roots: [String: URL]

        init(roots: [String: URL]) {
            self.roots = roots
        }

        func workspaceRoot(for directory: URL) -> URL? {
            roots[directory.standardizedFileURL.path]
        }
    }

    @Test("legacy records decode optional fields with stable defaults")
    func legacyDecodeDefaults() throws {
        let data = Data(#"[{"id":"/tmp/legacy-project"}]"#.utf8)
        let records = try JSONDecoder().decode([ProjectRecord].self, from: data)
        let record = try #require(records.first)

        #expect(record.id == ProjectID(rawValue: "/tmp/legacy-project"))
        #expect(record.openCount == 0)
        #expect(record.isPinned == false)
        #expect(record.isCollapsed == false)
        #expect(record.accent == nil)
        #expect(record.remoteOrigin == nil)
        #expect(record.tags.isEmpty)
        #expect(record.defaultBaseRef == nil)
        #expect(record.defaultAgents.isEmpty)
    }

    @Test("store writes atomically with owner-only permissions")
    func ownerOnlyPersistence() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let fileURL = sandbox.appendingPathComponent("projects/registry.json")
        let store = ProjectRegistryStore(fileURL: fileURL)
        let record = ProjectRecord(
            id: ProjectID(rawValue: "/tmp/project-a"),
            lastOpenedAt: Date(timeIntervalSince1970: 100),
            openCount: 2,
            isPinned: true
        )

        try store.save([record])

        #expect(try store.load() == [record])
        let fileMode = try #require(
            FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions]
                as? NSNumber
        )
        let directoryMode = try #require(
            FileManager.default.attributesOfItem(
                atPath: fileURL.deletingLastPathComponent().path
            )[.posixPermissions] as? NSNumber
        )
        #expect(fileMode.intValue & 0o777 == 0o600)
        #expect(directoryMode.intValue & 0o777 == 0o700)
    }

    @Test("store rejects symbolic-link roots and destinations")
    func rejectsSymbolicLinks() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let realRoot = sandbox.appendingPathComponent("real", isDirectory: true)
        let linkedRoot = sandbox.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: realRoot)
        let linkedStore = ProjectRegistryStore(
            fileURL: linkedRoot.appendingPathComponent("registry.json")
        )

        #expect(throws: ProjectRegistryStoreError.self) {
            try linkedStore.save([])
        }

        let directFile = realRoot.appendingPathComponent("registry.json")
        let target = realRoot.appendingPathComponent("target.json")
        try Data("[]".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: directFile, withDestinationURL: target)
        #expect(throws: ProjectRegistryStoreError.self) {
            try ProjectRegistryStore(fileURL: directFile).save([])
        }
    }

    @Test("same basenames persist as distinct records")
    func sameBasenamesRemainDistinct() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        var now = Date(timeIntervalSince1970: 200)
        let registry = ProjectRegistry(
            store: ProjectRegistryStore(fileURL: sandbox.appendingPathComponent("registry.json")),
            clock: { now }
        )
        let first = descriptor("/tmp/one/html")
        let second = descriptor("/tmp/two/html")

        try registry.recordOpen(first)
        now.addTimeInterval(1)
        try registry.recordOpen(second)

        #expect(registry.records.count == 2)
        #expect(Set(registry.records.map(\.id)).count == 2)
    }

    @Test("legacy symlink records migrate to one physical project")
    func symlinkRecordsMigrate() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let physical = sandbox.appendingPathComponent("physical", isDirectory: true)
        let link = sandbox.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: physical, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: physical)
        let fileURL = sandbox.appendingPathComponent("registry.json")
        let legacy = """
        [
          {"id":"\(link.path)","openCount":2,"isPinned":true},
          {"id":"\(physical.path)","openCount":3,"tags":["swift"]}
        ]
        """
        try Data(legacy.utf8).write(to: fileURL)

        let store = ProjectRegistryStore(fileURL: fileURL)
        let records = try store.load()

        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.id == ProjectID(rootURL: physical))
        #expect(record.openCount == 3)
        #expect(record.isPinned)
        #expect(record.tags == ["swift"])
        let persisted = try store.load()
        #expect(persisted.map(\.id) == [ProjectID(rootURL: physical)])
    }

    @Test("pin collapse and open count survive reload")
    func mutationsSurviveReload() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let fileURL = sandbox.appendingPathComponent("registry.json")
        let descriptor = descriptor("/tmp/durable-project")
        let registry = ProjectRegistry(
            store: ProjectRegistryStore(fileURL: fileURL),
            clock: { Date(timeIntervalSince1970: 300) }
        )

        try registry.recordOpen(descriptor)
        try registry.recordOpen(descriptor, incrementOpenCount: false)
        try registry.setPinned(true, projectID: descriptor.id)
        try registry.setCollapsed(true, projectID: descriptor.id)

        let reloaded = ProjectRegistry(store: ProjectRegistryStore(fileURL: fileURL))
        let record = try #require(reloaded.record(for: descriptor.id))
        #expect(record.openCount == 1)
        #expect(record.isPinned)
        #expect(record.isCollapsed)
        #expect(record.lastOpenedAt == Date(timeIntervalSince1970: 300))
    }

    @Test("persisted collapse drives the Aurora workspace snapshot")
    func collapseProjectsIntoAurora() throws {
        let source = Design.AuroraSourceTab(
            id: "tab",
            name: "Shell",
            workspaceGroup: "/tmp/project",
            workspaceTitle: nil,
            workspaceDefaultName: "project",
            workspaceBranch: "main",
            branch: "main",
            surfaces: [],
            workingDirectory: "/tmp/project",
            workspaceRootPath: "/tmp/project"
        )

        let workspace = try #require(Design.AuroraWorkspaceAdapter.workspaces(
            from: [source],
            collapsedWorkspaceIDs: ["/tmp/project"]
        ).first)

        #expect(workspace.isCollapsed)
    }

    @Test("directory changes inside one project do not count repeated opens")
    func sameProjectDirectoryChangesAreDeduplicated() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let project = URL(fileURLWithPath: "/tmp/project")
        let first = project.appendingPathComponent("Sources")
        let second = project.appendingPathComponent("Tests")
        let registry = ProjectRegistry(
            store: ProjectRegistryStore(fileURL: sandbox.appendingPathComponent("registry.json"))
        )
        let resolver = CachedProjectResolver(rootResolver: RootResolver(roots: [
            first.path: project,
            second.path: project,
        ]))
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            projectRegistry: registry,
            projectResolver: resolver,
            deferContentSetup: true
        )

        controller.observeProjectDirectory(first)
        controller.observeProjectDirectory(second, previousDirectory: first)

        #expect(registry.records.count == 1)
        #expect(registry.records.first?.openCount == 1)
    }

    @Test("workspace alias persistence publishes a project refresh signal")
    func aliasPublishesRefreshSignal() throws {
        let suiteName = "ProjectAliasSignalTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AuroraWorkspaceTitleStore(defaults: defaults, storageKey: "titles")
        var revisions: [UInt64] = []
        let cancellable = store.$revision.dropFirst().sink { revisions.append($0) }

        store.setTitle("Backend", for: "/tmp/project")

        #expect(revisions == [1])
        _ = cancellable
    }

    @Test("post-commit publisher observes the committed registry snapshot")
    func postCommitPublisherUsesCommittedSnapshot() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let registry = ProjectRegistry(
            store: ProjectRegistryStore(fileURL: sandbox.appendingPathComponent("registry.json"))
        )
        var observed: [[ProjectRecord]] = []
        let cancellable = registry.recordsDidChange.sink { snapshot in
            #expect(registry.records == snapshot)
            observed.append(snapshot)
        }

        try registry.recordOpen(descriptor("/tmp/post-commit"))

        #expect(observed.count == 1)
        #expect(observed.first?.first?.id == ProjectID(rawValue: "/tmp/post-commit"))
        _ = cancellable
    }

    @Test("presentation projects aliases and distinguishes unavailable roots")
    func presentationProjection() {
        let first = ProjectRecord(
            id: ProjectID(rawValue: "/tmp/one/html"),
            lastOpenedAt: Date(timeIntervalSince1970: 10),
            isPinned: true
        )
        let second = ProjectRecord(
            id: ProjectID(rawValue: "/tmp/two/html"),
            lastOpenedAt: Date(timeIntervalSince1970: 9)
        )

        let items = ProjectPresentationBuilder.makeItems(
            records: [first, second],
            aliases: [first.id.rawValue: "Frontend"],
            liveProjectIDs: [first.id.rawValue],
            availability: { $0.path == first.id.rawValue }
        )

        #expect(items.map(\.name) == ["Frontend", "html"])
        #expect(items.map(\.parentPath) == ["/tmp/one", "/tmp/two"])
        #expect(items[0].isPinned)
        #expect(items[0].isLive)
        #expect(items[0].isAvailable)
        #expect(!items[1].isLive)
        #expect(!items[1].isAvailable)
    }

    @Test("encoded records do not claim ownership of aliases")
    func aliasesAreNotPersisted() throws {
        let data = try JSONEncoder().encode(ProjectRecord(id: ProjectID(rawValue: "/tmp/a")))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["alias"] == nil)
        #expect(Set(object.keys) == [
            "id", "lastOpenedAt", "openCount", "isPinned", "isCollapsed",
            "tags", "defaultAgents",
        ])
    }

    @Test("load failure is visible and prevents destructive overwrite")
    func corruptStoreFailsClosed() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let fileURL = sandbox.appendingPathComponent("registry.json")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fileURL)
        let registry = ProjectRegistry(store: ProjectRegistryStore(fileURL: fileURL))

        #expect(registry.persistenceErrorDescription != nil)
        #expect(throws: ProjectRegistryError.self) {
            try registry.recordOpen(descriptor("/tmp/new-project"))
        }
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "not-json")
    }

    private func makeSandbox() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectRegistryTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func descriptor(_ path: String) -> ProjectDescriptor {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let name = ProjectDescriptor.automaticName(for: root)
        return ProjectDescriptor(
            id: ProjectID(rootURL: root),
            rootURL: root,
            automaticName: name,
            displayName: name,
            parent: nil
        )
    }
}
