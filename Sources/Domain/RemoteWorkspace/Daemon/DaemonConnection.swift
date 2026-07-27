// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonConnection.swift - Lease-bound JSON-RPC transport to the remote daemon.

import Foundation

/// One authenticated daemon channel carried by an attested SSH direct-tcpip stream.
///
/// The connection is bound to an exact remote profile lease. Every request is
/// prefixed with an in-memory 256-bit capability and has an absolute response
/// timeout, so a stale SSH session or silent peer cannot retain control.
@MainActor
final class DaemonConnection: ObservableObject {
    private struct PendingRequest {
        let continuation: CheckedContinuation<DaemonResponse, any Error>
        let timeoutTask: Task<Void, Never>
    }

    nonisolated static let maximumFrameBytes = 1 * 1_024 * 1_024

    @Published private(set) var isConnected = false

    let profileID: UUID
    let connectionLeaseID: UUID
    let heartbeatInterval: TimeInterval
    let requestTimeout: TimeInterval
    var onUnexpectedDisconnect: (@MainActor () -> Void)?

    private let authorizationIsCurrent: @MainActor () -> Bool
    private var transport: (any ProxyUpstreamTransport)?
    private var capability = ""
    private var pendingRequests: [String: PendingRequest] = [:]
    private var heartbeatTask: Task<Void, Never>?
    private var requestCounter: UInt64 = 0
    private var receiveBuffer = Data()
    private var generation: UInt64 = 0

    init(
        profileID: UUID,
        connectionLeaseID: UUID,
        heartbeatInterval: TimeInterval = 30,
        requestTimeout: TimeInterval = 10,
        authorizationIsCurrent: @escaping @MainActor () -> Bool
    ) {
        self.profileID = profileID
        self.connectionLeaseID = connectionLeaseID
        self.heartbeatInterval = max(0.1, heartbeatInterval)
        self.requestTimeout = max(0.1, requestTimeout)
        self.authorizationIsCurrent = authorizationIsCurrent
    }

    /// Completes the SSH stream handshake and an authenticated ping before returning.
    func connect(
        transport: any ProxyUpstreamTransport,
        capability: String
    ) async throws {
        disconnect()
        guard Self.isValidCapability(capability), authorizationIsCurrent() else {
            transport.cancel()
            throw DaemonProtocolError.authenticationFailed
        }

        self.transport = transport
        self.capability = capability
        let connectionGeneration = generation

        do {
            try await transport.waitUntilReady()
            guard generation == connectionGeneration,
                  self.transport === transport,
                  transport.isRunning,
                  authorizationIsCurrent() else {
                throw DaemonProtocolError.connectionLost
            }

            isConnected = true
            startReceiving(generation: connectionGeneration)
            let response = try await send(
                cmd: DaemonCommand.ping.rawValue,
                timeout: requestTimeout
            )
            guard response.ok,
                  response.data?["pong"] as? Bool == true,
                  authorizationIsCurrent() else {
                throw DaemonProtocolError.authenticationFailed
            }
            startHeartbeat(generation: connectionGeneration)
        } catch {
            disconnect()
            throw error
        }
    }

    func disconnect() {
        generation &+= 1
        heartbeatTask?.cancel()
        heartbeatTask = nil
        transport?.cancel()
        transport = nil
        capability.removeAll(keepingCapacity: false)
        receiveBuffer.removeAll(keepingCapacity: false)
        isConnected = false
        failAllPending(DaemonProtocolError.connectionLost)
    }

    func send(
        cmd: String,
        args: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> DaemonResponse {
        try Task.checkCancellation()
        guard isConnected,
              authorizationIsCurrent(),
              let transport,
              transport.isRunning,
              Self.isValidCapability(capability) else {
            disconnect()
            throw DaemonProtocolError.daemonNotRunning
        }

        requestCounter &+= 1
        let requestID = "req-\(requestCounter)"
        let request = DaemonRequest(id: requestID, cmd: cmd, args: args)
        let jsonLine = try request.jsonLine()
        let frame = Data("\(capability)\t\(jsonLine)".utf8)
        guard frame.count <= Self.maximumFrameBytes else {
            throw DaemonProtocolError.encodingFailed
        }
        let boundedTimeout = max(0.1, timeout ?? requestTimeout)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<DaemonResponse, any Error>) in
                let timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(
                            nanoseconds: UInt64(boundedTimeout * 1_000_000_000)
                        )
                    } catch {
                        return
                    }
                    self?.finishRequest(
                        id: requestID,
                        result: .failure(DaemonProtocolError.timeout)
                    )
                }
                pendingRequests[requestID] = PendingRequest(
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )

                transport.send(frame) { [weak self] result in
                    guard case .failure(let error) = result else { return }
                    Task { @MainActor in
                        self?.finishRequest(id: requestID, result: .failure(error))
                    }
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.finishRequest(id: requestID, result: .failure(CancellationError()))
            }
        }
    }

    private func startReceiving(generation expectedGeneration: UInt64) {
        guard generation == expectedGeneration,
              isConnected,
              authorizationIsCurrent(),
              let transport else {
            failConnection(DaemonProtocolError.connectionLost)
            return
        }

        transport.receive(maximumLength: 65_536) { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == expectedGeneration else { return }
                guard self.authorizationIsCurrent() else {
                    self.failConnection(DaemonProtocolError.connectionLost)
                    return
                }
                switch result {
                case .success(let data?):
                    self.receiveBuffer.append(data)
                    guard self.receiveBuffer.count <= Self.maximumFrameBytes else {
                        self.failConnection(DaemonProtocolError.invalidResponse)
                        return
                    }
                    do {
                        try self.processBuffer()
                    } catch {
                        self.failConnection(error)
                        return
                    }
                    self.startReceiving(generation: expectedGeneration)
                case .success(nil):
                    self.failConnection(DaemonProtocolError.connectionLost)
                case .failure(let error):
                    self.failConnection(error)
                }
            }
        }
    }

    private func processBuffer() throws {
        while let newlineIndex = receiveBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = Data(receiveBuffer[..<newlineIndex])
            receiveBuffer = Data(receiveBuffer[(newlineIndex + 1)...])
            guard !lineData.isEmpty,
                  lineData.count <= Self.maximumFrameBytes,
                  let line = String(data: lineData, encoding: .utf8) else {
                throw DaemonProtocolError.invalidResponse
            }
            let response = try DaemonResponse.parse(line)
            guard let responseID = response.id else {
                throw DaemonProtocolError.invalidResponse
            }
            if pendingRequests[responseID] != nil {
                finishRequest(id: responseID, result: .success(response))
            }
        }
    }

    private func startHeartbeat(generation expectedGeneration: UInt64) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(self.heartbeatInterval * 1_000_000_000)
                    )
                } catch {
                    return
                }
                guard self.generation == expectedGeneration,
                      self.isConnected,
                      self.authorizationIsCurrent() else {
                    self.failConnection(DaemonProtocolError.connectionLost)
                    return
                }
                do {
                    let response = try await self.send(cmd: DaemonCommand.ping.rawValue)
                    guard response.ok, response.data?["pong"] as? Bool == true else {
                        throw DaemonProtocolError.invalidResponse
                    }
                } catch {
                    self.failConnection(error)
                    return
                }
            }
        }
    }

    private func finishRequest(
        id: String,
        result: Result<DaemonResponse, any Error>
    ) {
        guard let pending = pendingRequests.removeValue(forKey: id) else { return }
        pending.timeoutTask.cancel()
        pending.continuation.resume(with: result)
    }

    private func failConnection(_ error: any Error) {
        let shouldNotify = isConnected
        generation &+= 1
        heartbeatTask?.cancel()
        heartbeatTask = nil
        transport?.cancel()
        transport = nil
        capability.removeAll(keepingCapacity: false)
        receiveBuffer.removeAll(keepingCapacity: false)
        isConnected = false
        failAllPending(error)
        if shouldNotify {
            onUnexpectedDisconnect?()
        }
    }

    private func failAllPending(_ error: any Error) {
        let pending = pendingRequests.values
        pendingRequests.removeAll()
        for request in pending {
            request.timeoutTask.cancel()
            request.continuation.resume(throwing: error)
        }
    }

    nonisolated static func isValidCapability(_ value: String) -> Bool {
        guard value.utf8.count == 64 else { return false }
        return value.utf8.allSatisfy { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
        }
    }
}
