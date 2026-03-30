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

    /// Weak to break retain cycle: RemoteConnectionManager → ProxyManagerImpl → forwarder.
    private weak var forwarder: (any PortForwarding)?

    // MARK: - Internal State

    private var activeProfileID: UUID?
    private var socksPort: Int?
    private var httpConnectPort: Int?
    private(set) var httpConnectProxy: HTTPConnectProxy?
    private var healthMonitor: ProxyHealthMonitor?

    // MARK: - Initialization

    /// Creates a proxy manager with injected dependencies.
    ///
    /// - Parameters:
    ///   - tunnelManager: Tracks active tunnels for UI display.
    ///   - forwarder: Executes SSH port forwarding commands (weak to avoid retain cycle).
    init(tunnelManager: SSHTunnelManager, forwarder: any PortForwarding) {
        self.tunnelManager = tunnelManager
        self.forwarder = forwarder
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
        state = .starting
        activeProfileID = profileID

        guard let forwarder else {
            state = .failing(reason: "Port forwarder unavailable")
            throw ProxyError.httpConnectFailed("Port forwarder deallocated")
        }

        let forward = RemoteConnectionProfile.PortForward.dynamic(localPort: port)

        do {
            try forwarder.forwardPort(forward, for: profileID)
        } catch {
            state = .failing(reason: errorDescription(error))
            throw error
        }

        tunnelManager.addTunnel(forward: forward, for: profileID)
        socksPort = port
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
        guard let currentSOCKSPort = socksPort else {
            throw ProxyError.socksNotActive
        }
        guard let forwarder else {
            throw ProxyError.httpConnectFailed("Port forwarder unavailable")
        }

        // Stop existing HTTP CONNECT proxy if running.
        httpConnectProxy?.stop()

        // Create and start the HTTP CONNECT proxy.
        let proxy = HTTPConnectProxy(
            listenPort: port,
            forwarder: forwarder,
            profileID: profileID
        )
        do {
            try proxy.start()
        } catch {
            throw ProxyError.httpConnectFailed(error.localizedDescription)
        }

        httpConnectProxy = proxy
        httpConnectPort = port
        state = .active(socksPort: currentSOCKSPort, httpPort: port)
    }

    // MARK: - Disable

    /// Shuts down all proxy services and cleans up tunnels.
    ///
    /// Cancels the SOCKS5 forward, stops HTTP CONNECT if active,
    /// and removes all tracked tunnels for the profile.
    func disable(profileID: UUID) async {
        // Stop health monitoring.
        healthMonitor?.stopMonitoring()
        healthMonitor = nil

        // Stop HTTP CONNECT proxy.
        httpConnectProxy?.stop()
        httpConnectProxy = nil

        // Cancel SOCKS5 forward.
        if let port = socksPort, let forwarder {
            let forward = RemoteConnectionProfile.PortForward.dynamic(localPort: port)
            try? forwarder.cancelForward(forward, for: profileID)
        }

        tunnelManager.removeAllTunnels(for: profileID)

        socksPort = nil
        httpConnectPort = nil
        activeProfileID = nil
        state = .off
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
            if let port = socksPort {
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
