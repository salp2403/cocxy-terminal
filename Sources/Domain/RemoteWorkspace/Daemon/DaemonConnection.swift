// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonConnection.swift - JSON-RPC multiplex connection to remote daemon.

import Foundation
import Network

// MARK: - Daemon Connection

/// Manages the communication channel to a remote cocxyd daemon.
///
/// Communication flows through an SSH reverse tunnel to the daemon's TCP port.
/// Requests are multiplexed by ID, allowing concurrent operations.
/// A heartbeat (ping every 30s) detects connection loss.
@MainActor
final class DaemonConnection: ObservableObject {

    // MARK: - State

    @Published private(set) var isConnected = false

    // MARK: - Configuration

    let heartbeatInterval: TimeInterval

    // MARK: - Internal

    private var connection: NWConnection?
    private var pendingRequests: [String: CheckedContinuation<DaemonResponse, any Error>] = [:]
    private var heartbeatTask: Task<Void, Never>?
    private var requestCounter: Int = 0
    private var receiveBuffer = Data()

    init(heartbeatInterval: TimeInterval = 30.0) {
        self.heartbeatInterval = heartbeatInterval
    }

    // MARK: - Connect

    /// Connects to the daemon via the reverse tunnel's local endpoint.
    ///
    /// - Parameter port: The local port of the SSH reverse tunnel.
    func connect(port: UInt16) {
        let nwPort = NWEndpoint.Port(rawValue: port)!
        connection = NWConnection(
            host: .ipv4(.loopback),
            port: nwPort,
            using: .tcp
        )

        connection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.startHeartbeat()
                    self?.startReceiving()
                case .failed, .cancelled:
                    self?.isConnected = false
                    self?.stopHeartbeat()
                    self?.failAllPending(DaemonProtocolError.connectionLost)
                default:
                    break
                }
            }
        }

        connection?.start(queue: .main)
    }

    /// Disconnects from the daemon.
    func disconnect() {
        stopHeartbeat()
        connection?.cancel()
        connection = nil
        isConnected = false
        failAllPending(DaemonProtocolError.connectionLost)
    }

    // MARK: - Send Request

    /// Sends a command to the daemon and waits for the response.
    ///
    /// - Parameters:
    ///   - cmd: The daemon command to execute.
    ///   - args: Optional arguments.
    /// - Returns: The daemon's response.
    func send(cmd: String, args: [String: String]? = nil) async throws -> DaemonResponse {
        guard isConnected, let connection else {
            throw DaemonProtocolError.daemonNotRunning
        }

        requestCounter += 1
        let reqID = "req-\(requestCounter)"

        let request = DaemonRequest(id: reqID, cmd: cmd, args: args)
        let jsonLine = try request.jsonLine()
        let data = Data(jsonLine.utf8)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[reqID] = continuation

            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    Task { @MainActor in
                        self?.pendingRequests.removeValue(forKey: reqID)
                    }
                    continuation.resume(throwing: error)
                }
            })
        }
    }

    // MARK: - Receive

    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in

            Task { @MainActor in
                guard let self else { return }

                if let data {
                    self.receiveBuffer.append(data)
                    self.processBuffer()
                }

                if isComplete || error != nil {
                    self.isConnected = false
                    self.failAllPending(DaemonProtocolError.connectionLost)
                    return
                }

                self.startReceiving()
            }
        }
    }

    private func processBuffer() {
        // Split on newlines — each line is a JSON response.
        while let newlineIndex = receiveBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = receiveBuffer[receiveBuffer.startIndex..<newlineIndex]
            receiveBuffer = Data(receiveBuffer[(newlineIndex + 1)...])

            guard let line = String(data: lineData, encoding: .utf8),
                  let response = try? DaemonResponse.parse(line)
            else { continue }

            // Dispatch to pending request.
            if let id = response.id, let continuation = pendingRequests.removeValue(forKey: id) {
                continuation.resume(returning: response)
            }
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64((self?.heartbeatInterval ?? 30) * 1_000_000_000))
                guard let self, self.isConnected else { return }
                _ = try? await self.send(cmd: DaemonCommand.ping.rawValue)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    // MARK: - Helpers

    private func failAllPending(_ error: any Error) {
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: error)
        }
        pendingRequests.removeAll()
    }
}
