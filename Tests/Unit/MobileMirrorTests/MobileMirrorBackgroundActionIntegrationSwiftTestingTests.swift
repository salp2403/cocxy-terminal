// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror background action integration")
@MainActor
struct MobileMirrorBackgroundActionIntegrationSwiftTestingTests {
    @Test("project publication is rejected after pairing revocation")
    func projectPublicationRequiresCurrentPairing() async throws {
        let sandbox = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let gate = MobileMirrorActionGate()
        let service = SuspendedPublishedProjectService(gate: gate)
        let context = makeCoordinator(sandbox: sandbox, projectService: service)
        defer { context.stop() }
        let session = try activatePairing(
            authority: context.coordinator.authority,
            coordinator: context.coordinator
        )
        let operation = try preparedProjectCreation(
            name: "Revoked Pairing",
            context: context,
            session: session
        )
        let task = Task { @MainActor in try await operation() }

        await gate.waitUntilSuspended()
        _ = context.coordinator.authority.revoke()
        await gate.release()

        await #expect(throws: MobileMirrorError.sessionExpired) {
            try await task.value
        }
        #expect(context.projectRegistry.records.isEmpty)
        #expect(FileManager.default.fileExists(
            atPath: sandbox
                .appendingPathComponent("projects/Revoked Pairing", isDirectory: true)
                .path
        ) == false)
    }

    @Test("project publication observes cancellation before activation")
    func projectPublicationObservesCancellation() async throws {
        let sandbox = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let gate = MobileMirrorActionGate()
        let service = SuspendedPublishedProjectService(gate: gate)
        let context = makeCoordinator(sandbox: sandbox, projectService: service)
        defer { context.stop() }
        let session = try activatePairing(
            authority: context.coordinator.authority,
            coordinator: context.coordinator
        )
        let operation = try preparedProjectCreation(
            name: "Cancelled Pairing",
            context: context,
            session: session
        )
        let task = Task { @MainActor in try await operation() }

        await gate.waitUntilSuspended()
        task.cancel()
        await gate.release()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(context.projectRegistry.records.isEmpty)
    }

    @Test("revoked project work records its completed side effect")
    func revokedProjectWorkRemainsAudited() async throws {
        let sandbox = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let gate = MobileMirrorActionGate()
        let service = SuspendedPublishedProjectService(gate: gate)
        let context = makeCoordinator(sandbox: sandbox, projectService: service)
        defer { context.stop() }
        let session = try activatePairing(
            authority: context.coordinator.authority,
            coordinator: context.coordinator
        )
        let rootURL = try installProjectRoot(in: sandbox, coordinator: context.coordinator)

        _ = try await context.coordinator.handle(
            action: MobileMirrorAction(kind: .projectCreate, name: "Revoked Work"),
            cookie: session.cookie,
            channelID: session.active.channelID,
            identity: session.identity
        )
        await gate.waitUntilSuspended()
        #expect(FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent("Revoked Work", isDirectory: true).path
        ))

        context.coordinator.shutdown()
        await gate.release()

        #expect(await eventually {
            context.auditWriter.mobileActionOutcomes() == ["queued", "rejected"]
                && !context.coordinator.projectCreationIsQueued
        })
        #expect(context.projectRegistry.records.isEmpty)
    }

    @Test("a cancelled partial action still audits and notifies")
    func cancelledPartialActionStillPublishesCompletion() async throws {
        let sandbox = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let context = makeCoordinator(sandbox: sandbox)
        defer { context.stop() }
        let session = try activatePairing(
            authority: context.coordinator.authority,
            coordinator: context.coordinator
        )
        let eventCapture = MobileMirrorEventCapture()
        let eventHub = MobileMirrorEventHub { data, _ in
            eventCapture.append(data)
            return true
        }
        eventHub.add(descriptor: 101, close: {})
        context.coordinator.gateway = MobileMirrorGateway(eventHub: eventHub) { _, _ in
            .response(.error("Unavailable", status: 503))
        }
        let gate = MobileMirrorActionGate()

        context.coordinator.startBackgroundAction(
            MobileMirrorAction(kind: .projectCreate, name: "Partial Work"),
            channelID: session.active.channelID,
            identity: session.identity,
            notificationSessionID: session.active.channelID.uuidString
        ) {
            await gate.suspend()
            return .partial
        }
        await gate.waitUntilSuspended()
        context.coordinator.backgroundActionQueue.cancelAll()
        await gate.release()

        #expect(await eventually {
            context.auditWriter.mobileActionOutcomes() == ["partial"]
                && eventCapture.contains("\"kind\":\"action-partial\"")
        })
    }

    @Test("revoking an active pairing notifies the mobile client before shutdown")
    func activePairingRevocationPublishesEvent() async throws {
        let sandbox = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let context = makeCoordinator(sandbox: sandbox)
        defer { context.stop() }
        _ = try activatePairing(
            authority: context.coordinator.authority,
            coordinator: context.coordinator
        )
        let eventCapture = MobileMirrorEventCapture()
        let eventHub = MobileMirrorEventHub { data, _ in
            eventCapture.append(data)
            return true
        }
        eventHub.add(descriptor: 102, close: {})
        context.coordinator.gateway = MobileMirrorGateway(eventHub: eventHub) { _, _ in
            .response(.error("Unavailable", status: 503))
        }

        context.coordinator.revoke()

        #expect(eventCapture.contains("event: revoked"))
        #expect(context.coordinator.activePairing == nil)
        #expect(context.coordinator.authority.activePairing() == nil)
    }

    @Test("background audit failure reaches the desktop in the configured language")
    func backgroundAuditFailureIsLocalized() async throws {
        let sandbox = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let localizationRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Localization", isDirectory: true)
        let localizer = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(Bundle(url: localizationRoot))
        )
        let context = makeCoordinator(
            sandbox: sandbox,
            auditWriter: MobileMirrorIntegrationAuditWriter(failsWrites: true),
            localizer: localizer
        )
        defer { context.stop() }

        context.coordinator.startBackgroundAction(
            MobileMirrorAction(kind: .projectCreate, name: "Trabajo"),
            channelID: UUID(),
            identity: MobileMirrorClientIdentity(
                remoteAddress: "192.168.50.23",
                userAgent: "Mobile integration test"
            ),
            notificationSessionID: UUID().uuidString,
            operation: { .accepted }
        )

        #expect(await eventually {
            context.coordinator.state == .failed(
                "El registro de auditoría local no está disponible."
            )
        })
    }

    private func preparedProjectCreation(
        name: String,
        context: MobileMirrorCoordinatorTestContext,
        session: MobileMirrorTestSession
    ) throws -> @MainActor () async throws -> Void {
        _ = try installProjectRoot(in: context.sandbox, coordinator: context.coordinator)
        return try context.coordinator.prepareProjectCreation(
            named: name,
            identity: session.identity,
            cookie: session.cookie,
            channelID: session.active.channelID
        )
    }

    private func installProjectRoot(
        in sandbox: URL,
        coordinator: MobileMirrorCoordinator
    ) throws -> URL {
        let rootURL = sandbox.appendingPathComponent("projects", isDirectory: true)
        if !FileManager.default.fileExists(atPath: rootURL.path) {
            try FileManager.default.createDirectory(
                at: rootURL,
                withIntermediateDirectories: false
            )
        }
        coordinator.projectCreationRootHandle = try ProjectDirectoryRoot.open(rootURL)
        coordinator.projectCreationRoot = rootURL
        return rootURL
    }

    private func activatePairing(
        authority: MobileMirrorPairingAuthority,
        coordinator: MobileMirrorCoordinator
    ) throws -> MobileMirrorTestSession {
        let identity = MobileMirrorClientIdentity(
            remoteAddress: "192.168.50.23",
            userAgent: "Mobile integration test"
        )
        let offer = authority.makeOffer()
        let pending = try authority.consumeOffer(token: offer.token, identity: identity)
        let active = try #require(try authority.decide(pendingID: pending.id, approve: true))
        let poll = try authority.poll(pendingID: pending.id, identity: identity)
        guard case .confirmed(let cookie) = poll else {
            Issue.record("Expected confirmed mobile pairing")
            throw MobileMirrorError.pairingPending
        }
        coordinator.activePairing = active
        return MobileMirrorTestSession(identity: identity, active: active, cookie: cookie)
    }

    private func makeCoordinator(
        sandbox: URL,
        projectService: any MobileMirrorProjectCreating = MobileMirrorProjectService(),
        auditWriter: MobileMirrorIntegrationAuditWriter = MobileMirrorIntegrationAuditWriter(),
        localizer: AppLocalizer? = nil
    ) -> MobileMirrorCoordinatorTestContext {
        let appDelegate = AppDelegate()
        let profileStore = MockRemoteProfileStore()
        let tunnelManager = SSHTunnelManager()
        let connectionManager = RemoteConnectionManager(
            multiplexer: MockSSHMultiplexerDelegate(),
            profileStore: profileStore,
            tunnelManager: tunnelManager,
            executor: MockProcessExecutor()
        )
        let relayManager = RelayManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: MockPortForwarder()
        )
        let tunnelController = MobileMirrorSSHTunnelController(
            connectionManager: connectionManager,
            profileStore: profileStore,
            tunnelManager: tunnelManager
        )
        let projectRegistry = ProjectRegistry(store: ProjectRegistryStore(
            fileURL: sandbox.appendingPathComponent("registry.json")
        ))
        let coordinator = MobileMirrorCoordinator(
            appDelegate: appDelegate,
            projectRegistry: projectRegistry,
            projectResolver: CachedProjectResolver(),
            titleStore: AuroraWorkspaceTitleStore(),
            sessionRegistry: SessionRegistryImpl(),
            approvalRegistry: MobileMirrorApprovalRegistry(),
            auditLog: RelayAuditLog(writer: auditWriter),
            relayManager: relayManager,
            tunnelController: tunnelController,
            projectService: projectService,
            localizer: localizer,
            projectCreationConfirmation: { _, _ in true }
        )
        return MobileMirrorCoordinatorTestContext(
            coordinator: coordinator,
            projectRegistry: projectRegistry,
            relayManager: relayManager,
            auditWriter: auditWriter,
            sandbox: sandbox
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-mobile-background-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url.standardizedFileURL
    }

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return condition()
    }
}

@MainActor
private struct MobileMirrorCoordinatorTestContext {
    let coordinator: MobileMirrorCoordinator
    let projectRegistry: ProjectRegistry
    let relayManager: RelayManagerImpl
    let auditWriter: MobileMirrorIntegrationAuditWriter
    let sandbox: URL

    func stop() {
        coordinator.shutdown()
        relayManager.stopExpirationTimer()
    }
}

private struct MobileMirrorTestSession {
    let identity: MobileMirrorClientIdentity
    let active: MobileMirrorActivePairing
    let cookie: String
}

private actor MobileMirrorActionGate {
    private var suspended = false
    private var released = false
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        suspended = true
        suspensionWaiters.forEach { $0.resume() }
        suspensionWaiters.removeAll()
        guard !released else { return }
        await withCheckedContinuation { continuation in
            if released {
                continuation.resume()
            } else {
                releaseContinuation = continuation
            }
        }
    }

    func waitUntilSuspended() async {
        guard !suspended else { return }
        await withCheckedContinuation { suspensionWaiters.append($0) }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private final class SuspendedPublishedProjectService: MobileMirrorProjectCreating, @unchecked Sendable {
    private let gate: MobileMirrorActionGate

    init(gate: MobileMirrorActionGate) {
        self.gate = gate
    }

    func createProject(
        named name: String,
        in authorizedRoot: ProjectDirectoryRoot
    ) async throws -> ProjectDirectoryPublication {
        let publicationTask = Task.detached(priority: .userInitiated) {
            try await MobileMirrorProjectService().createProject(
                named: name,
                in: authorizedRoot
            )
        }
        let publication = try await publicationTask.value
        await gate.suspend()
        return publication
    }
}

private final class MobileMirrorIntegrationAuditWriter: AuditLogWriting, @unchecked Sendable {
    private let lock = NSLock()
    private let failsWrites: Bool
    private var lines: [String] = []

    init(failsWrites: Bool = false) {
        self.failsWrites = failsWrites
    }

    var currentSize: Int {
        lock.withLock { lines.joined(separator: "\n").utf8.count }
    }

    func appendLine(_ line: String) throws {
        if failsWrites { throw RelayAuditWriterTestFailure.injected }
        lock.withLock { lines.append(line) }
    }

    func rotate() {}

    func readAllLines() -> [String] {
        lock.withLock { lines }
    }

    func mobileActionOutcomes() -> [String] {
        readAllLines().compactMap { line in
            guard let data = line.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  payload["event"] as? String == "mobileAction" else {
                return nil
            }
            return payload["outcome"] as? String
        }
    }
}

private final class MobileMirrorEventCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var payloads: [String] = []

    func append(_ data: Data) {
        guard let value = String(data: data, encoding: .utf8) else { return }
        lock.withLock { payloads.append(value) }
    }

    func contains(_ value: String) -> Bool {
        lock.withLock { payloads.contains(where: { $0.contains(value) }) }
    }
}
