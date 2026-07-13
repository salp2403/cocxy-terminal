// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemotePortScannerBrowserRouteSwiftTestingTests.swift - Browser routing tests for remote port discovery.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

private final class RemotePortScannerMultiplexer: SSHMultiplexing, @unchecked Sendable {
    var attemptedForwards: [RemoteConnectionProfile.PortForward] = []
    var forwarded: [RemoteConnectionProfile.PortForward] = []
    var cancelled: [RemoteConnectionProfile.PortForward] = []
    var lifecycleEvents: [String] = []
    var failingLocalPorts: Set<Int> = []
    var remoteCommandResults: [String: ProcessResult] = [:]

    func connect(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws -> SSHControlMasterIdentity {
        SSHControlMasterIdentity(processID: 56_789, controlPath: profile.controlPath)
    }

    func disconnect(profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws {}

    func isAlive(profile: RemoteConnectionProfile, executor: any ProcessExecutor) async throws -> Bool {
        true
    }

    func isControlMasterProcessAlive(_ identity: SSHControlMasterIdentity) -> Bool {
        false
    }

    func terminateControlMaster(_ identity: SSHControlMasterIdentity) {}

    func controlPath(for profile: RemoteConnectionProfile) -> String {
        profile.controlPath
    }

    func newSession(profile: RemoteConnectionProfile) -> String {
        "ssh mock"
    }

    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        attemptedForwards.append(forward)
        if let localPort = forward.boundLocalPort, failingLocalPorts.contains(localPort) {
            throw SSHMultiplexerError.connectionFailed("local port busy")
        }
        forwarded.append(forward)
    }

    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        lifecycleEvents.append("cancel")
        cancelled.append(forward)
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

    func loadAll() throws -> [RemoteConnectionProfile] {
        profiles
    }

    func save(_ profile: RemoteConnectionProfile) throws {
        profiles.append(profile)
    }

    func delete(id: UUID) throws {
        profiles.removeAll { $0.id == id }
    }

    func findByName(_ name: String) throws -> RemoteConnectionProfile? {
        profiles.first { $0.name == name }
    }

    func findByGroup(_ group: String) throws -> [RemoteConnectionProfile] {
        profiles.filter { $0.group == group }
    }
}

@Suite("RemotePortScanner browser routes")
struct RemotePortScannerBrowserRouteSwiftTestingTests {
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

    @Test("Scan discovers a dev service without publishing a local forward")
    @MainActor func scanDoesNotPublishDetectedService() async throws {
        let multiplexer = RemotePortScannerMultiplexer()
        multiplexer.failingLocalPorts = [3000]
        let manager = Self.makeConnectionManager(multiplexer: multiplexer)
        let profile = RemoteConnectionProfile(
            id: UUID(),
            name: "Remote Dev",
            host: "dev.internal",
            user: "said"
        )
        await manager.connect(profile: profile)

        let scanner = RemotePortScanner(
            multiplexer: multiplexer,
            connectionManager: manager,
            localPortCandidates: { remotePort, _ in [remotePort, 53_000] },
            localPortAvailability: { _ in true }
        )
        multiplexer.remoteCommandResults[
            "ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null"
        ] = ProcessResult(
            exitCode: 0,
            stdout: #"LISTEN 0 128 127.0.0.1:3000 *:* users:(("node",pid=1234,fd=15))"#,
            stderr: ""
        )
        scanner.startScanning(profileID: profile.id, performInitialScan: false)

        await scanner.refreshNow()

        #expect(scanner.detectedPorts == [
            RemotePortInfo(port: 3000, process: "node", address: "127.0.0.1"),
        ])
        #expect(multiplexer.attemptedForwards.isEmpty)
        #expect(multiplexer.forwarded.isEmpty)
        #expect(scanner.forwardedPorts.isEmpty)
        #expect(scanner.forwardedPortMappings.isEmpty)
        #expect(scanner.browserOpenSuggestions.isEmpty)
    }

    @Test("Listening endpoint parser distinguishes loopback and wildcard addresses")
    @MainActor func parserPreservesListeningAddressScope() {
        let multiplexer = RemotePortScannerMultiplexer()
        let scanner = RemotePortScanner(
            multiplexer: multiplexer,
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

    @Test("Explicit forward falls back to a browser-safe port and publishes a suggestion")
    @MainActor func explicitForwardPublishesBrowserSuggestionWithFallbackPort() async throws {
        let multiplexer = RemotePortScannerMultiplexer()
        multiplexer.failingLocalPorts = [3000]
        let manager = Self.makeConnectionManager(multiplexer: multiplexer)
        let profile = RemoteConnectionProfile(
            id: UUID(),
            name: "Remote Dev",
            host: "dev.internal",
            user: "said"
        )
        await manager.connect(profile: profile)

        let scanner = RemotePortScanner(
            multiplexer: multiplexer,
            connectionManager: manager,
            localPortCandidates: { remotePort, _ in [remotePort, 53_000] },
            localPortAvailability: { _ in true }
        )
        multiplexer.remoteCommandResults[
            "ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null"
        ] = ProcessResult(
            exitCode: 0,
            stdout: #"LISTEN 0 128 127.0.0.1:3000 *:* users:(("node",pid=1234,fd=15))"#,
            stderr: ""
        )
        scanner.startScanning(profileID: profile.id, performInitialScan: false)
        await scanner.refreshNow()

        await scanner.forwardDetectedPort(3000)

        #expect(multiplexer.attemptedForwards.count == 2)
        #expect(multiplexer.forwarded.count == 1)
        #expect(scanner.forwardedPorts == Set([3000]))
        #expect(scanner.forwardedPortMappings[3000] == 53_000)
        #expect(scanner.browserOpenSuggestions.count == 1)
        let suggestion = try #require(scanner.browserOpenSuggestions.first)
        #expect(suggestion.remotePort == 3000)
        #expect(suggestion.localPort == 53_000)
        #expect(suggestion.localURL.absoluteString == "http://127.0.0.1:53000/")
        #expect(suggestion.process == "node")
    }

    @Test("Explicit forward skips a locally bound candidate before publishing")
    @MainActor func explicitForwardSkipsLocallyBoundCandidate() async throws {
        let multiplexer = RemotePortScannerMultiplexer()
        let manager = Self.makeConnectionManager(multiplexer: multiplexer)
        let profile = RemoteConnectionProfile(
            id: UUID(),
            name: "Remote Dev",
            host: "dev.internal",
            user: "said"
        )
        await manager.connect(profile: profile)

        let scanner = RemotePortScanner(
            multiplexer: multiplexer,
            connectionManager: manager,
            localPortCandidates: { remotePort, _ in [remotePort, 53_000] },
            localPortAvailability: { $0 != 3000 }
        )
        multiplexer.remoteCommandResults[
            "ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null"
        ] = ProcessResult(
            exitCode: 0,
            stdout: #"LISTEN 0 128 127.0.0.1:3000 *:* users:(("node",pid=1234,fd=15))"#,
            stderr: ""
        )
        scanner.startScanning(profileID: profile.id, performInitialScan: false)

        await scanner.refreshNow()
        await scanner.forwardDetectedPort(3000)

        #expect(multiplexer.attemptedForwards.count == 1)
        #expect(multiplexer.forwarded.count == 1)
        #expect(scanner.forwardedPortMappings[3000] == 53_000)
        let suggestion = try #require(scanner.browserOpenSuggestions.first)
        #expect(suggestion.localURL.absoluteString == "http://127.0.0.1:53000/")
    }

    @Test("Scanner builds remote browser profile and route from forwarded mapping")
    @MainActor func scannerBuildsRemoteBrowserProfileAndRoute() async throws {
        let multiplexer = RemotePortScannerMultiplexer()
        let manager = Self.makeConnectionManager(multiplexer: multiplexer)
        let profile = RemoteConnectionProfile(
            id: UUID(),
            name: "Lab",
            host: "lab.internal",
            user: "dev",
            port: 2200
        )
        await manager.connect(profile: profile)

        let scanner = RemotePortScanner(
            multiplexer: multiplexer,
            connectionManager: manager,
            localPortCandidates: { _, _ in [55_173] },
            localPortAvailability: { _ in true }
        )
        multiplexer.remoteCommandResults[
            "ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null"
        ] = ProcessResult(
            exitCode: 0,
            stdout: #"LISTEN 0 128 0.0.0.0:5173 *:* users:(("vite",pid=42,fd=9))"#,
            stderr: ""
        )
        scanner.startScanning(profileID: profile.id, performInitialScan: false)
        await scanner.refreshNow()
        await scanner.forwardDetectedPort(5173)

        let browserProfile = scanner.browserProfile(
            for: profile,
            proxyState: .active(socksPort: 1080, httpPort: 18888)
        )
        let route = try #require(scanner.browserRoute(
            forRemotePort: 5173,
            remoteConnectionProfile: profile,
            proxyState: .active(socksPort: 1080, httpPort: 18888),
            path: "dashboard"
        ))

        #expect(browserProfile.displayTitle == "Lab (dev@lab.internal:2200)")
        #expect(browserProfile.localForwardedPorts == [5173: 55_173])
        #expect(browserProfile.proxyHealth == .active)
        #expect(browserProfile.socksPort == 1080)
        #expect(browserProfile.httpConnectPort == 18888)
        #expect(route.remoteAddress == "lab.internal:5173")
        #expect(route.localURL.absoluteString == "http://127.0.0.1:55173/dashboard")
    }

    @Test("Switching scanned profile clears stale browser routes")
    @MainActor func switchingScannedProfileClearsStaleBrowserRoutes() async {
        let multiplexer = RemotePortScannerMultiplexer()
        let manager = Self.makeConnectionManager(multiplexer: multiplexer)
        let first = RemoteConnectionProfile(id: UUID(), name: "One", host: "one.internal")
        let second = RemoteConnectionProfile(id: UUID(), name: "Two", host: "two.internal")
        await manager.connect(profile: first)
        await manager.connect(profile: second)

        let scanner = RemotePortScanner(
            multiplexer: multiplexer,
            connectionManager: manager,
            localPortCandidates: { _, _ in [53_000] },
            localPortAvailability: { _ in true }
        )
        multiplexer.remoteCommandResults[
            "ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null"
        ] = ProcessResult(
            exitCode: 0,
            stdout: #"LISTEN 0 128 127.0.0.1:3000 *:* users:(("node",pid=1234,fd=15))"#,
            stderr: ""
        )

        scanner.startScanning(profileID: first.id, performInitialScan: false)
        await scanner.refreshNow()
        await scanner.forwardDetectedPort(3000)
        #expect(scanner.scanningProfileID == first.id)
        #expect(scanner.forwardedPortMappings[3000] == 53_000)
        #expect(scanner.browserOpenSuggestions.count == 1)

        scanner.startScanning(profileID: second.id, performInitialScan: false)

        #expect(multiplexer.cancelled == [
            .local(localPort: 53_000, remotePort: 3000),
        ])
        #expect(scanner.scanningProfileID == second.id)
        #expect(scanner.forwardedPortMappings.isEmpty)
        #expect(scanner.browserOpenSuggestions.isEmpty)
    }

    @Test("Stopping clears browser leases before cancelling scanner-owned forwards")
    @MainActor func stopClearsBrowserLeasesBeforeCancellingOwnedForwards() async {
        let multiplexer = RemotePortScannerMultiplexer()
        let manager = Self.makeConnectionManager(multiplexer: multiplexer)
        let profile = RemoteConnectionProfile(
            id: UUID(),
            name: "Remote Dev",
            host: "dev.internal"
        )
        await manager.connect(profile: profile)

        let scanner = RemotePortScanner(
            multiplexer: multiplexer,
            connectionManager: manager,
            localPortCandidates: { remotePort, _ in
                remotePort == 3000 ? [53_000] : [55_173]
            },
            localPortAvailability: { _ in true }
        )
        multiplexer.remoteCommandResults[
            "ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null"
        ] = ProcessResult(
            exitCode: 0,
            stdout: """
            LISTEN 0 128 127.0.0.1:3000 *:* users:(("node",pid=1,fd=3))
            LISTEN 0 128 127.0.0.1:5173 *:* users:(("vite",pid=2,fd=4))
            """,
            stderr: ""
        )
        scanner.startScanning(profileID: profile.id, performInitialScan: false)
        await scanner.refreshNow()
        await scanner.forwardDetectedPort(3000)
        await scanner.forwardDetectedPort(5173)
        let leaseObserver = scanner.$forwardedPortMappings
            .dropFirst()
            .sink { mappings in
                if mappings.isEmpty {
                    multiplexer.lifecycleEvents.append("leases-cleared")
                }
            }

        scanner.stopScanning()

        #expect(multiplexer.lifecycleEvents == [
            "leases-cleared",
            "cancel",
            "cancel",
        ])
        #expect(multiplexer.cancelled == [
            .local(localPort: 53_000, remotePort: 3000),
            .local(localPort: 55_173, remotePort: 5173),
        ])
        #expect(scanner.scanningProfileID == nil)
        #expect(scanner.detectedPorts.isEmpty)
        #expect(scanner.forwardedPorts.isEmpty)
        #expect(scanner.forwardedPortMappings.isEmpty)
        #expect(scanner.browserOpenSuggestions.isEmpty)
        _ = leaseObserver
    }
}
