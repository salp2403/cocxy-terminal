// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteBrowserProxySession.swift - Window-scoped remote browser capability.

import Foundation

struct RemoteBrowserProxyCapability: Equatable, Sendable {
    let id: UUID
    let ownerWindowID: WindowID
    let profileID: UUID
    let remotePort: Int
    let localProxyPort: Int
    let credentials: ProxyCredentials
    let expiresAt: Date

    /// A non-resolving browser origin that WebKit cannot bypass to local TCP.
    /// The broker maps this stable, window-scoped alias to remote localhost.
    var browserHost: String {
        Self.browserHost(for: ownerWindowID)
    }

    static func browserHost(for ownerWindowID: WindowID) -> String {
        "cocxy-\(ownerWindowID.rawValue.uuidString.lowercased()).invalid"
    }
}

enum RemoteBrowserProxyInvalidation: Equatable, Sendable {
    case expired
    case listenerFailed(String)
}

enum RemoteBrowserProxySessionError: Error, Equatable, LocalizedError {
    case invalidRemotePort
    case invalidLifetime
    case connectionUnavailable
    case connectionChanged
    case noAvailableProxyPort

    var errorDescription: String? {
        switch self {
        case .invalidRemotePort:
            return "Invalid remote browser port"
        case .invalidLifetime:
            return "Invalid remote browser capability lifetime"
        case .connectionUnavailable:
            return "The remote connection is unavailable"
        case .connectionChanged:
            return "The remote connection changed during browser setup"
        case .noAvailableProxyPort:
            return "No protected local proxy port is available"
        }
    }
}

/// Owns one authenticated SOCKS listener for one window, profile, and remote
/// service. The capability never leaves memory and is revoked with the session.
@MainActor
final class RemoteBrowserProxySession {
    typealias ProxyFactory = @MainActor (
        _ port: Int,
        _ credentials: ProxyCredentials,
        _ forwarder: any PortForwarding,
        _ profileID: UUID,
        _ connectionLeaseID: UUID,
        _ targetMappings: [ProxyTarget: ProxyTarget]
    ) -> any SOCKS5ProxyLifecycle

    typealias PortCandidateProvider = @MainActor () -> [Int]

    static let defaultLifetime: TimeInterval = 30 * 60
    static let renewalLeadTime: TimeInterval = 5 * 60
    private static let maximumLifetime = TimeInterval(UInt64.max / 1_000_000_000)

    let ownerWindowID: WindowID
    let profileID: UUID
    let remotePort: Int

    var invalidationHandler: (@MainActor (RemoteBrowserProxyInvalidation) -> Void)?
    private(set) var capability: RemoteBrowserProxyCapability?

    private weak var forwarder: (any PortForwarding)?
    private let lifetime: TimeInterval
    private let portCandidates: PortCandidateProvider
    private let proxyFactory: ProxyFactory
    private var proxy: (any SOCKS5ProxyLifecycle)?
    private var expirationTask: Task<Void, Never>?

    init(
        ownerWindowID: WindowID,
        profileID: UUID,
        remotePort: Int,
        forwarder: any PortForwarding,
        lifetime: TimeInterval = RemoteBrowserProxySession.defaultLifetime,
        portCandidates: @escaping PortCandidateProvider = RemoteBrowserProxySession.defaultPortCandidates,
        proxyFactory: @escaping ProxyFactory = {
            port, credentials, forwarder, profileID, connectionLeaseID, targetMappings in
            SOCKS5Proxy(
                listenPort: port,
                credentials: credentials,
                forwarder: forwarder,
                profileID: profileID,
                connectionLeaseID: connectionLeaseID,
                allowedTargets: Set(targetMappings.keys),
                targetMappings: targetMappings
            )
        }
    ) {
        self.ownerWindowID = ownerWindowID
        self.profileID = profileID
        self.remotePort = remotePort
        self.forwarder = forwarder
        self.lifetime = lifetime
        self.portCandidates = portCandidates
        self.proxyFactory = proxyFactory
    }

    deinit {
        expirationTask?.cancel()
    }

    func start() async throws -> RemoteBrowserProxyCapability {
        if let capability { return capability }
        guard (1...65_535).contains(remotePort) else {
            throw RemoteBrowserProxySessionError.invalidRemotePort
        }
        guard lifetime.isFinite,
              lifetime > 0,
              lifetime <= Self.maximumLifetime else {
            throw RemoteBrowserProxySessionError.invalidLifetime
        }
        guard let forwarder,
              let connectionLeaseID = forwarder.connectionLeaseID(for: profileID) else {
            throw RemoteBrowserProxySessionError.connectionUnavailable
        }

        let browserHost = RemoteBrowserProxyCapability.browserHost(for: ownerWindowID)
        let targetMappings = try Self.targetMappings(
            browserHost: browserHost,
            remotePort: remotePort
        )
        let credentials = ProxyCredentials.generate()
        let candidates = Self.normalizedCandidates(portCandidates())

        for port in candidates {
            try Task.checkCancellation()
            let candidate = proxyFactory(
                port,
                credentials,
                forwarder,
                profileID,
                connectionLeaseID,
                targetMappings
            )
            candidate.failureHandler = { [weak self] reason in
                self?.invalidate(.listenerFailed(reason))
            }

            do {
                try await candidate.start()
                try Task.checkCancellation()
            } catch {
                candidate.stop()
                if error is CancellationError { throw error }
                continue
            }

            guard forwarder.connectionLeaseID(for: profileID) == connectionLeaseID else {
                candidate.stop()
                throw RemoteBrowserProxySessionError.connectionChanged
            }

            let expiration = Date().addingTimeInterval(lifetime)
            let capability = RemoteBrowserProxyCapability(
                id: UUID(),
                ownerWindowID: ownerWindowID,
                profileID: profileID,
                remotePort: remotePort,
                localProxyPort: port,
                credentials: credentials,
                expiresAt: expiration
            )
            self.proxy = candidate
            self.capability = capability
            candidate.activate()
            scheduleExpiration(after: lifetime)
            return capability
        }

        throw RemoteBrowserProxySessionError.noAvailableProxyPort
    }

    func stop() {
        expirationTask?.cancel()
        expirationTask = nil
        proxy?.stop()
        proxy = nil
        capability = nil
    }

    private func scheduleExpiration(after interval: TimeInterval) {
        expirationTask?.cancel()
        let nanoseconds = UInt64(interval * 1_000_000_000)
        expirationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            self?.invalidate(.expired)
        }
    }

    private func invalidate(_ reason: RemoteBrowserProxyInvalidation) {
        guard capability != nil else { return }
        let handler = invalidationHandler
        stop()
        handler?(reason)
    }

    private static func targetMappings(
        browserHost: String,
        remotePort: Int
    ) throws -> [ProxyTarget: ProxyTarget] {
        [
            try ProxyTarget(host: browserHost, port: remotePort):
                try ProxyTarget(host: "localhost", port: remotePort),
        ]
    }

    private static func normalizedCandidates(_ candidates: [Int]) -> [Int] {
        var seen = Set<Int>()
        return candidates.filter { candidate in
            (1...65_535).contains(candidate) && seen.insert(candidate).inserted
        }
    }

    private static func defaultPortCandidates() -> [Int] {
        var candidates: [Int] = []
        var seen = Set<Int>()
        while candidates.count < 64 {
            let candidate = Int.random(in: 49_152...65_535)
            if seen.insert(candidate).inserted {
                candidates.append(candidate)
            }
        }
        return candidates
    }
}
