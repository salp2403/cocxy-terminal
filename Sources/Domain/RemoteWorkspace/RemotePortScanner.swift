// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemotePortScanner.swift - Detect listening ports on remote hosts via SSH.

import Combine
import Darwin
import Foundation

// MARK: - Remote Port Info

/// A detected listening port on a remote host.
struct RemotePortInfo: Equatable, Sendable {
    let port: Int
    let process: String?
    let address: String
}

/// Browser-ready route suggestion produced from a detected remote dev server.
struct RemoteBrowserOpenSuggestion: Identifiable, Equatable, Sendable {
    let profileID: UUID
    let remotePort: Int
    let localPort: Int
    let process: String?
    let remoteAddress: String
    let localURL: URL

    var id: String {
        "\(profileID.uuidString):\(remotePort):\(localPort)"
    }
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
    typealias LocalPortCandidateProvider = @MainActor (_ remotePort: Int, _ usedLocalPorts: Set<Int>) -> [Int]
    typealias LocalPortAvailabilityChecker = @MainActor (_ localPort: Int) -> Bool

    /// Currently detected remote ports.
    @Published private(set) var detectedPorts: [RemotePortInfo] = []

    /// Ports that have been auto-forwarded.
    @Published private(set) var forwardedPorts: Set<Int> = []

    /// Mapping of remote dev server port -> local forwarded port.
    @Published private(set) var forwardedPortMappings: [Int: Int] = [:]

    /// Browser-ready suggestions for detected remote dev servers.
    @Published private(set) var browserOpenSuggestions: [RemoteBrowserOpenSuggestion] = []

    /// Whether the scanner is actively polling.
    private(set) var isScanning = false

    /// Profile currently being scanned.
    var scanningProfileID: UUID? { activeProfileID }

    /// Polling interval in seconds.
    let scanInterval: TimeInterval

    /// Common dev server ports to look for specifically.
    static let devPorts: Set<Int> = [
        3000, 3001, 3333, 4000, 4200, 5000, 5173, 5174,
        8000, 8080, 8081, 8443, 8888, 9000, 9090
    ]

    private let multiplexer: any SSHMultiplexing
    private let connectionManager: RemoteConnectionManager
    private let localPortCandidates: LocalPortCandidateProvider
    private let localPortAvailability: LocalPortAvailabilityChecker
    private var scanTimer: Timer?
    private var activeProfileID: UUID?

    // MARK: - Initialization

    init(
        multiplexer: any SSHMultiplexing,
        connectionManager: RemoteConnectionManager,
        scanInterval: TimeInterval = 10.0,
        localPortCandidates: @escaping LocalPortCandidateProvider = RemotePortScanner.defaultLocalPortCandidates,
        localPortAvailability: @escaping LocalPortAvailabilityChecker = RemotePortScanner.defaultLocalPortAvailability
    ) {
        self.multiplexer = multiplexer
        self.connectionManager = connectionManager
        self.scanInterval = scanInterval
        self.localPortCandidates = localPortCandidates
        self.localPortAvailability = localPortAvailability
    }

    // MARK: - Scanning Lifecycle

    /// Starts scanning a remote host for listening ports.
    ///
    /// - Parameter profileID: The remote connection profile to scan through.
    func startScanning(profileID: UUID, performInitialScan: Bool = true) {
        stopScanning()
        activeProfileID = profileID
        isScanning = true

        // Initial scan immediately.
        if performInitialScan {
            Task { await performScan() }
        }

        // Schedule periodic scanning.
        scanTimer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }
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
        forwardedPortMappings = [:]
        browserOpenSuggestions = []
    }

    // MARK: - Auto-Forward

    /// Auto-forwards a detected remote port to the same local port.
    ///
    /// Creates an SSH `-L localPort:localhost:remotePort` tunnel via the
    /// existing ControlMaster connection.
    func autoForward(port: Int) async {
        guard let profileID = activeProfileID else { return }
        guard forwardedPortMappings[port] == nil else { return }

        let usedLocalPorts = Set(forwardedPortMappings.values)
        let candidates = localPortCandidates(port, usedLocalPorts)

        for localPort in candidates where (1...65535).contains(localPort) {
            guard localPortAvailability(localPort) else { continue }

            let forward = RemoteConnectionProfile.PortForward.local(
                localPort: localPort, remotePort: port
            )

            do {
                try connectionManager.forwardPort(forward, for: profileID)
                forwardedPorts.insert(port)
                forwardedPortMappings[port] = localPort
                refreshBrowserOpenSuggestions()
                return
            } catch {
                // Try the next candidate. The same-numbered port can be busy locally.
                continue
            }
        }
    }

    /// Auto-forwards all detected dev server ports.
    func autoForwardAllDevPorts() async {
        for portInfo in detectedPorts where Self.devPorts.contains(portInfo.port) {
            await autoForward(port: portInfo.port)
        }
    }

    /// Runs an immediate scan for the active profile.
    func refreshNow() async {
        await performScan()
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
        refreshBrowserOpenSuggestions()

        // Auto-forward any new dev server ports.
        for portInfo in ports where Self.devPorts.contains(portInfo.port) {
            if forwardedPortMappings[portInfo.port] == nil {
                await autoForward(port: portInfo.port)
            }
        }
    }

    private func refreshBrowserOpenSuggestions() {
        guard let profileID = activeProfileID else {
            browserOpenSuggestions = []
            return
        }

        browserOpenSuggestions = detectedPorts.compactMap { portInfo in
            guard let localPort = forwardedPortMappings[portInfo.port] else {
                return nil
            }
            var components = URLComponents()
            components.scheme = "http"
            components.host = "127.0.0.1"
            components.port = localPort
            components.path = "/"
            guard let localURL = components.url else { return nil }
            return RemoteBrowserOpenSuggestion(
                profileID: profileID,
                remotePort: portInfo.port,
                localPort: localPort,
                process: portInfo.process,
                remoteAddress: portInfo.address,
                localURL: localURL
            )
        }
    }

    func browserProfile(
        for remoteConnectionProfile: RemoteConnectionProfile,
        proxyState: ProxyState = .off
    ) -> RemoteBrowserProfile {
        let mappings = activeProfileID == remoteConnectionProfile.id ? forwardedPortMappings : [:]
        return RemoteBrowserProfile(
            remoteConnectionProfile: remoteConnectionProfile,
            localForwardedPorts: mappings,
            proxyState: proxyState
        )
    }

    func browserRoute(
        forRemotePort remotePort: Int,
        remoteConnectionProfile: RemoteConnectionProfile,
        proxyState: ProxyState = .off,
        scheme: String = "http",
        path: String = "/"
    ) -> RemoteBrowserRoute? {
        browserProfile(
            for: remoteConnectionProfile,
            proxyState: proxyState
        )
        .route(forRemotePort: remotePort, scheme: scheme, path: path)
    }

    nonisolated static func defaultLocalPortCandidates(remotePort: Int, usedLocalPorts: Set<Int>) -> [Int] {
        var candidates: [Int] = []
        if !usedLocalPorts.contains(remotePort) {
            candidates.append(remotePort)
        }

        let base = 49_152 + (remotePort % 12_000)
        for offset in 0..<16 {
            let candidate = base + offset
            if candidate <= 65_535, !usedLocalPorts.contains(candidate), !candidates.contains(candidate) {
                candidates.append(candidate)
            }
        }

        return candidates
    }

    nonisolated static func defaultLocalPortAvailability(localPort: Int) -> Bool {
        guard (1...65535).contains(localPort) else { return false }

        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(localPort).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(
                    descriptor,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                ) == 0
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
