// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CellCloudInitFileBrokerSwiftTestingTests.swift - Approval-bound user-data staging coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Cell cloud-init file broker")
struct CellCloudInitFileBrokerSwiftTestingTests {
    @Test("approved bytes are staged privately for every cloud provider and then removed")
    func stagesApprovedBytesForCloudProviders() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let cases: [(provider: String, value: String, prefix: String)] = [
            ("aws", "file://\(fixture.source.path)", "file://"),
            ("aws", "fileb://\(fixture.source.path)", "fileb://"),
            ("gcp", fixture.source.path, ""),
            ("azure", fixture.source.path, ""),
        ]

        for testCase in cases {
            let params = [
                "provider": testCase.provider,
                "cloud-init": testCase.value,
            ]
            let broker = CellCloudInitFileBroker(stager: CellCloudInitFileStager(
                rootDirectory: fixture.stagingRoot
            ))
            var stagedPath: String?

            let result = try broker.withStagedApprovedCloudInit(
                kind: "create",
                params: params,
                approvedContext: fixture.context
            ) { boundParams in
                let reference = try #require(
                    CellCLICommandService.cloudInitLocalResourceReference(in: boundParams)
                )
                stagedPath = reference.path
                let fileURL = URL(fileURLWithPath: reference.path)
                let directoryURL = fileURL.deletingLastPathComponent()
                let fileMode = try posixMode(at: fileURL)
                let directoryMode = try posixMode(at: directoryURL)

                #expect(boundParams["cloud-init"]?.hasPrefix(testCase.prefix) == true)
                #expect(reference.path != fixture.source.path)
                #expect(reference.path.hasPrefix(fixture.stagingRoot.path + "/request-"))
                #expect(try Data(contentsOf: fileURL) == fixture.data)
                #expect(fileMode == 0o600)
                #expect(directoryMode == 0o700)
                return "staged"
            }

            #expect(result == "staged")
            #expect(stagedPath.map(FileManager.default.fileExists(atPath:)) == false)
        }
    }

    @Test("changed content fails before staging or provider work")
    func rejectsChangedContent() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data("changed after approval\n".utf8).write(to: fixture.source)
        var operationCalls = 0

        do {
            _ = try broker(for: fixture).withStagedApprovedCloudInit(
                kind: "create",
                params: ["provider": "gcp", "cloud-init": fixture.source.path],
                approvedContext: fixture.context
            ) { _ in
                operationCalls += 1
            }
            Issue.record("Expected changed cloud-init content to fail")
        } catch let error as CellCloudInitFileBrokerError {
            #expect(error == .sourceChanged)
        }

        #expect(operationCalls == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.stagingRoot.path))
    }

    @Test("a symlink replacement cannot reuse an approved digest")
    func rejectsSymlinkReplacement() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let replacement = fixture.root.appendingPathComponent("replacement.yml")
        try fixture.data.write(to: replacement)
        try FileManager.default.removeItem(at: fixture.source)
        try FileManager.default.createSymbolicLink(
            at: fixture.source,
            withDestinationURL: replacement
        )
        var operationCalls = 0

        do {
            _ = try broker(for: fixture).withStagedApprovedCloudInit(
                kind: "create",
                params: ["provider": "azure", "cloud-init": fixture.source.path],
                approvedContext: fixture.context
            ) { _ in
                operationCalls += 1
            }
            Issue.record("Expected a symlink replacement to fail")
        } catch let error as CellCloudInitFileBrokerError {
            #expect(error == .sourceUnavailable)
        }

        #expect(operationCalls == 0)
    }

    @Test("staging is removed when provider work throws")
    func removesStagingAfterProviderFailure() throws {
        enum ProbeError: Error { case expected }

        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var stagedPath: String?

        do {
            let _: Void = try broker(for: fixture).withStagedApprovedCloudInit(
                kind: "create",
                params: ["provider": "gcp", "cloud-init": fixture.source.path],
                approvedContext: fixture.context
            ) { boundParams in
                stagedPath = CellCLICommandService
                    .cloudInitLocalResourceReference(in: boundParams)?.path
                throw ProbeError.expected
            }
            Issue.record("Expected provider work to throw")
        } catch ProbeError.expected {
            // Expected.
        }

        #expect(stagedPath != nil)
        #expect(stagedPath.map(FileManager.default.fileExists(atPath:)) == false)
    }

    @Test("launch cleanup removes abandoned staging")
    func removesAbandonedStaging() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-cloud-init-cleanup-\(UUID().uuidString)", isDirectory: true)
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        let abandoned = stagingRoot.appendingPathComponent("request-stale", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: abandoned,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Data("stale".utf8).write(
            to: abandoned.appendingPathComponent(CellCloudInitFileStager.stagedFileName)
        )

        try CellCloudInitFileStager(rootDirectory: stagingRoot).removeAbandonedStaging()

        #expect(!FileManager.default.fileExists(atPath: stagingRoot.path))
    }

    @Test("launch cleanup preserves staging owned by a live app instance")
    func launchCleanupPreservesLiveProcesses() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-cloud-init-processes-\(UUID().uuidString)", isDirectory: true)
        let abandoned = parent.appendingPathComponent("process-111-abandoned", isDirectory: true)
        let active = parent.appendingPathComponent("process-222-active", isDirectory: true)
        let current = parent.appendingPathComponent("process-333-current", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        for directory in [abandoned, active, current] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        try CellCloudInitFileStager.removeAbandonedProcessStaging(
            in: parent,
            currentProcessID: 333,
            processIsRunning: { $0 == 222 }
        )

        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
        #expect(FileManager.default.fileExists(atPath: active.path))
        #expect(FileManager.default.fileExists(atPath: current.path))
    }

    @MainActor
    @Test("app bridge keeps staged bytes alive only for provider creation")
    func appBridgeScopesStagingToProviderCreation() throws {
        for shouldFail in [false, true] {
            let fixture = try makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let provider = CapturingCloudInitCellProvider(shouldFail: shouldFail)
            let service = CellCLICommandService(
                providers: [.gcp: provider],
                auditLog: NoopCellAuditLog()
            )
            let delegate = AppDelegate()

            let result = delegate.handleCellCLIRequest(
                kind: "create",
                params: ["provider": "gcp", "cloud-init": fixture.source.path],
                approvedContext: fixture.context,
                serviceOverride: service,
                cloudInitBroker: broker(for: fixture)
            )
            let snapshot = try #require(provider.snapshot)

            #expect(result.success == !shouldFail)
            #expect(snapshot.path != fixture.source.path)
            #expect(snapshot.data == fixture.data)
            #expect(snapshot.mode == 0o600)
            #expect(!FileManager.default.fileExists(atPath: snapshot.path))
        }
    }

    private func broker(for fixture: Fixture) -> CellCloudInitFileBroker {
        CellCloudInitFileBroker(stager: CellCloudInitFileStager(
            rootDirectory: fixture.stagingRoot
        ))
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-cloud-init-broker-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let source = root.appendingPathComponent("approved.yml")
        let data = Data("#cloud-config\npackages:\n  - ripgrep\n".utf8)
        try data.write(to: source)
        let digest = SocketPrivilegedCommandSecurity.digest(data: data)
        let context = SocketPrivilegedCommandContext(
            scope: .computeCell,
            windowControllerIdentifier: nil,
            tabID: nil,
            workingDirectory: root.path,
            localResourcePaths: ["cloud-init": source.path],
            localResourceDigests: ["cloud-init": digest],
            surfaceID: nil,
            browserViewModelIdentifier: nil,
            browserTabID: nil,
            browserURL: nil,
            targetDisplayName: "gcp"
        )
        return Fixture(
            root: root,
            source: source,
            stagingRoot: root.appendingPathComponent("staging", isDirectory: true),
            data: data,
            context: context
        )
    }

    private func posixMode(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private struct Fixture {
        let root: URL
        let source: URL
        let stagingRoot: URL
        let data: Data
        let context: SocketPrivilegedCommandContext
    }
}

private final class CapturingCloudInitCellProvider: CellProvider, @unchecked Sendable {
    struct Snapshot {
        let path: String
        let data: Data
        let mode: Int
    }

    enum ProbeError: Error { case expected }

    let kind: CellProviderKind = .gcp
    let shouldFail: Bool
    private let snapshotBox = LockedBox<Snapshot?>(nil)

    init(shouldFail: Bool) {
        self.shouldFail = shouldFail
    }

    var snapshot: Snapshot? {
        snapshotBox.withValue { $0 }
    }

    func create(_ request: CellCreateRequest) async throws -> Cell {
        let path = try #require(request.metadata["cloud-init"])
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
        snapshotBox.withValue { value in
            value = Snapshot(path: path, data: data, mode: mode)
        }
        if shouldFail { throw ProbeError.expected }
        return Cell(id: UUID(), name: request.name, provider: .gcp, status: .running)
    }

    func list() async throws -> [Cell] { [] }
    func status(cellID: UUID) async throws -> CellStatus { .running }
    func exec(cellID: UUID, command: [String]) async throws -> String { "" }
    func attachCommand(cellID: UUID) async throws -> CellAttachCommand {
        CellAttachCommand(executable: "/usr/bin/true", arguments: [], displayName: "test")
    }
    func logs(cellID: UUID) async throws -> String { "" }
    func destroy(cellID: UUID, force: Bool) async throws {}
}

private struct NoopCellAuditLog: CellAuditLogging {
    func append(_ event: CellAuditEvent) throws {}
}
