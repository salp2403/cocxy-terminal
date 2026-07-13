// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LoopbackTCPListenerGroup.swift - Exact IPv4/IPv6 loopback listeners.

import Foundation
import Network

final class LoopbackConnectionDeliveryLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var pendingDeliveries = 0

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard pendingDeliveries < limit else { return false }
        pendingDeliveries += 1
        return true
    }

    func release() {
        lock.lock()
        pendingDeliveries = max(0, pendingDeliveries - 1)
        lock.unlock()
    }

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingDeliveries
    }
}

/// Owns matching IPv4 and IPv6 TCP listeners without a wildcard bind.
@MainActor
final class LoopbackTCPListenerGroup {
    private final class StartupGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, any Error>?

        init(continuation: CheckedContinuation<Void, any Error>) {
            self.continuation = continuation
        }

        var isPending: Bool {
            lock.lock()
            defer { lock.unlock() }
            return continuation != nil
        }

        @discardableResult
        func resolve(_ result: Result<Void, any Error>) -> Bool {
            lock.lock()
            guard let continuation else {
                lock.unlock()
                return false
            }
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
            return true
        }
    }

    let port: Int
    var newConnectionHandler: (@MainActor (NWConnection) -> Void)?
    var failureHandler: (@MainActor (NWError) -> Void)?

    private var listeners: [NWListener] = []
    private var startupGates: [ObjectIdentifier: StartupGate] = [:]
    private(set) var isReady = false
    private var lifecycleGeneration: UInt64 = 0
    private let listenerQueue = DispatchQueue(
        label: "dev.cocxy.terminal.proxy-listener.\(UUID().uuidString)"
    )
    private let deliveryLimiter = LoopbackConnectionDeliveryLimiter(
        limit: LoopbackTCPListenerGroup.maximumQueuedConnectionDeliveries
    )

    static let maximumQueuedConnectionDeliveries = 32
    var listenerWillStart: (@MainActor (_ index: Int) -> Void)?
    var listenerDidBecomeReady: (@MainActor (_ index: Int) -> Void)?

    init(port: Int) {
        self.port = port
    }

    func start() async throws {
        try Task.checkCancellation()
        guard listeners.isEmpty else {
            if isReady { return }
            throw POSIXError(.EALREADY)
        }
        guard let rawPort = UInt16(exactly: port),
              let networkPort = NWEndpoint.Port(rawValue: rawPort) else {
            throw POSIXError(.EINVAL)
        }

        let ipv4 = try makeListener(
            host: .ipv4(.loopback),
            port: networkPort,
            ipVersion: .v4
        )
        let ipv6 = try makeListener(
            host: .ipv6(.loopback),
            port: networkPort,
            ipVersion: .v6
        )
        listeners = [ipv4, ipv6]
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration

        do {
            try await start(ipv4, index: 0)
            listenerDidBecomeReady?(0)
            try requireCurrentLifecycle(generation)
            try Task.checkCancellation()
            try await start(ipv6, index: 1)
            listenerDidBecomeReady?(1)
            try requireCurrentLifecycle(generation)
            try Task.checkCancellation()
            isReady = true
        } catch {
            if lifecycleGeneration == generation {
                stop()
            }
            throw error
        }
    }

    func stop() {
        lifecycleGeneration &+= 1
        isReady = false
        let current = listeners
        listeners.removeAll()
        for listener in current {
            let identifier = ObjectIdentifier(listener)
            startupGates.removeValue(forKey: identifier)?.resolve(.failure(CancellationError()))
            listener.newConnectionHandler = nil
            listener.stateUpdateHandler = nil
            listener.cancel()
        }
    }

    private func makeListener(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        ipVersion: NWProtocolIP.Options.Version
    ) throws -> NWListener {
        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        guard let ipOptions = parameters.defaultProtocolStack.internetProtocol
            as? NWProtocolIP.Options else {
            throw POSIXError(.EPROTONOSUPPORT)
        }
        ipOptions.version = ipVersion
        // Network.framework otherwise treats the matching v4/v6 port as a
        // conflicting reservation even though both endpoints are exact.
        parameters.allowLocalEndpointReuse = true
        parameters.acceptLocalOnly = true
        parameters.requiredLocalEndpoint = .hostPort(host: host, port: port)
        let listener = try NWListener(using: parameters)
        let deliveryLimiter = self.deliveryLimiter
        listener.newConnectionHandler = { [weak self] connection in
            guard deliveryLimiter.acquire() else {
                connection.cancel()
                return
            }
            Task { @MainActor [weak self] in
                defer { deliveryLimiter.release() }
                guard let handler = self?.newConnectionHandler else {
                    connection.cancel()
                    return
                }
                handler(connection)
            }
        }
        return listener
    }

    private func start(_ listener: NWListener, index: Int) async throws {
        let identifier = ObjectIdentifier(listener)
        let generation = lifecycleGeneration
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                let gate = StartupGate(continuation: continuation)
                startupGates[identifier] = gate
                listener.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        guard gate.resolve(.success(())) else { return }
                        Task { @MainActor in
                            self?.startupGates.removeValue(forKey: identifier)
                        }
                    case .failed(let error):
                        if gate.resolve(.failure(error)) {
                            Task { @MainActor in
                                self?.startupGates.removeValue(forKey: identifier)
                            }
                        } else {
                            Task { @MainActor in
                                self?.handleListenerFailure(error, generation: generation)
                            }
                        }
                    case .cancelled:
                        if gate.resolve(.failure(CancellationError())) {
                            Task { @MainActor in
                                self?.startupGates.removeValue(forKey: identifier)
                            }
                        } else {
                            Task { @MainActor in
                                self?.handleListenerFailure(
                                    .posix(.ECANCELED),
                                    generation: generation
                                )
                            }
                        }
                    default:
                        break
                    }
                }
                listenerWillStart?(index)
                guard gate.isPending else { return }
                if Task.isCancelled {
                    cancelStartup(identifier: identifier)
                    return
                }
                listener.start(queue: listenerQueue)
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelStartup(identifier: identifier)
            }
        }
    }

    private func cancelStartup(identifier: ObjectIdentifier) {
        startupGates.removeValue(forKey: identifier)?.resolve(.failure(CancellationError()))
        guard let listener = listeners.first(where: { ObjectIdentifier($0) == identifier }) else {
            return
        }
        listener.newConnectionHandler = nil
        listener.stateUpdateHandler = nil
        listener.cancel()
    }

    private func requireCurrentLifecycle(_ generation: UInt64) throws {
        guard lifecycleGeneration == generation, listeners.count == 2 else {
            throw CancellationError()
        }
    }

    private func handleListenerFailure(_ error: NWError, generation: UInt64) {
        guard lifecycleGeneration == generation else { return }
        let shouldReport = isReady
        stop()
        if shouldReport {
            failureHandler?(error)
        }
    }
}
