// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CellDomainSwiftTestingTests.swift - Cocxy Cells local-first domain contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Cell models")
struct CellModelsSwiftTestingTests {
    @Test("provider kinds are stable and local-first")
    func providerKindsAreStableAndLocalFirst() {
        #expect(CellProviderKind.docker.rawValue == "docker")
        #expect(CellProviderKind.ssh.rawValue == "ssh")
        #expect(CellProviderKind.e2b.rawValue == "e2b")
        #expect(CellProviderKind.fly.rawValue == "fly")
        #expect(CellProviderKind.aws.rawValue == "aws")
        #expect(CellProviderKind.gcp.rawValue == "gcp")
        #expect(CellProviderKind.azure.rawValue == "azure")
        #expect(CellProviderKind.selfHosted.rawValue == "self-hosted")
        #expect(CellProviderKind.localFirstCases.prefix(2) == [.docker, .ssh])
        #expect(CellProviderKind.allCases.map(\.rawValue).contains("hosted-cocxy") == false)
    }

    @Test("cell snapshot carries no secret metadata")
    func cellSnapshotCarriesNoSecretMetadata() {
        let cell = Cell(
            id: UUID(),
            name: "Local Sandbox",
            provider: .docker,
            status: .running,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001),
            metadata: [
                "image": "swift:6.0",
                "token": "secret-token",
                "apiKey": "secret-api-key",
                "workspace": "/Users/said/project",
            ]
        )

        #expect(cell.safeMetadata["image"] == "swift:6.0")
        #expect(cell.safeMetadata["workspace"] == "/Users/said/project")
        #expect(cell.safeMetadata["token"] == "[redacted]")
        #expect(cell.safeMetadata["apiKey"] == "[redacted]")
    }
}

@Suite("Cell leases")
struct CellLeaseManagerSwiftTestingTests {
    @Test("lease is single-use and bound to cell and purpose")
    func leaseIsSingleUseAndBoundToCellAndPurpose() throws {
        let cellID = UUID()
        let clock = CellTestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let manager = CellLeaseManager(
            secret: Data(repeating: 7, count: 32),
            ttl: 60,
            clock: { clock.now }
        )

        let lease = try manager.issueLease(cellID: cellID, purpose: .attachPTY)

        #expect(lease.cellID == cellID)
        #expect(lease.purpose == .attachPTY)
        #expect(lease.expiresAt == clock.now.addingTimeInterval(60))
        #expect(manager.consumeLease(lease, cellID: cellID, purpose: .exec) == false)
        #expect(manager.consumeLease(lease, cellID: UUID(), purpose: .attachPTY) == false)
        #expect(manager.consumeLease(lease, cellID: cellID, purpose: .attachPTY) == true)
        #expect(manager.consumeLease(lease, cellID: cellID, purpose: .attachPTY) == false)

        clock.advance(by: 61)
        let expired = try manager.issueLease(cellID: cellID, purpose: .attachPTY)
        clock.advance(by: 61)
        #expect(manager.consumeLease(expired, cellID: cellID, purpose: .attachPTY) == false)
    }

    @Test("tampered lease signature is rejected")
    func tamperedLeaseSignatureIsRejected() throws {
        let cellID = UUID()
        let manager = CellLeaseManager(secret: Data(repeating: 8, count: 32))
        let lease = try manager.issueLease(cellID: cellID, purpose: .exec)
        let tampered = CellLease(
            id: lease.id,
            cellID: lease.cellID,
            purpose: lease.purpose,
            issuedAt: lease.issuedAt,
            expiresAt: lease.expiresAt,
            signature: Data(repeating: 0, count: lease.signature.count)
        )

        #expect(manager.consumeLease(tampered, cellID: cellID, purpose: .exec) == false)
    }
}

@Suite("Cell audit log")
struct CellAuditLogSwiftTestingTests {
    @Test("audit log is encrypted at rest, mode 0600, and redacts secret metadata")
    func auditLogIsEncryptedAndRedacted() throws {
        let directory = try temporaryDirectory()
        let logURL = directory.appendingPathComponent("cells-audit.enc")
        let keyProvider = StaticCellAuditKeyProvider(keyData: Data(repeating: 3, count: 32))
        let log = CellAuditLog(auditURL: logURL, keyProvider: keyProvider)
        let event = CellAuditEvent(
            cellID: UUID(),
            action: .exec,
            actor: "local-user",
            metadata: [
                "command": "swift test",
                "token": "secret-token",
                "password": "secret-password",
            ],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try log.append(event)

        let raw = try Data(contentsOf: logURL)
        #expect(String(data: raw, encoding: .utf8)?.contains("swift test") == false)
        #expect(String(data: raw, encoding: .utf8)?.contains("secret-token") == false)
        #expect(String(data: raw, encoding: .utf8)?.contains("secret-password") == false)

        let attrs = try FileManager.default.attributesOfItem(atPath: logURL.path)
        let mode = try #require(attrs[.posixPermissions] as? NSNumber).intValue & 0o777
        #expect(mode == 0o600)

        let loaded = try log.loadEvents()
        #expect(loaded == [
            CellAuditEvent(
                id: event.id,
                cellID: event.cellID,
                action: .exec,
                actor: "local-user",
                metadata: [
                    "command": "swift test",
                    "token": "[redacted]",
                    "password": "[redacted]",
                ],
                createdAt: event.createdAt
            )
        ])
    }
}

@Suite("Cell secrets store")
struct CellSecretsStoreSwiftTestingTests {
    @Test("secrets are saved through a keychain-shaped backend and scoped by provider")
    func secretsAreScopedByProviderAndAccount() throws {
        let backend = MemoryCellSecretKeyValueStore()
        let store = CellSecretsStore(backend: backend)
        let dockerRef = CellSecretRef(provider: .docker, account: "local", key: "DOCKER_HOST")
        let flyRef = CellSecretRef(provider: .fly, account: "personal", key: "FLY_API_TOKEN")

        try store.save(Data("unix:///var/run/docker.sock".utf8), for: dockerRef)
        try store.save(Data("fly-token".utf8), for: flyRef)

        #expect(try store.load(dockerRef) == Data("unix:///var/run/docker.sock".utf8))
        #expect(try store.load(flyRef) == Data("fly-token".utf8))
        #expect(try store.refs(for: .docker) == [dockerRef])
        #expect(try store.refs(for: .fly) == [flyRef])

        try store.delete(dockerRef)

        #expect(try store.load(dockerRef) == nil)
        #expect(try store.refs(for: .docker).isEmpty)
        #expect(backend.savedAccounts.allSatisfy { $0.hasPrefix("cells:") })
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocxy-cells-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private final class CellTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ current: Date) {
        self.current = current
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(interval)
    }
}
