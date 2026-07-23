// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemotePortScannerBrowserRouteSwiftTestingTests.swift - Protected browser route discovery tests.

import Foundation
import Testing
@testable import CocxyTerminal

private final class RemotePortScannerMultiplexer: SSHMultiplexing, @unchecked Sendable {
    var attemptedForwards: [RemoteConnectionProfile.PortForward] = []
    var cancelledForwards: [RemoteConnectionProfile.PortForward] = []
    var remoteCommandResults: [String: ProcessResult] = [:]

    func connect(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws -> SSHControlMasterIdentity {
        SSHControlMasterIdentity(
            processID: 56_789,
            controlPath: profile.controlPath,
            supervisorID: UUID()
        )
    }

    func disconnect(profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws {}

    func isAlive(profile: RemoteConnectionProfile, executor: any ProcessExecutor) async throws -> Bool {
        true
    }

    func isControlMasterProcessAlive(_ identity: SSHControlMasterIdentity) -> Bool { false }
    func terminateControlMaster(_ identity: SSHControlMasterIdentity) {}
    func controlPath(for profile: RemoteConnectionProfile) -> String { profile.controlPath }
    func newSession(profile: RemoteConnectionProfile) -> String { "ssh mock" }

    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        attemptedForwards.append(forward)
    }

    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        cancelledForwards.append(forward)
    }

    func attestControlMaster(
        _ expectedControlMaster: SSHControlMasterIdentity
    ) throws -> SSHControlSocketAttestation {
        SSHControlSocketAttestation(
            device: 7,
            inode: 11,
            peerProcessID: expectedControlMaster.processID
        )
    }

    func verifyControlMaster(
        _ expectedControlMaster: SSHControlMasterIdentity,
        attestation: SSHControlSocketAttestation
    ) throws {
        guard attestation.device == 7,
              attestation.inode == 11,
              attestation.peerProcessID == expectedControlMaster.processID else {
            throw SSHMultiplexerError.notConnected
        }
    }

    func executeRemoteCommand(
        _ command: String,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> ProcessResult {
        remoteCommandResults[command] ?? ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}

private final class RemotePortScannerProfileStore: RemoteProfileStoring, @unchecked Sendable {
    var profiles: [RemoteConnectionProfile] = []

    func loadAll() throws -> [RemoteConnectionProfile] { profiles }
    func save(_ profile: RemoteConnectionProfile) throws { profiles.append(profile) }
    func delete(id: UUID) throws { profiles.removeAll { $0.id == id } }
    func findByName(_ name: String) throws -> RemoteConnectionProfile? {
        profiles.first { $0.name == name }
    }
    func findByGroup(_ group: String) throws -> [RemoteConnectionProfile] {
        profiles.filter { $0.group == group }
    }
}

@Suite("RemotePortScanner protected browser routes")
struct RemotePortScannerBrowserRouteSwiftTestingTests {
    private static let scanCommand = "ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null"

    @MainActor private static func makeConnectionManager(
        multiplexer: RemotePortScannerMultiplexer
    ) -> RemoteConnectionManager {
        RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: RemotePortScannerProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
    }

    @MainActor private static func connectedScanner(
        output: String,
        profile: RemoteConnectionProfile = RemoteConnectionProfile(
            id: UUID(),
            name: "Remote Dev",
            host: "dev.internal",
            user: "said"
        )
    ) async -> (RemotePortScanner, RemotePortScannerMultiplexer, RemoteConnectionProfile) {
        let multiplexer = RemotePortScannerMultiplexer()
        let manager = makeConnectionManager(multiplexer: multiplexer)
        await manager.connect(profile: profile)
        multiplexer.remoteCommandResults[scanCommand] = ProcessResult(
            exitCode: 0,
            stdout: output,
            stderr: ""
        )
        let scanner = RemotePortScanner(connectionManager: manager)
        scanner.startScanning(profileID: profile.id, performInitialScan: false)
        await scanner.refreshNow()
        return (scanner, multiplexer, profile)
    }

    @Test("Automatic selection keeps an explicitly active connected profile")
    func automaticSelectionKeepsCurrentConnectedProfile() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let selected = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

        #expect(RemotePortScanner.preferredScanningProfileID(
            currentProfileID: selected,
            connections: [
                first: .connected(latencyMs: nil),
                selected: .connected(latencyMs: 12),
            ]
        ) == selected)
    }

    @Test("Automatic selection chooses a deterministic connected replacement")
    func automaticSelectionChoosesDeterministicReplacement() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        #expect(RemotePortScanner.preferredScanningProfileID(
            currentProfileID: nil,
            connections: [
                second: .connected(latencyMs: nil),
                first: .connected(latencyMs: nil),
            ]
        ) == first)
    }

    @Test("Scan discovers services without creating any SSH listener")
    @MainActor func scanIsDiscoveryOnly() async {
        let (scanner, multiplexer, _) = await Self.connectedScanner(
            output: #"LISTEN 0 128 127.0.0.1:3000 *:* users:(("node",pid=1234,fd=15))"#
        )

        #expect(scanner.detectedPorts == [
            RemotePortInfo(port: 3000, process: "node", address: "127.0.0.1"),
        ])
        #expect(multiplexer.attemptedForwards.isEmpty)
        #expect(multiplexer.cancelledForwards.isEmpty)
    }

    @Test("Listening endpoint parser distinguishes loopback and wildcard addresses")
    @MainActor func parserPreservesListeningAddressScope() {
        let multiplexer = RemotePortScannerMultiplexer()
        let scanner = RemotePortScanner(
            connectionManager: Self.makeConnectionManager(multiplexer: multiplexer)
        )

        let ports = scanner.parseListeningPorts("""
        LISTEN 0 128 127.0.0.1:3000 *:* users:(("node",pid=1,fd=3))
        LISTEN 0 128 0.0.0.0:8080 *:* users:(("server",pid=2,fd=4))
        LISTEN 0 128 [::1]:5173 [::]:* users:(("vite",pid=3,fd=5))
        LISTEN 0 128 :::9000 :::* users:(("api",pid=4,fd=6))
        """)

        #expect(ports == [
            RemotePortInfo(port: 3000, process: "node", address: "127.0.0.1"),
            RemotePortInfo(port: 5173, process: "vite", address: "::1"),
            RemotePortInfo(port: 8080, process: "server", address: "0.0.0.0"),
            RemotePortInfo(port: 9000, process: "api", address: "::"),
        ])
    }

    @Test("Explicit browser approval returns remote metadata without forwarding")
    @MainActor func approvalProducesBrokerTargetOnly() async throws {
        let (scanner, multiplexer, profile) = await Self.connectedScanner(
            output: #"LISTEN 0 128 127.0.0.1:3000 *:* users:(("node",pid=1234,fd=15))"#
        )

        let suggestion = try scanner.beginBrowserOpen(3000)

        #expect(suggestion.profileID == profile.id)
        #expect(suggestion.remotePort == 3000)
        #expect(suggestion.process == "node")
        #expect(suggestion.remoteAddress == "127.0.0.1")
        #expect(suggestion.browserURL.absoluteString == "http://localhost:3000/")
        #expect(scanner.busyPorts == [3000])
        #expect(multiplexer.attemptedForwards.isEmpty)

        scanner.finishBrowserOpen(3000)
        #expect(scanner.busyPorts.isEmpty)
    }

    @Test("Opening operation retains busy ownership until the async opener finishes")
    @MainActor func openingOperationOwnsBusyState() async throws {
        let (scanner, multiplexer, profile) = await Self.connectedScanner(
            output: #"LISTEN 0 128 127.0.0.1:3000 *:* users:(("node",pid=1,fd=3))"#
        )

        let suggestion = try await RemoteBrowserOpeningOperation.open(
            remotePort: 3000,
            profile: profile,
            scanner: scanner,
            opener: { openedProfile, openedSuggestion in
                #expect(openedProfile.id == profile.id)
                #expect(openedSuggestion.browserURL.absoluteString == "http://localhost:3000/")
                #expect(scanner.busyPorts == [3000])
                return true
            }
        )

        #expect(suggestion.remotePort == 3000)
        #expect(scanner.busyPorts.isEmpty)
        #expect(multiplexer.attemptedForwards.isEmpty)
    }

    @Test("Rejected browser surface leaves no SSH capability behind")
    @MainActor func rejectedBrowserOpenLeavesNoForward() async {
        let (scanner, multiplexer, profile) = await Self.connectedScanner(
            output: #"LISTEN 0 128 127.0.0.1:3000 *:* users:(("node",pid=1,fd=3))"#
        )

        await #expect(throws: RemotePortScannerError.browserUnavailable) {
            _ = try await RemoteBrowserOpeningOperation.open(
                remotePort: 3000,
                profile: profile,
                scanner: scanner,
                opener: { _, _ in false }
            )
        }

        #expect(scanner.busyPorts.isEmpty)
        #expect(multiplexer.attemptedForwards.isEmpty)
        #expect(multiplexer.cancelledForwards.isEmpty)
    }

    @Test("A second open for the same port fails closed while approval is active")
    @MainActor func duplicateOpenIsRejected() async throws {
        let (scanner, _, _) = await Self.connectedScanner(
            output: #"LISTEN 0 128 127.0.0.1:3000 *:* users:(("node",pid=1,fd=3))"#
        )

        _ = try scanner.beginBrowserOpen(3000)
        #expect(throws: RemotePortScannerError.operationInProgress(3000)) {
            _ = try scanner.beginBrowserOpen(3000)
        }
        scanner.finishBrowserOpen(3000)
    }

    @Test("Stopping revokes route ownership before scanner state is cleared")
    @MainActor func stopRevokesBeforeClearingState() async {
        let (scanner, _, profile) = await Self.connectedScanner(
            output: #"LISTEN 0 128 127.0.0.1:3000 *:* users:(("node",pid=1,fd=3))"#
        )
        var observedProfileID: UUID?
        var observedDetectedPorts: [RemotePortInfo] = []
        scanner.routeRevocationHandler = { revokedProfileID in
            observedProfileID = scanner.scanningProfileID
            observedDetectedPorts = scanner.detectedPorts
            #expect(revokedProfileID == profile.id)
        }

        scanner.stopScanning()

        #expect(observedProfileID == profile.id)
        #expect(observedDetectedPorts.map(\.port) == [3000])
        #expect(scanner.scanningProfileID == nil)
        #expect(scanner.detectedPorts.isEmpty)
        #expect(!scanner.isScanning)
    }

    @Test("Switching profiles revokes the previous route exactly once")
    @MainActor func profileSwitchRevokesPreviousRoute() async {
        let multiplexer = RemotePortScannerMultiplexer()
        let manager = Self.makeConnectionManager(multiplexer: multiplexer)
        let first = RemoteConnectionProfile(id: UUID(), name: "One", host: "one.internal")
        let second = RemoteConnectionProfile(id: UUID(), name: "Two", host: "two.internal")
        await manager.connect(profile: first)
        await manager.connect(profile: second)
        let scanner = RemotePortScanner(connectionManager: manager)
        var revoked: [UUID] = []
        scanner.routeRevocationHandler = { revoked.append($0) }

        scanner.startScanning(profileID: first.id, performInitialScan: false)
        scanner.startScanning(profileID: second.id, performInitialScan: false)

        #expect(revoked == [first.id])
        #expect(scanner.scanningProfileID == second.id)
    }

    @Test("TLS development ports produce HTTPS broker targets")
    @MainActor func tlsPortProducesHTTPSRoute() async throws {
        let (scanner, _, _) = await Self.connectedScanner(
            output: #"LISTEN 0 128 0.0.0.0:8443 *:* users:(("server",pid=2,fd=4))"#
        )

        let suggestion = try scanner.beginBrowserOpen(8443)
        defer { scanner.finishBrowserOpen(8443) }

        #expect(suggestion.browserURL.absoluteString == "https://localhost:8443/")
    }

    @Test("Approval rejects a service that disappeared after discovery")
    @MainActor func staleServiceIsRejected() async {
        let (scanner, _, _) = await Self.connectedScanner(output: "")

        #expect(throws: RemotePortScannerError.portNotDetected(3000)) {
            _ = try scanner.beginBrowserOpen(3000)
        }
    }
}
