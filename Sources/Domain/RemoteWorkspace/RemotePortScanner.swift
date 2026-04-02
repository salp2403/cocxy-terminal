// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemotePortScanner.swift - Detect listening ports on remote hosts via SSH.

import Foundation
import Combine

// MARK: - Remote Port Info

/// A detected listening port on a remote host.
struct RemotePortInfo: Equatable, Sendable {
    let port: Int
    let process: String?
    let address: String
}

// MARK: - Remote Port Scanner

/// Scans a remote host for listening TCP ports via an SSH ControlMaster connection.
///
/// Runs `ss -tlnp` (or `netstat -tlnp` as fallback) on the remote host
/// and parses the output to detect dev servers and other services.
/// Results are published via Combine for reactive UI updates.
///
/// When ports are detected, the scanner can auto-create SSH -L local forwards
/// so the browser pane can reach remote localhost without manual port forwarding.
@MainActor
final class RemotePortScanner: ObservableObject {

    /// Currently detected remote ports.
    @Published private(set) var detectedPorts: [RemotePortInfo] = []

    /// Ports that have been auto-forwarded.
    @Published private(set) var forwardedPorts: Set<Int> = []

    /// Whether the scanner is actively polling.
    private(set) var isScanning = false

    /// Polling interval in seconds.
    let scanInterval: TimeInterval

    /// Common dev server ports to look for specifically.
    static let devPorts: Set<Int> = [
        3000, 3001, 3333, 4000, 4200, 5000, 5173, 5174,
        8000, 8080, 8081, 8443, 8888, 9000, 9090
    ]

    private let multiplexer: SSHMultiplexing
    private let connectionManager: RemoteConnectionManager
    private var scanTimer: Timer?
    private var activeProfileID: UUID?

    // MARK: - Initialization

    init(
        multiplexer: SSHMultiplexing,
        connectionManager: RemoteConnectionManager,
        scanInterval: TimeInterval = 10.0
    ) {
        self.multiplexer = multiplexer
        self.connectionManager = connectionManager
        self.scanInterval = scanInterval
    }

    deinit {
        scanTimer?.invalidate()
    }

    // MARK: - Scanning Lifecycle

    /// Starts scanning a remote host for listening ports.
    ///
    /// - Parameter profileID: The remote connection profile to scan through.
    func startScanning(profileID: UUID) {
        stopScanning()
        activeProfileID = profileID
        isScanning = true

        // Initial scan immediately.
        Task { await performScan() }

        // Schedule periodic scanning.
        scanTimer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performScan()
            }
        }
    }

    /// Stops scanning and clears detected ports.
    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
        isScanning = false
        activeProfileID = nil
        detectedPorts = []
        forwardedPorts = []
    }

    // MARK: - Auto-Forward

    /// Auto-forwards a detected remote port to the same local port.
    ///
    /// Creates an SSH `-L localPort:localhost:remotePort` tunnel via the
    /// existing ControlMaster connection.
    func autoForward(port: Int) async {
        guard let profileID = activeProfileID else { return }
        guard !forwardedPorts.contains(port) else { return }

        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: port, remotePort: port
        )

        do {
            try connectionManager.forwardPort(forward, for: profileID)
            forwardedPorts.insert(port)
        } catch {
            // Port forward failed — local port may be in use.
        }
    }

    /// Auto-forwards all detected dev server ports.
    func autoForwardAllDevPorts() async {
        for portInfo in detectedPorts where Self.devPorts.contains(portInfo.port) {
            await autoForward(port: portInfo.port)
        }
    }

    // MARK: - Private: Scanning

    private func performScan() async {
        guard let profileID = activeProfileID else { return }

        // Try `ss` first (modern Linux), fall back to `netstat` (older systems).
        let command = "ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null"
        guard let output = await executeRemoteCommand(command, profileID: profileID) else {
            return
        }

        let ports = parseListeningPorts(output)
        detectedPorts = ports

        // Auto-forward any new dev server ports.
        for portInfo in ports where Self.devPorts.contains(portInfo.port) {
            if !forwardedPorts.contains(portInfo.port) {
                await autoForward(port: portInfo.port)
            }
        }
    }

    private func executeRemoteCommand(_ command: String, profileID: UUID) async -> String? {
        do {
            return try await connectionManager.executeRemoteCommand(
                command, profileID: profileID
            )
        } catch {
            return nil
        }
    }

    /// Parses `ss -tlnp` or `netstat -tlnp` output to extract listening ports.
    ///
    /// Example `ss` output:
    /// ```
    /// LISTEN  0  128  *:3000  *:*  users:(("node",pid=1234,fd=15))
    /// ```
    func parseListeningPorts(_ output: String) -> [RemotePortInfo] {
        var ports: [RemotePortInfo] = []
        let lines = output.split(separator: "\n")

        for line in lines {
            let lineStr = String(line)
            // Skip headers.
            guard lineStr.contains("LISTEN") || lineStr.contains("tcp") else { continue }

            // Extract port from address field (e.g., "*:3000", "0.0.0.0:8080", ":::3000").
            guard let port = extractPort(from: lineStr) else { continue }

            // Extract process name if available.
            let process = extractProcess(from: lineStr)
            let address = extractAddress(from: lineStr)

            ports.append(RemotePortInfo(port: port, process: process, address: address))
        }

        // Deduplicate by port number, preferring entries with process info.
        var seen: [Int: RemotePortInfo] = [:]
        for info in ports {
            if let existing = seen[info.port] {
                if existing.process == nil && info.process != nil {
                    seen[info.port] = info
                }
            } else {
                seen[info.port] = info
            }
        }

        return seen.values.sorted { $0.port < $1.port }
    }

    private func extractPort(from line: String) -> Int? {
        // Match patterns: *:PORT, 0.0.0.0:PORT, :::PORT, 127.0.0.1:PORT
        let patterns = [
            #"\*:(\d+)"#,
            #"0\.0\.0\.0:(\d+)"#,
            #":::(\d+)"#,
            #"127\.0\.0\.1:(\d+)"#,
            #"\]:(\d+)"#
        ]
        for pattern in patterns {
            if let match = line.range(of: pattern, options: .regularExpression) {
                let matched = String(line[match])
                if let colonRange = matched.lastIndex(of: ":") {
                    let portStr = matched[matched.index(after: colonRange)...]
                    if let port = Int(portStr), port > 0, port < 65536 {
                        return port
                    }
                }
            }
        }
        return nil
    }

    private func extractProcess(from line: String) -> String? {
        // ss format: users:(("node",pid=1234,fd=15))
        if let match = line.range(of: #"\(\("([^"]+)""#, options: .regularExpression) {
            let sub = line[match]
            let cleaned = sub.replacingOccurrences(of: "((\"", with: "")
                .replacingOccurrences(of: "\"", with: "")
            return cleaned.isEmpty ? nil : cleaned
        }
        // netstat format: 1234/node
        if let match = line.range(of: #"\d+/(\S+)"#, options: .regularExpression) {
            let sub = String(line[match])
            if let slashIdx = sub.firstIndex(of: "/") {
                return String(sub[sub.index(after: slashIdx)...])
            }
        }
        return nil
    }

    private func extractAddress(from line: String) -> String {
        if line.contains("0.0.0.0") || line.contains("*:") || line.contains(":::") {
            return "0.0.0.0"
        }
        if line.contains("127.0.0.1") {
            return "127.0.0.1"
        }
        return "0.0.0.0"
    }
}
