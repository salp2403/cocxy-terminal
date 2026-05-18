// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemotePortScannerBrowserRouteSwiftTestingTests.swift - Browser routing tests for remote port discovery.

import Foundation
import Testing
@testable import CocxyTerminal

private final class RemotePortScannerMultiplexer: SSHMultiplexing, @unchecked Sendable {
    var attemptedForwards: [RemoteConnectionProfile.PortForward] = []
    var forwarded: [RemoteConnectionProfile.PortForward] = []
    var cancelled: [RemoteConnectionProfile.PortForward] = []
    var failingLocalPorts: Set<Int> = []
    var remoteCommandResults: [String: ProcessResult] = [:]

    func connect(profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws {}

    func disconnect(profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws {}

    func isAlive(profile: RemoteConnectionProfile, executor: any ProcessExecutor) async throws -> Bool {
        true
    }

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

    @Test("Auto-forward falls back to browser-safe local port and publishes suggestion")
    @MainActor func autoForwardPublishesBrowserSuggestionWithFallbackPort() async throws {
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

    @Test("Auto-forward skips locally bound candidate before publishing suggestion")
    @MainActor func autoForwardSkipsLocallyBoundCandidate() async throws {
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
        #expect(scanner.scanningProfileID == first.id)
        #expect(scanner.forwardedPortMappings[3000] == 53_000)
        #expect(scanner.browserOpenSuggestions.count == 1)

        scanner.startScanning(profileID: second.id, performInitialScan: false)

        #expect(scanner.scanningProfileID == second.id)
        #expect(scanner.forwardedPortMappings.isEmpty)
        #expect(scanner.browserOpenSuggestions.isEmpty)
    }
}
