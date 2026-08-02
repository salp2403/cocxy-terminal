// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Project registry", .serialized)
struct ProjectRegistrySwiftTestingTests {
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
