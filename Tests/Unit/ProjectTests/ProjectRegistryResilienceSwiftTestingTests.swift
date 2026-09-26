// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Project registry resilience", .serialized)
struct ProjectRegistryResilienceSwiftTestingTests {
    @Test("a quarantine prune failure does not block recovery or the repaired registry save")
    func pruneFailureIsBestEffortAfterRecoverySave() throws {
        let sandbox = makeSandbox("PruneFailure")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let registryURL = sandbox.appendingPathComponent("registry.json")
        var staleURLs: [URL] = []
        for index in 0..<ProjectRegistryStore.maximumQuarantineFiles {
            let url = sandbox.appendingPathComponent(
                "registry-quarantine-stale-\(index).json"
            )
            try Data("[]".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(index))],
                ofItemAtPath: url.path
            )
            staleURLs.append(url)
        }
        try Data(#"["invalid",{"id":"/tmp/valid-after-prune"}]"#.utf8)
            .write(to: registryURL)
        let fileManager = PruneFailureFileManager(deniedRemovalURL: staleURLs[0])
        let store = ProjectRegistryStore(fileURL: registryURL, fileManager: fileManager)

        let report = try store.loadReport()

        #expect(report.records.map(\.id) == [ProjectID(rawValue: "/tmp/valid-after-prune")])
        #expect(report.discardedRecordCount == 1)
        #expect(fileManager.deniedRemovalAttemptCount == 1)
        #expect(try ProjectRegistryStore(fileURL: registryURL).load().map(\.id) == [
            ProjectID(rawValue: "/tmp/valid-after-prune"),
        ])
    }

    @Test("a quarantine enumeration failure does not undo registry recovery")
    func pruneEnumerationFailureIsBestEffort() throws {
        let sandbox = makeSandbox("EnumerationFailure")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let registryURL = sandbox.appendingPathComponent("registry.json")
        try Data(#"["invalid",{"id":"/tmp/valid-after-enumeration"}]"#.utf8)
            .write(to: registryURL)
        let fileManager = PruneFailureFileManager(deniedEnumerationURL: sandbox)
        let store = ProjectRegistryStore(fileURL: registryURL, fileManager: fileManager)

        let report = try store.loadReport()

        #expect(report.records.map(\.id) == [
            ProjectID(rawValue: "/tmp/valid-after-enumeration"),
        ])
        #expect(report.discardedRecordCount == 1)
        #expect(fileManager.deniedEnumerationAttemptCount == 1)
        #expect(try ProjectRegistryStore(fileURL: registryURL).load().map(\.id) == [
            ProjectID(rawValue: "/tmp/valid-after-enumeration"),
        ])
    }

    @Test("a read-only permission hardening failure does not hide readable records")
    func readHardeningFailureIsBestEffort() throws {
        let sandbox = makeSandbox("HardeningFailure")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let registryURL = sandbox.appendingPathComponent("registry.json")
        let projectRoot = sandbox.appendingPathComponent("readable", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let projectID = ProjectID(rootURL: projectRoot)
        try JSONSerialization.data(withJSONObject: [["id": projectID.rawValue]])
            .write(to: registryURL)
        let fileManager = PruneFailureFileManager(deniedAttributesURL: sandbox)

        let report = try ProjectRegistryStore(
            fileURL: registryURL,
            fileManager: fileManager
        ).loadReport()

        #expect(report.records.map(\.id) == [projectID])
        #expect(fileManager.deniedAttributesAttemptCount == 1)
    }

    @Test("quarantine retention runs when the repaired registry save fails")
    func retentionRunsAfterSaveFailure() throws {
        let sandbox = makeSandbox("SaveFailure")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let registryURL = sandbox.appendingPathComponent("registry.json")
        try Data(#"["invalid",{"id":"/tmp/valid-before-save-failure"}]"#.utf8)
            .write(to: registryURL)
        for index in 0..<ProjectRegistryStore.maximumQuarantineFiles {
            let url = sandbox.appendingPathComponent("registry-quarantine-old-\(index).json")
            try Data("[]".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(index))],
                ofItemAtPath: url.path
            )
        }
        let deniedPath = ProjectPathCanonicalizer.canonicalURL(registryURL).path
        let store = ProjectRegistryStore(fileURL: registryURL) { data, url in
            if ProjectPathCanonicalizer.canonicalURL(url).path == deniedPath {
                throw CocoaError(.fileWriteNoPermission)
            }
            try data.write(to: url, options: .atomic)
        }

        let report = try store.loadReport()
        #expect(report.repairFailure != nil)
        #expect(report.records.map(\.id) == [ProjectID(rawValue: "/tmp/valid-before-save-failure")])

        let quarantineFiles = try FileManager.default.contentsOfDirectory(
            at: sandbox,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("registry-quarantine-")
                && $0.pathExtension == "json"
        }
        #expect(quarantineFiles.count == ProjectRegistryStore.maximumQuarantineFiles)
    }

    @Test("a directory hardening failure blocks registry writes")
    func writeHardeningFailureFailsClosed() throws {
        let sandbox = makeSandbox("WriteHardening")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let registryURL = sandbox.appendingPathComponent("registry.json")
        let fileManager = PruneFailureFileManager(deniedAttributesURL: sandbox)
        let store = ProjectRegistryStore(fileURL: registryURL, fileManager: fileManager)

        #expect(throws: ProjectRegistryStoreError.self) {
            try store.save([ProjectRecord(id: ProjectID(rawValue: "/tmp/hardened"))])
        }
        #expect(!FileManager.default.fileExists(atPath: registryURL.path))
    }

    @Test("a failed quarantine keeps readable projects without dropping rejected records")
    func quarantineFailureKeepsRecordsReadOnlyUntilRetry() throws {
        let sandbox = makeSandbox("QuarantineFailure")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let registryURL = sandbox.appendingPathComponent("registry.json")
        let original = Data(#"["invalid",{"id":"/tmp/kept-project"}]"#.utf8)
        try original.write(to: registryURL)
        let writes = WriteGate(deniedNamePrefix: "registry-quarantine-")
        let registry = ProjectRegistry(store: writes.store(fileURL: registryURL))

        #expect(registry.records.map(\.id) == [ProjectID(rawValue: "/tmp/kept-project")])
        #expect(registry.persistenceErrorDescription != nil)
        #expect(throws: ProjectRegistryError.self) {
            try registry.setPinned(true, projectID: ProjectID(rawValue: "/tmp/kept-project"))
        }
        #expect(try Data(contentsOf: registryURL) == original)

        writes.deniedNamePrefix = nil
        try registry.setPinned(true, projectID: ProjectID(rawValue: "/tmp/kept-project"))

        #expect(registry.persistenceErrorDescription == nil)
        #expect(registry.recoveryDiagnostic?.discardedRecordCount == 1)
        #expect(try ProjectRegistryStore(fileURL: registryURL).load().map(\.isPinned) == [true])
        let quarantine = try #require(registry.recoveryDiagnostic?.quarantineFileURL)
        #expect(try String(contentsOf: quarantine, encoding: .utf8).contains("invalid"))
    }

    @Test("a failed repair save keeps projects and the recovery notice, and the next write persists")
    func repairSaveFailureKeepsRecordsWritable() throws {
        let sandbox = makeSandbox("RepairSaveFailure")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let registryURL = sandbox.appendingPathComponent("registry.json")
        try Data(#"["invalid",{"id":"/tmp/repaired-project"}]"#.utf8).write(to: registryURL)
        let writes = WriteGate(deniedNamePrefix: "registry.json")
        let registry = ProjectRegistry(store: writes.store(fileURL: registryURL))

        #expect(registry.records.map(\.id) == [ProjectID(rawValue: "/tmp/repaired-project")])
        #expect(registry.recoveryDiagnostic?.discardedRecordCount == 1)
        #expect(registry.persistenceErrorDescription != nil)

        writes.deniedNamePrefix = nil
        try registry.setPinned(true, projectID: ProjectID(rawValue: "/tmp/repaired-project"))

        #expect(registry.persistenceErrorDescription == nil)
        #expect(try ProjectRegistryStore(fileURL: registryURL).load().map(\.id) == [
            ProjectID(rawValue: "/tmp/repaired-project"),
        ])
    }

    @Test(
        "an unreadable registry recovers on the next write once the file is readable",
        arguments: ["symbolic link", "directory"]
    )
    func unreadableRegistryRecoversOnNextWrite(corruption: String) throws {
        let sandbox = makeSandbox("UnreadableRecovery")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let registryURL = sandbox.appendingPathComponent("registry.json")
        let restoredURL = sandbox.appendingPathComponent("restored.json")
        try Data(#"[{"id":"/tmp/restored-project"}]"#.utf8).write(to: restoredURL)
        if corruption == "directory" {
            try FileManager.default.createDirectory(at: registryURL, withIntermediateDirectories: false)
        } else {
            try FileManager.default.createSymbolicLink(at: registryURL, withDestinationURL: restoredURL)
        }
        let registry = ProjectRegistry(store: ProjectRegistryStore(fileURL: registryURL))
        #expect(registry.records.isEmpty)
        #expect(throws: ProjectRegistryError.self) {
            try registry.recordOpen(descriptor(sandbox))
        }

        try FileManager.default.removeItem(at: registryURL)
        try FileManager.default.moveItem(at: restoredURL, to: registryURL)
        try registry.recordOpen(descriptor(sandbox))

        #expect(registry.persistenceErrorDescription == nil)
        #expect(Set(registry.records.map(\.id)) == Set([
            ProjectID(rawValue: "/tmp/restored-project"),
            ProjectID(rootURL: sandbox),
        ]))
    }

    @Test("known project roots and identity cache update before records publishes")
    func resolverUsesIncomingSnapshotDuringPublishedWillSet() throws {
        let sandbox = makeSandbox("WillPublish")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let projectRoot = sandbox.appendingPathComponent("project", isDirectory: true)
        let child = projectRoot.appendingPathComponent("Sources/Feature", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let registry = ProjectRegistry(store: ProjectRegistryStore(
            fileURL: sandbox.appendingPathComponent("registry.json")
        ))
        let services = ProjectIdentityServices(registry: registry)
        let appDelegate = AppDelegate(projectIdentityServices: services)
        let resolver = appDelegate.projectResolver
        #expect(appDelegate.projectRegistry === registry)
        #expect(resolver.resolveProject(for: child).id == ProjectID(rootURL: child))
        var rootObservedDuringWillSet: ProjectID?
        let cancellable = registry.$records.dropFirst().sink { _ in
            rootObservedDuringWillSet = resolver.resolveProject(for: child).id
        }

        try registry.recordOpen(descriptor(projectRoot))

        #expect(rootObservedDuringWillSet == ProjectID(rootURL: projectRoot))
        #expect(resolver.resolveProject(for: child).id == ProjectID(rootURL: projectRoot))
        _ = cancellable
    }

    private func makeSandbox(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "ProjectRegistryResilience-\(suffix)-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func descriptor(_ root: URL) -> ProjectDescriptor {
        let canonicalRoot = ProjectPathCanonicalizer.canonicalURL(root)
        let name = ProjectDescriptor.automaticName(for: canonicalRoot)
        return ProjectDescriptor(
            id: ProjectID(rootURL: canonicalRoot),
            rootURL: canonicalRoot,
            automaticName: name,
            displayName: name,
            parent: nil
        )
    }
}

private final class WriteGate: @unchecked Sendable {
    private let lock = NSLock()
    private var prefix: String?

    init(deniedNamePrefix: String?) {
        prefix = deniedNamePrefix
    }

    var deniedNamePrefix: String? {
        get { lock.withLock { prefix } }
        set { lock.withLock { prefix = newValue } }
    }

    func store(fileURL: URL) -> ProjectRegistryStore {
        ProjectRegistryStore(fileURL: fileURL) { [self] data, url in
            if let prefix = deniedNamePrefix, url.lastPathComponent.hasPrefix(prefix) {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try data.write(to: url, options: .atomic)
        }
    }
}

private final class PruneFailureFileManager: FileManager, @unchecked Sendable {
    private let deniedRemovalPath: String?
    private let deniedEnumerationPath: String?
    private let deniedAttributesPath: String?
    private let state = State()

    var deniedRemovalAttemptCount: Int {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.deniedRemovalAttemptCount
    }

    var deniedEnumerationAttemptCount: Int {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.deniedEnumerationAttemptCount
    }

    var deniedAttributesAttemptCount: Int {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.deniedAttributesAttemptCount
    }

    init(deniedRemovalURL: URL) {
        deniedRemovalPath = ProjectPathCanonicalizer.canonicalURL(deniedRemovalURL).path
        deniedEnumerationPath = nil
        deniedAttributesPath = nil
        super.init()
    }

    init(deniedEnumerationURL: URL) {
        deniedRemovalPath = nil
        deniedEnumerationPath = ProjectPathCanonicalizer.canonicalURL(deniedEnumerationURL).path
        deniedAttributesPath = nil
        super.init()
    }

    init(deniedAttributesURL: URL) {
        deniedRemovalPath = nil
        deniedEnumerationPath = nil
        deniedAttributesPath = ProjectPathCanonicalizer.canonicalURL(deniedAttributesURL).path
        super.init()
    }

    override func removeItem(at url: URL) throws {
        if ProjectPathCanonicalizer.canonicalURL(url).path == deniedRemovalPath {
            state.lock.lock()
            state.deniedRemovalAttemptCount += 1
            state.lock.unlock()
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: url)
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        if ProjectPathCanonicalizer.canonicalURL(url).path == deniedEnumerationPath {
            state.lock.lock()
            state.deniedEnumerationAttemptCount += 1
            state.lock.unlock()
            throw CocoaError(.fileReadNoPermission)
        }
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }

    override func setAttributes(
        _ attributes: [FileAttributeKey: Any],
        ofItemAtPath path: String
    ) throws {
        let canonicalPath = ProjectPathCanonicalizer.canonicalURL(
            URL(fileURLWithPath: path)
        ).path
        if canonicalPath == deniedAttributesPath {
            state.lock.lock()
            state.deniedAttributesAttemptCount += 1
            state.lock.unlock()
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.setAttributes(attributes, ofItemAtPath: path)
    }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var deniedRemovalAttemptCount = 0
        var deniedEnumerationAttemptCount = 0
        var deniedAttributesAttemptCount = 0
    }
}
