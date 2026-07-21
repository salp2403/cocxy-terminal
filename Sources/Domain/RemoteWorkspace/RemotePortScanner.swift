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

/// User-action failures surfaced by remote browser port discovery and forwarding.
enum RemotePortScannerError: Error, Equatable, LocalizedError {
    case inactive
    case portNotDetected(Int)
    case operationInProgress(Int)
    case noAvailableLocalPort(Int)
    case forwardingFailed(Int)
    case cancellationFailed(Int)
    case browserUnavailable
    case scanFailed

    var errorDescription: String? {
        switch self {
        case .inactive:
            return "Remote port scanning is not active for this connection"
        case .portNotDetected(let port):
            return "Remote port \(port) is no longer available"
        case .operationInProgress(let port):
            return "An operation is already in progress for remote port \(port)"
        case .noAvailableLocalPort(let port):
            return "No local port is available for remote port \(port)"
        case .forwardingFailed(let port):
            return "Could not forward remote port \(port)"
        case .cancellationFailed(let port):
            return "Could not stop forwarding remote port \(port)"
        case .browserUnavailable:
            return "No browser surface is available"
        case .scanFailed:
            return "Could not scan the remote connection for listening ports"
        }
    }
}

/// Opens a remote browser route and removes a newly-created forward if the UI
/// cannot accept the navigation.
@MainActor
enum RemoteBrowserOpeningOperation {
    static func open(
        remotePort: Int,
        profile: RemoteConnectionProfile,
        scanner: RemotePortScanner,
        opener: (RemoteConnectionProfile, RemoteBrowserOpenSuggestion) -> Bool
    ) async throws -> RemoteBrowserOpenSuggestion {
        guard scanner.scanningProfileID == profile.id else {
            throw RemotePortScannerError.inactive
        }
        let hadExistingForward = scanner.forwardedPortMappings[remotePort] != nil
        let suggestion = try await scanner.forwardDetectedPort(remotePort)
        guard opener(profile, suggestion) else {
            if !hadExistingForward {
                do {
                    try scanner.cancelForwardedPort(remotePort)
                } catch {
                    throw RemotePortScannerError.cancellationFailed(remotePort)
                }
            }
            throw RemotePortScannerError.browserUnavailable
        }
        return suggestion
    }
}

// MARK: - Remote Port Scanner

/// Scans a remote host for listening TCP ports via an SSH ControlMaster connection.
///
/// Runs `ss -tlnp` (or `netstat -tlnp` as fallback) on the remote host
/// and parses the output to detect dev servers and other services.
/// Results are published via Combine for reactive UI updates.
///
/// Discovery never creates a client-facing local listener. Callers must request
/// a specific forward explicitly after presenting the detected service.
@MainActor
final class RemotePortScanner: ObservableObject {
    typealias LocalPortCandidateProvider = @MainActor (_ remotePort: Int, _ usedLocalPorts: Set<Int>) -> [Int]
    typealias LocalPortAvailabilityChecker = @MainActor (_ localPort: Int) -> Bool

    /// Currently detected remote ports.
    @Published private(set) var detectedPorts: [RemotePortInfo] = []

    /// Ports that have been explicitly forwarded during this scan session.
    @Published private(set) var forwardedPorts: Set<Int> = []

    /// Mapping of explicitly selected remote port -> local forwarded port.
    @Published private(set) var forwardedPortMappings: [Int: Int] = [:]

    /// Browser-ready suggestions for detected remote dev servers.
    @Published private(set) var browserOpenSuggestions: [RemoteBrowserOpenSuggestion] = []

    /// Whether the scanner is actively polling.
    @Published private(set) var isScanning = false

    /// Whether an immediate or scheduled scan is currently in flight.
    @Published private(set) var isRefreshing = false

    /// Ports currently being forwarded or cancelled.
    @Published private(set) var busyPorts: Set<Int> = []

    /// Most recent scan failure. A successful scan clears it.
    @Published private(set) var scanError: RemotePortScannerError?

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
    private var refreshToken: UUID?

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
        guard activeProfileID != profileID || !isScanning else {
            if performInitialScan {
                Task { await performScan() }
            }
            return
        }
        stopScanning()
        activeProfileID = profileID
        isScanning = true
        scanError = nil
        busyPorts = []

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
        refreshToken = nil
        isRefreshing = false
        scanError = nil
        busyPorts = []

        let profileID = activeProfileID
        let ownedForwardMappings = forwardedPortMappings
        let connectionLeaseID = profileID.flatMap { connectionManager.connectionLeaseID(for: $0) }
        activeProfileID = nil
        detectedPorts = []
        forwardedPorts = []
        forwardedPortMappings = [:]
        browserOpenSuggestions = []

        var cancellationFailed = false
        if let profileID {
            for (remotePort, localPort) in ownedForwardMappings.sorted(by: { $0.key < $1.key }) {
                let forward = RemoteConnectionProfile.PortForward.local(
                    localPort: localPort,
                    remotePort: remotePort
                )
                do {
                    try connectionManager.cancelForward(forward, for: profileID)
                } catch {
                    cancellationFailed = true
                }
            }
        }

        if cancellationFailed, let profileID, let connectionLeaseID {
            let manager = connectionManager
            Task { @MainActor [weak manager] in
                _ = await manager?.revokeForwardingSession(
                    profileID: profileID,
                    expectedLeaseID: connectionLeaseID
                )
            }
        }
    }

    // MARK: - Explicit Forwarding

    /// Forwards one user-selected remote port to an available local port.
    ///
    /// Creates an SSH `-L localPort:localhost:remotePort` tunnel via the
    /// existing ControlMaster connection.
    func forwardDetectedPort(_ port: Int) async throws -> RemoteBrowserOpenSuggestion {
        guard let profileID = activeProfileID else {
            throw RemotePortScannerError.inactive
        }
        if let existing = makeBrowserOpenSuggestion(remotePort: port) {
            return existing
        }
        guard detectedPorts.contains(where: { $0.port == port }) else {
            throw RemotePortScannerError.portNotDetected(port)
        }
        guard busyPorts.insert(port).inserted else {
            throw RemotePortScannerError.operationInProgress(port)
        }
        defer { busyPorts.remove(port) }

        let usedLocalPorts = Set(forwardedPortMappings.values)
        let candidates = localPortCandidates(port, usedLocalPorts)
        var didAttemptForward = false

        for localPort in candidates where (1...65535).contains(localPort) && !usedLocalPorts.contains(localPort) {
            guard localPortAvailability(localPort) else { continue }
            didAttemptForward = true

            let forward = RemoteConnectionProfile.PortForward.local(
                localPort: localPort, remotePort: port
            )

            do {
                try connectionManager.forwardPort(forward, for: profileID)
            } catch {
                // Try the next candidate. The same-numbered port can be busy locally.
                continue
            }

            forwardedPorts.insert(port)
            forwardedPortMappings[port] = localPort
            refreshBrowserOpenSuggestions()
            guard let suggestion = makeBrowserOpenSuggestion(remotePort: port) else {
                do {
                    try connectionManager.cancelForward(forward, for: profileID)
                } catch {
                    throw RemotePortScannerError.cancellationFailed(port)
                }
                forwardedPorts.remove(port)
                forwardedPortMappings.removeValue(forKey: port)
                refreshBrowserOpenSuggestions()
                throw RemotePortScannerError.forwardingFailed(port)
            }
            return suggestion
        }

        if didAttemptForward {
            throw RemotePortScannerError.forwardingFailed(port)
        }
        throw RemotePortScannerError.noAvailableLocalPort(port)
    }

    /// Stops a scanner-owned local forward while retaining it in published
    /// state if OpenSSH cannot confirm cancellation.
    func cancelForwardedPort(_ remotePort: Int) throws {
        guard let profileID = activeProfileID else {
            throw RemotePortScannerError.inactive
        }
        guard let localPort = forwardedPortMappings[remotePort] else { return }
        guard busyPorts.insert(remotePort).inserted else {
            throw RemotePortScannerError.operationInProgress(remotePort)
        }
        defer { busyPorts.remove(remotePort) }

        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: localPort,
            remotePort: remotePort
        )
        do {
            try connectionManager.cancelForward(forward, for: profileID)
        } catch {
            throw RemotePortScannerError.cancellationFailed(remotePort)
        }
        forwardedPorts.remove(remotePort)
        forwardedPortMappings.removeValue(forKey: remotePort)
        refreshBrowserOpenSuggestions()
    }

    /// Runs an immediate scan for the active profile.
    func refreshNow() async {
        await performScan()
    }

    // MARK: - Private: Scanning

    private func performScan() async {
        guard let profileID = activeProfileID, refreshToken == nil else { return }
        let token = UUID()
        refreshToken = token
        isRefreshing = true
        defer {
            if refreshToken == token {
                refreshToken = nil
                isRefreshing = false
            }
        }

        // Try `ss` first (modern Linux), fall back to `netstat` (older systems).
        let command = "ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null"
        guard let output = await executeRemoteCommand(command, profileID: profileID) else {
            guard refreshToken == token, activeProfileID == profileID else { return }
            scanError = .scanFailed
            return
        }
        guard refreshToken == token, activeProfileID == profileID else { return }

        let ports = parseListeningPorts(output)
        detectedPorts = ports
        scanError = nil
        refreshBrowserOpenSuggestions()
    }

    private func refreshBrowserOpenSuggestions() {
        guard let profileID = activeProfileID else {
            browserOpenSuggestions = []
            return
        }

        browserOpenSuggestions = forwardedPortMappings.keys.sorted().compactMap {
            makeBrowserOpenSuggestion(remotePort: $0, profileID: profileID)
        }
    }

    private func makeBrowserOpenSuggestion(
        remotePort: Int,
        profileID: UUID? = nil
    ) -> RemoteBrowserOpenSuggestion? {
        guard let profileID = profileID ?? activeProfileID,
              let localPort = forwardedPortMappings[remotePort] else { return nil }
        let portInfo = detectedPorts.first { $0.port == remotePort }
        var components = URLComponents()
        components.scheme = Self.suggestedScheme(for: remotePort)
        components.host = "127.0.0.1"
        components.port = localPort
        components.path = "/"
        guard let localURL = components.url else { return nil }
        return RemoteBrowserOpenSuggestion(
            profileID: profileID,
            remotePort: remotePort,
            localPort: localPort,
            process: portInfo?.process,
            remoteAddress: portInfo?.address ?? "unknown",
            localURL: localURL
        )
    }

    nonisolated static func suggestedScheme(for remotePort: Int) -> String {
        [443, 8443].contains(remotePort) ? "https" : "http"
    }

    nonisolated static func preferredScanningProfileID(
        currentProfileID: UUID?,
        connections: [UUID: RemoteConnectionManager.ConnectionState]
    ) -> UUID? {
        if let currentProfileID,
           case .connected = connections[currentProfileID] {
            return currentProfileID
        }
        return connections.compactMap { profileID, state in
            if case .connected = state { return profileID }
            return nil
        }
        .sorted { $0.uuidString < $1.uuidString }
        .first
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
            let address = extractAddress(from: lineStr, port: port)

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

    private func extractAddress(from line: String, port: Int) -> String {
        if line.contains("127.0.0.1:\(port)") {
            return "127.0.0.1"
        }
        if let range = line.range(
            of: #"\[[^\]]+\]:\#(port)"#,
            options: .regularExpression
        ) {
            let endpoint = line[range]
            if let closeBracket = endpoint.firstIndex(of: "]") {
                return String(endpoint[endpoint.index(after: endpoint.startIndex)..<closeBracket])
            }
        }
        if line.contains(":::\(port)") {
            return "::"
        }
        if line.contains("0.0.0.0:\(port)") || line.contains("*:\(port)") {
            return "0.0.0.0"
        }
        return "0.0.0.0"
    }
}
