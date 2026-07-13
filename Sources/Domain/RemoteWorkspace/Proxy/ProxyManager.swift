// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProxyManager.swift - SOCKS5 proxy lifecycle management with state machine.

import Foundation
import Combine

// MARK: - Proxy State

/// Represents the operational state of the proxy subsystem.
///
/// Transitions follow a strict state machine:
/// `.off` → `.starting` → `.active` → `.failing` → `.failover` → `.active` or `.off`
enum ProxyState: Equatable, Sendable {
    case off
    case starting
    case active(socksPort: Int, httpPort: Int?)
    case failing(reason: String)
    case failover
}

// MARK: - Proxy Error

/// Errors that can occur during proxy operations.
enum ProxyError: Error, Equatable {
    case socksNotActive
    case httpConnectFailed(String)
    case systemProxyFailed(String)
}

// MARK: - Port Forwarding Protocol

/// Abstraction for SSH port forwarding operations.
///
/// `RemoteConnectionManager` conforms to this protocol, allowing tests
/// to inject a mock without real SSH connections.
@MainActor
protocol PortForwarding: AnyObject {
    /// Identifies the currently connected SSH session for one profile.
    func connectionLeaseID(for profileID: UUID) -> UUID?

    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) throws

    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) throws
}

// MARK: - Proxy Managing Protocol

/// Defines the public API for proxy lifecycle management.
///
/// Implementations handle the SOCKS5 tunnel via SSH dynamic forwarding
/// and an optional HTTP CONNECT proxy layered on top.
@MainActor
protocol ProxyManaging: AnyObject {
    var state: ProxyState { get }
    var statePublisher: AnyPublisher<ProxyState, Never> { get }
    func enableSOCKS(port: Int, profileID: UUID) async throws
    func enableHTTPConnect(port: Int, profileID: UUID) async throws
    func disable(profileID: UUID) async
    func healthCheck() async -> Bool
}

// MARK: - ProxyManagerImpl

/// Concrete implementation of `ProxyManaging`.
///
/// Orchestrates the SOCKS5 dynamic forward via `PortForwarding` (SSH `-D` flag)
/// and tracks the tunnel in `SSHTunnelManager` for UI display.
///
/// ## Usage
///
/// ```swift
/// let proxy = ProxyManagerImpl(tunnelManager: tunnelManager, forwarder: connectionManager)
/// try await proxy.enableSOCKS(port: 1080, profileID: profile.id)
/// // SOCKS5 proxy now listening on localhost:1080
/// ```
@MainActor
final class ProxyManagerImpl: ProxyManaging, ObservableObject {

    typealias HTTPConnectProxyFactory = @MainActor (
        _ port: Int,
        _ forwarder: any PortForwarding,
        _ profileID: UUID,
        _ connectionLeaseID: UUID
    ) -> any HTTPConnectProxyLifecycle

    private struct ActiveSOCKSForward {
        let profileID: UUID
        let connectionLeaseID: UUID
        let forward: RemoteConnectionProfile.PortForward
        let tunnelID: UUID
    }

    // MARK: - Published State

    @Published private(set) var state: ProxyState = .off

    /// Uptime since SOCKS was enabled (in seconds).
    @Published private(set) var uptimeSeconds: TimeInterval = 0

    /// Timestamp when SOCKS was activated.
    private(set) var activeSince: Date?

    var statePublisher: AnyPublisher<ProxyState, Never> {
        $state.eraseToAnyPublisher()
    }

    // MARK: - Dependencies

    private let tunnelManager: SSHTunnelManager
    private let httpConnectProxyFactory: HTTPConnectProxyFactory

    /// Weak to break retain cycle: RemoteConnectionManager → ProxyManagerImpl → forwarder.
    private weak var forwarder: (any PortForwarding)?

    // MARK: - Internal State

    private var activeSOCKSForward: ActiveSOCKSForward?
    private var httpConnectPort: Int?
    private(set) var httpConnectProxy: (any HTTPConnectProxyLifecycle)?
    private var httpConnectGeneration: UInt64 = 0
    private var pendingHTTPConnectProxies: [UInt64: any HTTPConnectProxyLifecycle] = [:]
    private var healthMonitor: ProxyHealthMonitor?

    var hasTrackedSOCKSForward: Bool {
        activeSOCKSForward != nil
    }

    // MARK: - Initialization

    /// Creates a proxy manager with injected dependencies.
    ///
    /// - Parameters:
    ///   - tunnelManager: Tracks active tunnels for UI display.
    ///   - forwarder: Executes SSH port forwarding commands (weak to avoid retain cycle).
    init(
        tunnelManager: SSHTunnelManager,
        forwarder: any PortForwarding,
        httpConnectProxyFactory: @escaping HTTPConnectProxyFactory = {
            port,
            forwarder,
            profileID,
            connectionLeaseID in
            HTTPConnectProxy(
                listenPort: port,
                forwarder: forwarder,
                profileID: profileID,
                connectionLeaseID: connectionLeaseID
            )
        }
    ) {
        self.tunnelManager = tunnelManager
        self.forwarder = forwarder
        self.httpConnectProxyFactory = httpConnectProxyFactory
    }

    // MARK: - Enable SOCKS5

    /// Activates a SOCKS5 dynamic forward on the given local port.
    ///
    /// Creates an SSH `-D` forward via the `PortForwarding` dependency
    /// and registers the tunnel for tracking.
    ///
    /// - Parameters:
    ///   - port: Local port for the SOCKS5 listener (e.g., 1080).
    ///   - profileID: The remote profile whose SSH session carries the forward.
    func enableSOCKS(port: Int, profileID: UUID) async throws {
        guard let forwarder else {
            if activeSOCKSForward == nil {
                state = .failing(reason: "Port forwarder unavailable")
            }
            throw ProxyError.httpConnectFailed("Port forwarder deallocated")
        }
        guard let connectionLeaseID = forwarder.connectionLeaseID(for: profileID) else {
            let error = SSHMultiplexerError.connectionFailed(
                "No active connection lease for profile"
            )
            if activeSOCKSForward == nil {
                state = .failing(reason: errorDescription(error))
            }
            throw error
        }

        if let previous = activeSOCKSForward {
            try retireForReplacement(previous, using: forwarder)
        }

        state = .starting

        let forward = RemoteConnectionProfile.PortForward.dynamic(localPort: port)

        do {
            try forwarder.forwardPort(forward, for: profileID)
        } catch {
            state = .failing(reason: errorDescription(error))
            throw error
        }

        let tunnel = tunnelManager.addTunnel(forward: forward, for: profileID)
        activeSOCKSForward = ActiveSOCKSForward(
            profileID: profileID,
            connectionLeaseID: connectionLeaseID,
            forward: forward,
            tunnelID: tunnel.id
        )
        activeSince = Date()
        state = .active(socksPort: port, httpPort: httpConnectPort)

        // Start health monitoring.
        let probe = TCPHealthProbe()
        let monitor = ProxyHealthMonitor(probe: probe)
        monitor.delegate = self
        monitor.startMonitoring()
        healthMonitor = monitor
    }

    // MARK: - Enable HTTP CONNECT

    /// Activates an HTTP CONNECT proxy on the given local port.
    ///
    /// Requires SOCKS5 to be active first, since HTTP CONNECT routes
    /// through SSH local forwards created on demand.
    ///
    /// - Parameters:
    ///   - port: Local port for the HTTP CONNECT listener (e.g., 8888).
    ///   - profileID: The remote profile whose SSH session carries forwards.
    func enableHTTPConnect(port: Int, profileID: UUID) async throws {
        guard let ownership = activeSOCKSForward,
              ownership.profileID == profileID,
              case .dynamic(let currentSOCKSPort) = ownership.forward
        else {
            throw ProxyError.socksNotActive
        }
        guard let forwarder else {
            throw ProxyError.httpConnectFailed("Port forwarder unavailable")
        }
        guard forwarder.connectionLeaseID(for: profileID) == ownership.connectionLeaseID else {
            throw ProxyError.socksNotActive
        }

        // Invalidate any in-flight start before creating this listener.
        let startupGeneration: UInt64
        do {
            startupGeneration = try stopHTTPConnectProxy()
        } catch {
            state = .failing(reason: errorDescription(error))
            throw ProxyError.httpConnectFailed(errorDescription(error))
        }
        state = .active(socksPort: currentSOCKSPort, httpPort: nil)

        // Create and start the HTTP CONNECT proxy.
        let proxy = httpConnectProxyFactory(
            port,
            forwarder,
            profileID,
            ownership.connectionLeaseID
        )
        pendingHTTPConnectProxies[startupGeneration] = proxy
        do {
            try await proxy.start()
        } catch {
            let wasPending = pendingHTTPConnectProxies.removeValue(
                forKey: startupGeneration
            ) != nil
            if wasPending {
                try? proxy.stop()
            }
            if httpConnectGeneration != startupGeneration {
                throw ProxyError.socksNotActive
            }
            throw ProxyError.httpConnectFailed(error.localizedDescription)
        }

        let wasPending = pendingHTTPConnectProxies.removeValue(
            forKey: startupGeneration
        ) != nil

        guard httpConnectGeneration == startupGeneration,
              let currentOwnership = activeSOCKSForward,
              currentOwnership.profileID == ownership.profileID,
              currentOwnership.connectionLeaseID == ownership.connectionLeaseID,
              currentOwnership.tunnelID == ownership.tunnelID,
              forwarder.connectionLeaseID(for: profileID) == ownership.connectionLeaseID
        else {
            if wasPending {
                try? proxy.stop()
            }
            throw ProxyError.socksNotActive
        }

        httpConnectProxy = proxy
        httpConnectPort = port
        state = .active(socksPort: currentSOCKSPort, httpPort: port)
        proxy.activate()
    }

    // MARK: - Disable

    /// Shuts down proxy services owned by the selected profile.
    ///
    /// Cancels the SOCKS5 forward, stops HTTP CONNECT if active,
    /// and removes only the tunnel registered by this manager.
    func disable(profileID: UUID) async {
        guard let ownership = activeSOCKSForward,
              ownership.profileID == profileID
        else { return }

        do {
            try stopProxyFrontends()
        } catch {
            state = .failing(reason: errorDescription(error))
            return
        }
        guard let forwarder else {
            state = .failing(reason: "Port forwarder unavailable during proxy cleanup")
            return
        }
        if forwarder.connectionLeaseID(for: ownership.profileID) == ownership.connectionLeaseID {
            do {
                try forwarder.cancelForward(ownership.forward, for: ownership.profileID)
            } catch {
                state = .failing(reason: errorDescription(error))
                return
            }
        }

        finalizeCleanup(ownership)
    }

    /// Stops local listeners before an SSH session starts terminating, while
    /// retaining the exact SOCKS forward identity until cancellation or proven
    /// ControlMaster death completes.
    func prepareForSessionTermination(profileID: UUID, connectionLeaseID: UUID?) {
        guard let ownership = activeSOCKSForward,
              ownership.profileID == profileID,
              connectionLeaseID.map({ ownership.connectionLeaseID == $0 }) ?? true
        else { return }
        do {
            try stopProxyFrontends()
        } catch {
            state = .failing(reason: errorDescription(error))
        }
    }

    /// Releases local tracking without another `ssh -O cancel` only after the
    /// manager has proved the owning ControlMaster process terminated.
    func releaseAfterSessionTermination(profileID: UUID, connectionLeaseID: UUID) {
        guard let ownership = activeSOCKSForward,
              ownership.profileID == profileID,
              ownership.connectionLeaseID == connectionLeaseID
        else { return }
        releaseProxyFrontendsAfterSessionTermination()
        finalizeCleanup(ownership)
    }

    // MARK: - Health Check

    /// Verifies the proxy tunnel is operational.
    ///
    /// Returns `true` if the proxy is in an active state.
    /// Full TCP probe implementation is added by `ProxyHealthMonitor` (Task 5).
    func healthCheck() async -> Bool {
        guard case .active = state else { return false }
        return true
    }

    // MARK: - Helpers

    private func retireForReplacement(
        _ ownership: ActiveSOCKSForward,
        using forwarder: any PortForwarding
    ) throws {
        do {
            try stopProxyFrontends()
            if forwarder.connectionLeaseID(for: ownership.profileID) == ownership.connectionLeaseID {
                try forwarder.cancelForward(ownership.forward, for: ownership.profileID)
            }
        } catch {
            state = .failing(reason: errorDescription(error))
            throw error
        }
        finalizeCleanup(ownership)
    }

    private func finalizeCleanup(_ ownership: ActiveSOCKSForward) {
        guard activeSOCKSForward?.tunnelID == ownership.tunnelID else { return }

        tunnelManager.removeTunnel(id: ownership.tunnelID)

        activeSOCKSForward = nil
        httpConnectPort = nil
        activeSince = nil
        uptimeSeconds = 0
        state = .off
    }

    private func stopProxyFrontends() throws {
        healthMonitor?.delegate = nil
        healthMonitor?.stopMonitoring()
        healthMonitor = nil
        _ = try stopHTTPConnectProxy()
    }

    @discardableResult
    private func stopHTTPConnectProxy() throws -> UInt64 {
        httpConnectGeneration &+= 1
        let pendingProxies = Array(pendingHTTPConnectProxies.values)
        pendingHTTPConnectProxies.removeAll()
        for proxy in pendingProxies {
            try? proxy.stop()
        }
        httpConnectPort = nil

        if let proxy = httpConnectProxy {
            try proxy.stop()
            httpConnectProxy = nil
        }
        return httpConnectGeneration
    }

    private func releaseProxyFrontendsAfterSessionTermination() {
        healthMonitor?.delegate = nil
        healthMonitor?.stopMonitoring()
        healthMonitor = nil
        httpConnectGeneration &+= 1

        httpConnectProxy?.releaseAfterSessionTermination()
        httpConnectProxy = nil
        let pendingProxies = Array(pendingHTTPConnectProxies.values)
        pendingHTTPConnectProxies.removeAll()
        for proxy in pendingProxies {
            proxy.releaseAfterSessionTermination()
        }
        httpConnectPort = nil
    }

    private func errorDescription(_ error: any Error) -> String {
        if let sshError = error as? SSHMultiplexerError {
            return "\(sshError)"
        }
        return error.localizedDescription
    }
}

// MARK: - ProxyHealthDelegate Conformance

extension ProxyManagerImpl: ProxyHealthDelegate {

    func proxyHealthDidChange(to healthState: ProxyHealthState) {
        switch healthState {
        case .healthy:
            if let port = activeSOCKSForward?.forward.boundLocalPort {
                state = .active(socksPort: port, httpPort: httpConnectPort)
            }
        case .failing:
            state = .failing(reason: "Health check failed — tunnel may be down")
        case .degraded(let failures):
            // Keep active but log the degradation.
            NSLog("[ProxyManager] Health degraded: \(failures) consecutive failures")
        case .unknown:
            break
        }
    }
}
