// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProxyHealthMonitor.swift - TCP probe health monitoring with failover.

import Foundation
import Network

// MARK: - Health State

/// Represents the health status of the proxy tunnel.
enum ProxyHealthState: Equatable, Sendable {
    case unknown
    case healthy
    case degraded(consecutiveFailures: Int)
    case failing
}

// MARK: - Health Probing Protocol

/// Abstraction for TCP health probe. Enables testing without real network.
@MainActor
protocol HealthProbing: AnyObject {
    func probe() async -> Bool
}

// MARK: - Health Delegate Protocol

/// Notified when the health monitor detects a state change.
@MainActor
protocol ProxyHealthDelegate: AnyObject {
    func proxyHealthDidChange(to state: ProxyHealthState)
}

// MARK: - Proxy Health Monitor

/// Monitors the SOCKS5 tunnel health via periodic TCP probes.
///
/// Tracks consecutive failures and transitions through health states:
/// `.unknown` → `.healthy` → `.degraded` → `.failing`
///
/// When the threshold is reached (default 3 failures), the delegate
/// is notified so the `ProxyManager` can trigger failover or cleanup.
///
/// ## Usage
///
/// The monitor supports two modes:
/// 1. **Manual** — call `checkOnce()` directly (used in tests).
/// 2. **Automatic** — call `startMonitoring()` for periodic checks.
@MainActor
final class ProxyHealthMonitor {

    // MARK: - State

    /// Current health state.
    private(set) var state: ProxyHealthState = .unknown

    /// Delegate notified on state changes.
    weak var delegate: (any ProxyHealthDelegate)?

    // MARK: - Configuration

    /// Number of consecutive failures before transitioning to `.failing`.
    let consecutiveFailuresThreshold: Int

    /// Interval between automatic health checks (in seconds).
    let checkInterval: TimeInterval

    // MARK: - Internal

    private let probe: any HealthProbing
    private var consecutiveFailures = 0
    private var monitoringTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a health monitor.
    ///
    /// - Parameters:
    ///   - probe: The health check implementation.
    ///   - consecutiveFailuresThreshold: Failures before `.failing` state (default 3).
    ///   - checkInterval: Seconds between checks (default 10).
    init(
        probe: any HealthProbing,
        consecutiveFailuresThreshold: Int = 3,
        checkInterval: TimeInterval = 10.0
    ) {
        self.probe = probe
        self.consecutiveFailuresThreshold = consecutiveFailuresThreshold
        self.checkInterval = checkInterval
    }

    // MARK: - Single Check

    /// Runs a single health check and updates state accordingly.
    ///
    /// This is the core logic, used by both manual and automatic modes.
    func checkOnce() async {
        let isHealthy = await probe.probe()
        let previousState = state

        if isHealthy {
            consecutiveFailures = 0
            state = .healthy
        } else {
            consecutiveFailures += 1
            if consecutiveFailures >= consecutiveFailuresThreshold {
                state = .failing
            } else {
                state = .degraded(consecutiveFailures: consecutiveFailures)
            }
        }

        if state != previousState {
            delegate?.proxyHealthDidChange(to: state)
        }
    }

    // MARK: - Automatic Monitoring

    /// Starts periodic health checks.
    func startMonitoring() {
        stopMonitoring()
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.checkOnce()
                try? await Task.sleep(nanoseconds: UInt64(self.checkInterval * 1_000_000_000))
            }
        }
    }

    /// Stops periodic health checks.
    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }
}

// MARK: - TCP Health Probe

/// Production health probe that attempts a TCP connection through the SOCKS tunnel.
///
/// Connects to a well-known host (1.1.1.1:443) to verify the tunnel is functional.
/// The connection is established and immediately closed — no data is exchanged.
@MainActor
final class TCPHealthProbe: HealthProbing {

    private let targetHost: String
    private let targetPort: UInt16
    private let timeoutSeconds: TimeInterval

    init(
        targetHost: String = "1.1.1.1",
        targetPort: UInt16 = 443,
        timeoutSeconds: TimeInterval = 5.0
    ) {
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.timeoutSeconds = timeoutSeconds
    }

    func probe() async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(targetHost),
                port: NWEndpoint.Port(rawValue: targetPort)!,
                using: .tcp
            )

            var completed = false
            let queue = DispatchQueue(label: "com.cocxy.healthprobe")

            connection.stateUpdateHandler = { state in
                guard !completed else { return }
                switch state {
                case .ready:
                    completed = true
                    connection.cancel()
                    continuation.resume(returning: true)
                case .failed, .cancelled:
                    completed = true
                    continuation.resume(returning: false)
                default:
                    break
                }
            }

            connection.start(queue: queue)

            // Timeout fallback.
            queue.asyncAfter(deadline: .now() + self.timeoutSeconds) {
                guard !completed else { return }
                completed = true
                connection.cancel()
                continuation.resume(returning: false)
            }
        }
    }
}
