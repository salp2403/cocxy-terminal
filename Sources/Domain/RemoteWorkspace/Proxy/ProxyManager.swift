// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProxyManager.swift - Authenticated proxy session lifecycle.

import Combine
import Foundation

// MARK: - Proxy State

/// Secret-free public state for the single active proxy session.
enum ProxyState: Equatable, Sendable {
    case off
    case starting(profileID: UUID)
    case active(profileID: UUID, socksPort: Int, httpPort: Int?)
    case failing(profileID: UUID?, reason: String)
    case failover(profileID: UUID)

    var profileID: UUID? {
        switch self {
        case .off:
            return nil
        case .starting(let profileID),
             .active(let profileID, _, _),
             .failover(let profileID):
            return profileID
        case .failing(let profileID, _):
            return profileID
        }
    }
}

enum ProxyError: Error, Equatable, LocalizedError {
    case socksNotActive
    case invalidPort
    case httpConnectFailed(String)
    case systemProxyFailed(String)

    var errorDescription: String? {
        switch self {
        case .socksNotActive:
            return "The authenticated SOCKS5 proxy is not active for this profile"
        case .invalidPort:
            return "Invalid proxy port"
        case .httpConnectFailed(let reason), .systemProxyFailed(let reason):
            return reason
        }
    }
}

// MARK: - SSH Authority

@MainActor
protocol PortForwarding: AnyObject {
    func connectionLeaseID(for profileID: UUID) -> UUID?

    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) async throws

    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) async throws

    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID,
        expectedConnectionLeaseID: UUID
    ) async throws

    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID,
        expectedConnectionLeaseID: UUID
    ) async throws

    func openProxyTransport(
        to target: ProxyTarget,
        for profileID: UUID,
        expectedConnectionLeaseID: UUID
    ) throws -> any ProxyUpstreamTransport
}

extension PortForwarding {
    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID,
        expectedConnectionLeaseID: UUID
    ) async throws {
        guard connectionLeaseID(for: profileID) == expectedConnectionLeaseID else {
            throw SSHMultiplexerError.notConnected
        }
        try await forwardPort(forward, for: profileID)
        guard connectionLeaseID(for: profileID) == expectedConnectionLeaseID else {
            throw SSHMultiplexerError.notConnected
        }
    }

    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID,
        expectedConnectionLeaseID: UUID
    ) async throws {
        guard connectionLeaseID(for: profileID) == expectedConnectionLeaseID else {
            throw SSHMultiplexerError.notConnected
        }
        try await cancelForward(forward, for: profileID)
        guard connectionLeaseID(for: profileID) == expectedConnectionLeaseID else {
            throw SSHMultiplexerError.notConnected
        }
    }

    func openProxyTransport(
        to target: ProxyTarget,
        for profileID: UUID,
        expectedConnectionLeaseID: UUID
    ) throws -> any ProxyUpstreamTransport {
        _ = target
        _ = profileID
        _ = expectedConnectionLeaseID
        throw ProxyUpstreamTransportError.unavailable
    }
}

// MARK: - Public Lifecycle

@MainActor
protocol ProxyManaging: AnyObject {
    var state: ProxyState { get }
    var statePublisher: AnyPublisher<ProxyState, Never> { get }
    func enableSOCKS(port: Int, profileID: UUID) async throws
    func enableHTTPConnect(port: Int, profileID: UUID) async throws
    func disableHTTPConnect(profileID: UUID) async
    func disable(profileID: UUID) async
    func healthCheck() async -> Bool
}

// MARK: - Proxy Manager

@MainActor
final class ProxyManagerImpl: ProxyManaging, ObservableObject {
    typealias SOCKS5ProxyFactory = @MainActor (
        _ port: Int,
        _ credentials: ProxyCredentials,
        _ forwarder: any PortForwarding,
        _ profileID: UUID,
        _ connectionLeaseID: UUID
    ) -> any SOCKS5ProxyLifecycle

    typealias HTTPConnectProxyFactory = @MainActor (
        _ port: Int,
        _ credentials: ProxyCredentials,
        _ forwarder: any PortForwarding,
        _ profileID: UUID,
        _ connectionLeaseID: UUID
    ) -> any HTTPConnectProxyLifecycle

    private struct ActiveProxySession {
        let id: UUID
        let profileID: UUID
        let connectionLeaseID: UUID
        let credentials: ProxyCredentials
        let socksProxy: any SOCKS5ProxyLifecycle
    }

    private struct PendingSOCKSStart {
        let profileID: UUID
        let connectionLeaseID: UUID
        let proxy: any SOCKS5ProxyLifecycle
    }

    @Published private var publishedState: ProxyState = .off
    @Published private(set) var uptimeSeconds: TimeInterval = 0
    private(set) var activeSince: Date?
    private let committedState = CurrentValueSubject<ProxyState, Never>(.off)

    var state: ProxyState { publishedState }

    var statePublisher: AnyPublisher<ProxyState, Never> {
        committedState.eraseToAnyPublisher()
    }

    private weak var forwarder: (any PortForwarding)?
    private let socks5ProxyFactory: SOCKS5ProxyFactory
    private let httpConnectProxyFactory: HTTPConnectProxyFactory

    private var activeSession: ActiveProxySession?
    private var activeHTTPConnectCredentials: ProxyCredentials?
    private(set) var socksProxy: (any SOCKS5ProxyLifecycle)?
    private(set) var httpConnectProxy: (any HTTPConnectProxyLifecycle)?
    private var pendingSOCKSProxies: [UInt64: PendingSOCKSStart] = [:]
    private var pendingHTTPConnectProxies: [UInt64: any HTTPConnectProxyLifecycle] = [:]
    private var socksGeneration: UInt64 = 0
    private var httpGeneration: UInt64 = 0
    private var pendingStatePublications: [ProxyState] = []
    private var isPublishingState = false

    var hasTrackedSOCKSForward: Bool { activeSession != nil }
    var activeProfileID: UUID? { activeSession?.profileID }

    init(
        tunnelManager: SSHTunnelManager,
        forwarder: any PortForwarding,
        socks5ProxyFactory: @escaping SOCKS5ProxyFactory = {
            port, credentials, forwarder, profileID, connectionLeaseID in
            SOCKS5Proxy(
                listenPort: port,
                credentials: credentials,
                forwarder: forwarder,
                profileID: profileID,
                connectionLeaseID: connectionLeaseID
            )
        },
        httpConnectProxyFactory: @escaping HTTPConnectProxyFactory = {
            port, credentials, forwarder, profileID, connectionLeaseID in
            HTTPConnectProxy(
                listenPort: port,
                credentials: credentials,
                forwarder: forwarder,
                profileID: profileID,
                connectionLeaseID: connectionLeaseID
            )
        }
    ) {
        _ = tunnelManager
        self.forwarder = forwarder
        self.socks5ProxyFactory = socks5ProxyFactory
        self.httpConnectProxyFactory = httpConnectProxyFactory
    }

    /// Returns the in-memory capability only to the owning profile's UI.
    func credentials(for profileID: UUID) -> ProxyCredentials? {
        guard activeSession?.profileID == profileID else { return nil }
        return activeSession?.credentials
    }

    /// Returns the independently rotated HTTP capability to its owning UI.
    func httpConnectCredentials(for profileID: UUID) -> ProxyCredentials? {
        guard activeSession?.profileID == profileID,
              httpConnectProxy != nil else { return nil }
        return activeHTTPConnectCredentials
    }

    func enableSOCKS(port: Int, profileID: UUID) async throws {
        guard (1...65_535).contains(port) else { throw ProxyError.invalidPort }
        guard let forwarder else {
            publishState(.failing(profileID: profileID, reason: "SSH authority is unavailable"))
            throw ProxyUpstreamTransportError.unavailable
        }
        guard let connectionLeaseID = forwarder.connectionLeaseID(for: profileID) else {
            publishState(.failing(profileID: profileID, reason: "No active SSH connection"))
            throw SSHMultiplexerError.notConnected
        }
        try Task.checkCancellation()

        stopCurrentSession()
        let generation = invalidatePendingSOCKSStarts()
        let credentials = ProxyCredentials.generate()
        let sessionID = UUID()
        let proxy = socks5ProxyFactory(
            port,
            credentials,
            forwarder,
            profileID,
            connectionLeaseID
        )
        proxy.failureHandler = { [weak self] reason in
            self?.handleSOCKSListenerFailure(
                sessionID: sessionID,
                generation: generation,
                profileID: profileID,
                reason: reason
            )
        }
        pendingSOCKSProxies[generation] = PendingSOCKSStart(
            profileID: profileID,
            connectionLeaseID: connectionLeaseID,
            proxy: proxy
        )
        publishState(.starting(profileID: profileID))

        do {
            try await proxy.start()
            try Task.checkCancellation()
        } catch {
            let wasPending = pendingSOCKSProxies.removeValue(forKey: generation) != nil
            if wasPending { proxy.stop() }
            if error is CancellationError {
                if socksGeneration == generation {
                    socksGeneration &+= 1
                    clearPublishedSessionState()
                }
                throw error
            }
            guard socksGeneration == generation else { throw ProxyError.socksNotActive }
            publishState(.failing(profileID: profileID, reason: error.localizedDescription))
            throw error
        }

        let wasPending = pendingSOCKSProxies.removeValue(forKey: generation) != nil
        guard wasPending, socksGeneration == generation else {
            proxy.stop()
            throw ProxyError.socksNotActive
        }
        guard forwarder.connectionLeaseID(for: profileID) == connectionLeaseID,
              proxy.isReady else {
            proxy.stop()
            publishState(.failing(
                profileID: profileID,
                reason: "SSH connection changed before proxy activation"
            ))
            throw ProxyError.socksNotActive
        }
        do {
            try Task.checkCancellation()
        } catch {
            proxy.stop()
            if socksGeneration == generation {
                socksGeneration &+= 1
                clearPublishedSessionState()
            }
            throw error
        }

        let session = ActiveProxySession(
            id: sessionID,
            profileID: profileID,
            connectionLeaseID: connectionLeaseID,
            credentials: credentials,
            socksProxy: proxy
        )
        activeSession = session
        socksProxy = proxy
        activeSince = Date()
        uptimeSeconds = 0
        proxy.activate()
        publishState(.active(profileID: profileID, socksPort: port, httpPort: nil))
    }

    func enableHTTPConnect(port: Int, profileID: UUID) async throws {
        guard (1...65_535).contains(port) else { throw ProxyError.invalidPort }
        guard let session = activeSession,
              session.profileID == profileID,
              let forwarder,
              forwarder.connectionLeaseID(for: profileID) == session.connectionLeaseID else {
            throw ProxyError.socksNotActive
        }
        try Task.checkCancellation()

        stopHTTPConnect()
        let generation = invalidatePendingHTTPStarts()
        publishState(.active(
            profileID: profileID,
            socksPort: session.socksProxy.port,
            httpPort: nil
        ))
        let credentials = ProxyCredentials.generate()
        let proxy = httpConnectProxyFactory(
            port,
            credentials,
            forwarder,
            profileID,
            session.connectionLeaseID
        )
        proxy.failureHandler = { [weak self] reason in
            self?.handleHTTPListenerFailure(
                sessionID: session.id,
                generation: generation,
                profileID: profileID,
                reason: reason
            )
        }
        pendingHTTPConnectProxies[generation] = proxy

        do {
            try await proxy.start()
            try Task.checkCancellation()
        } catch {
            let wasPending = pendingHTTPConnectProxies.removeValue(forKey: generation) != nil
            if wasPending { proxy.stop() }
            if error is CancellationError {
                if httpGeneration == generation {
                    httpGeneration &+= 1
                }
                throw error
            }
            guard httpGeneration == generation else { throw ProxyError.socksNotActive }
            throw ProxyError.httpConnectFailed(error.localizedDescription)
        }

        let wasPending = pendingHTTPConnectProxies.removeValue(forKey: generation) != nil
        guard wasPending,
              httpGeneration == generation,
              let current = activeSession,
              current.id == session.id,
              forwarder.connectionLeaseID(for: profileID) == session.connectionLeaseID,
              proxy.isReady else {
            proxy.stop()
            throw ProxyError.socksNotActive
        }
        do {
            try Task.checkCancellation()
        } catch {
            proxy.stop()
            if httpGeneration == generation {
                httpGeneration &+= 1
            }
            throw error
        }

        httpConnectProxy = proxy
        activeHTTPConnectCredentials = credentials
        proxy.activate()
        publishState(.active(
            profileID: profileID,
            socksPort: session.socksProxy.port,
            httpPort: port
        ))
    }

    func disableHTTPConnect(profileID: UUID) async {
        guard let session = activeSession, session.profileID == profileID else { return }
        stopHTTPConnect()
        publishState(.active(
            profileID: profileID,
            socksPort: session.socksProxy.port,
            httpPort: nil
        ))
    }

    func disable(profileID: UUID) async {
        guard state.profileID == profileID else { return }
        stopCurrentSession()
    }

    /// Invalidates credentials and listeners before ControlMaster termination.
    func prepareForSessionTermination(profileID: UUID, connectionLeaseID: UUID?) {
        if let session = activeSession,
           session.profileID == profileID,
           connectionLeaseID.map({ $0 == session.connectionLeaseID }) ?? true {
            stopCurrentSession()
            return
        }
        let hasMatchingPendingStart = pendingSOCKSProxies.values.contains { pending in
            pending.profileID == profileID
                && (connectionLeaseID.map { $0 == pending.connectionLeaseID } ?? true)
        }
        if hasMatchingPendingStart {
            stopCurrentSession()
        }
    }

    func releaseAfterSessionTermination(profileID: UUID, connectionLeaseID: UUID) {
        guard let session = activeSession,
              session.profileID == profileID,
              session.connectionLeaseID == connectionLeaseID else { return }
        activeSession = nil
        socksProxy = nil
        stopHTTPConnect(releasingAfterSessionTermination: true)
        session.socksProxy.releaseAfterSessionTermination()
        clearPublishedSessionState()
    }

    func healthCheck() async -> Bool {
        guard let session = activeSession,
              session.socksProxy.isReady,
              forwarder?.connectionLeaseID(for: session.profileID) == session.connectionLeaseID else {
            return false
        }
        return httpConnectProxy?.isReady ?? true
    }

    private func handleSOCKSListenerFailure(
        sessionID: UUID,
        generation: UInt64,
        profileID: UUID,
        reason: String
    ) {
        guard socksGeneration == generation,
              activeSession?.id == sessionID else { return }
        stopCurrentSession()
        publishState(.failing(profileID: profileID, reason: reason))
    }

    private func handleHTTPListenerFailure(
        sessionID: UUID,
        generation: UInt64,
        profileID: UUID,
        reason: String
    ) {
        guard httpGeneration == generation,
              activeSession?.id == sessionID,
              httpConnectProxy != nil else { return }
        stopCurrentSession()
        publishState(.failing(profileID: profileID, reason: reason))
    }

    private func stopCurrentSession() {
        socksGeneration &+= 1
        httpGeneration &+= 1
        stopPendingStarts()
        guard let session = activeSession else {
            socksProxy = nil
            stopHTTPConnect()
            clearPublishedSessionState()
            return
        }

        // Drop the capability reference before any listener teardown callback.
        activeSession = nil
        socksProxy = nil
        stopHTTPConnect()
        session.socksProxy.stop()
        clearPublishedSessionState()
    }

    private func stopHTTPConnect(releasingAfterSessionTermination: Bool = false) {
        httpGeneration &+= 1
        activeHTTPConnectCredentials = nil
        let pending = Array(pendingHTTPConnectProxies.values)
        pendingHTTPConnectProxies.removeAll()
        for proxy in pending {
            if releasingAfterSessionTermination {
                proxy.releaseAfterSessionTermination()
            } else {
                proxy.stop()
            }
        }
        if let proxy = httpConnectProxy {
            if releasingAfterSessionTermination {
                proxy.releaseAfterSessionTermination()
            } else {
                proxy.stop()
            }
            httpConnectProxy = nil
        }
    }

    @discardableResult
    private func invalidatePendingSOCKSStarts() -> UInt64 {
        socksGeneration &+= 1
        let pending = Array(pendingSOCKSProxies.values)
        pendingSOCKSProxies.removeAll()
        for start in pending { start.proxy.stop() }
        return socksGeneration
    }

    @discardableResult
    private func invalidatePendingHTTPStarts() -> UInt64 {
        httpGeneration &+= 1
        let pending = Array(pendingHTTPConnectProxies.values)
        pendingHTTPConnectProxies.removeAll()
        for proxy in pending { proxy.stop() }
        return httpGeneration
    }

    private func stopPendingStarts() {
        let socks = Array(pendingSOCKSProxies.values)
        pendingSOCKSProxies.removeAll()
        for start in socks { start.proxy.stop() }
        let http = Array(pendingHTTPConnectProxies.values)
        pendingHTTPConnectProxies.removeAll()
        for proxy in http { proxy.stop() }
    }

    private func clearPublishedSessionState() {
        activeSince = nil
        uptimeSeconds = 0
        publishState(.off)
    }

    /// Serializes reentrant lifecycle changes so every observer receives the
    /// same committed order, including teardown requested from inside a sink.
    private func publishState(_ state: ProxyState) {
        pendingStatePublications.append(state)
        guard !isPublishingState else { return }

        isPublishingState = true
        defer { isPublishingState = false }
        while !pendingStatePublications.isEmpty {
            let nextState = pendingStatePublications.removeFirst()
            publishedState = nextState
            committedState.send(nextState)
        }
    }
}
