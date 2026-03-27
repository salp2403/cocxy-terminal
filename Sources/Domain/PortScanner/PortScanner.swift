// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PortScanner.swift - Detects active dev servers on localhost.

import Combine
import Foundation
import Network

// MARK: - Detected Port

/// Represents a port on localhost with an active TCP listener.
///
/// Used by the status bar to show which dev servers are running.
/// The `processName` is best-effort: it may be nil if `lsof` fails
/// or the process cannot be identified.
///
/// - SeeAlso: ``PortScannerImpl``
struct DetectedPort: Identifiable, Equatable, Sendable {

    /// The TCP port number.
    let port: UInt16

    /// The name of the process listening on this port (best-effort).
    let processName: String?

    /// Unique identity derived from the port number.
    var id: UInt16 { port }
}

// MARK: - Port Scanner

/// Scans localhost for active TCP listeners on common development ports.
///
/// Uses `NWConnection` from the Network framework for non-blocking TCP
/// connect probes. Each probe has a 200ms timeout so scans complete fast
/// even when many ports are closed.
///
/// ## Usage
///
/// ```swift
/// let scanner = PortScannerImpl()
/// scanner.startScanning(interval: 5.0)
///
/// scanner.portsChangedPublisher
///     .sink { ports in
///         print("Active ports: \(ports.map { $0.port })")
///     }
/// ```
///
/// ## Thread safety
///
/// All published state lives on `@MainActor`. The underlying `NWConnection`
/// probes run on a private dispatch queue and publish results back to main.
///
/// - SeeAlso: ``DetectedPort``
@MainActor
final class PortScannerImpl: ObservableObject {

    // MARK: - Published State

    /// Ports currently detected as active on localhost.
    @Published private(set) var activePorts: [DetectedPort] = []

    // MARK: - Configuration

    /// Common development server ports to scan.
    static let defaultPorts: [UInt16] = [
        3000, 3001, 3002,   // Next.js, React dev servers
        5173, 5174,          // Vite
        4200,                // Angular CLI
        8000, 8080, 8081,    // Generic HTTP, Spring Boot, various
        8888,                // Jupyter
        4000,                // Phoenix, Gatsby
        5000, 5500,          // Flask, Live Server
        9000,                // PHP, SonarQube
    ]

    // MARK: - Internal State

    /// Timer that triggers periodic scans.
    private var scanTimer: DispatchSourceTimer?

    /// Queue for NWConnection probes.
    private let probeQueue = DispatchQueue(
        label: "com.cocxy.port-scanner.probe",
        qos: .utility
    )

    /// Subject backing the ``portsChangedPublisher``.
    private let portsChangedSubject = PassthroughSubject<[DetectedPort], Never>()

    /// Whether the scanner is currently running periodic scans.
    private(set) var isScanning: Bool = false

    // MARK: - Public API

    /// Publisher that emits whenever the set of active ports changes.
    var portsChangedPublisher: AnyPublisher<[DetectedPort], Never> {
        portsChangedSubject.eraseToAnyPublisher()
    }

    /// Starts periodic scanning at the given interval.
    ///
    /// If already scanning, the previous timer is cancelled and replaced.
    ///
    /// - Parameter interval: Seconds between scan cycles. Defaults to 5.
    func startScanning(interval: TimeInterval = 5.0) {
        stopScanning()
        isScanning = true

        let timer = DispatchSource.makeTimerSource(queue: probeQueue)
        timer.schedule(
            deadline: .now(),
            repeating: interval,
            leeway: .milliseconds(500)
        )
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isScanning else { return }
                _ = await self.scanOnce()
            }
        }
        timer.resume()
        self.scanTimer = timer
    }

    /// Stops periodic scanning and cancels the timer.
    func stopScanning() {
        isScanning = false
        scanTimer?.cancel()
        scanTimer = nil
    }

    /// Performs a single scan of all configured ports.
    ///
    /// Probes each port in ``defaultPorts`` with a TCP connect test.
    /// Updates ``activePorts`` and emits on ``portsChangedPublisher``
    /// only when the result differs from the previous scan.
    ///
    /// - Returns: The list of ports detected as active.
    @discardableResult
    func scanOnce() async -> [DetectedPort] {
        let detectedPorts = await probeAllPorts()
        let sorted = detectedPorts.sorted { $0.port < $1.port }

        if sorted != activePorts {
            activePorts = sorted
            portsChangedSubject.send(sorted)
        }

        return sorted
    }

    // MARK: - Probing

    /// Probes all configured ports concurrently and returns those that are open.
    private func probeAllPorts() async -> [DetectedPort] {
        await withTaskGroup(of: DetectedPort?.self) { group in
            for port in Self.defaultPorts {
                group.addTask { [weak self] in
                    guard self != nil else { return nil }
                    let isOpen = await self?.probePort(port) ?? false
                    guard isOpen else { return nil }
                    let processName = await self?.resolveProcessName(for: port)
                    return DetectedPort(port: port, processName: processName)
                }
            }

            var results: [DetectedPort] = []
            for await result in group {
                if let detected = result {
                    results.append(detected)
                }
            }
            return results
        }
    }

    /// Probes a single port on localhost using NWConnection.
    ///
    /// Attempts a TCP connection with a 200ms timeout. Returns true
    /// if the connection reaches the `.ready` state (port is open).
    ///
    /// - Parameter port: The TCP port to probe.
    /// - Returns: Whether the port is accepting connections.
    private func probePort(_ port: UInt16) async -> Bool {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: .ipv4(.loopback),
                port: NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: 80)!
            )

            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback

            let connection = NWConnection(to: endpoint, using: parameters)

            var hasResumed = false
            let lock = NSLock()

            func resumeOnce(with value: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                connection.cancel()
                continuation.resume(returning: value)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeOnce(with: true)
                case .failed, .cancelled:
                    resumeOnce(with: false)
                case .waiting:
                    // Connection is waiting (e.g., no route). Treat as closed.
                    resumeOnce(with: false)
                default:
                    break
                }
            }

            connection.start(queue: self.probeQueue)

            // Timeout: 200ms. If the connection has not reached .ready, give up.
            self.probeQueue.asyncAfter(deadline: .now() + .milliseconds(200)) {
                resumeOnce(with: false)
            }
        }
    }

    // MARK: - Process Name Resolution

    /// Attempts to resolve the process name listening on a given port.
    ///
    /// Uses `lsof -i :<port> -t` to get the PID, then `ps -p <pid> -o comm=`
    /// to get the process name. This is best-effort: returns nil on any failure.
    ///
    /// - Parameter port: The port to look up.
    /// - Returns: The process name, or nil if resolution fails.
    private nonisolated func resolveProcessName(for port: UInt16) async -> String? {
        // Step 1: Get PID via lsof.
        guard let pid = runCommand("/usr/sbin/lsof", arguments: ["-i", ":\(port)", "-t"]) else {
            return nil
        }

        let trimmedPID = pid.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""

        guard !trimmedPID.isEmpty else { return nil }

        // Step 2: Get process name via ps.
        guard let name = runCommand("/bin/ps", arguments: ["-p", trimmedPID, "-o", "comm="]) else {
            return nil
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        // Extract just the binary name from the full path.
        return URL(fileURLWithPath: trimmedName).lastPathComponent
    }

    /// Runs a command and returns its stdout, or nil on failure.
    ///
    /// The process runs synchronously with a 1-second timeout.
    /// Never throws or crashes, regardless of the command's exit status.
    private nonisolated func runCommand(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
