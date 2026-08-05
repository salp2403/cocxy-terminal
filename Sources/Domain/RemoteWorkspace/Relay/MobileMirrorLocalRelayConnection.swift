// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorLocalRelayConnection.swift - Backpressured TLS relay connection.

import Dispatch
import Foundation
import Network

final class MobileMirrorLocalRelayConnection: @unchecked Sendable {
    let remoteAddress: String

    private let client: NWConnection
    private let gatewayPort: UInt16
    private let preamble: Data
    private let idleTimeout: TimeInterval
    private let handshakeTimeout: TimeInterval
    private let onClose: @Sendable () -> Void
    private let queue = DispatchQueue(label: "dev.cocxy.mobile.relay.connection")
    private var upstream: NWConnection?
    private var handshakeTimer: DispatchSourceTimer?
    private var idleTimer: DispatchSourceTimer?
    private var lastActivity = ProcessInfo.processInfo.systemUptime
    private var isActive = false
    private var isClosed = false

    init(
        client: NWConnection,
        gatewayPort: UInt16,
        remoteAddress: String,
        preamble: Data,
        idleTimeout: TimeInterval,
        handshakeTimeout: TimeInterval,
        onClose: @escaping @Sendable () -> Void
    ) {
        self.client = client
        self.gatewayPort = gatewayPort
        self.remoteAddress = remoteAddress
        self.preamble = preamble
        self.idleTimeout = idleTimeout
        self.handshakeTimeout = handshakeTimeout
        self.onClose = onClose
    }

    func start() {
        queue.async { [self] in
            guard !isClosed else { return }
            startHandshakeTimer()
            client.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.openUpstream()
                case .failed, .cancelled:
                    self.closeNow()
                default:
                    break
                }
            }
            client.start(queue: queue)
        }
    }

    func close() {
        queue.async { [weak self] in self?.closeNow() }
    }

    private func openUpstream() {
        guard !isClosed, upstream == nil,
              let port = NWEndpoint.Port(rawValue: gatewayPort) else {
            closeNow()
            return
        }
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 15
        tcpOptions.keepaliveInterval = 5
        tcpOptions.keepaliveCount = 3
        tcpOptions.connectionTimeout = Int(handshakeTimeout)
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        let candidate = NWConnection(
            host: .ipv4(.loopback),
            port: port,
            using: parameters
        )
        upstream = candidate
        candidate.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sendPreamble(to: candidate)
            case .failed, .cancelled:
                self.closeNow()
            default:
                break
            }
        }
        candidate.start(queue: queue)
    }

    private func sendPreamble(to destination: NWConnection) {
        guard !isClosed, !isActive else { return }
        destination.send(content: preamble, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            guard error == nil, !self.isClosed else {
                self.closeNow()
                return
            }
            self.isActive = true
            self.handshakeTimer?.cancel()
            self.handshakeTimer = nil
            self.recordActivity()
            self.startIdleTimer()
            self.pump(from: self.client, to: destination)
            self.pump(from: destination, to: self.client)
        })
    }

    private func pump(from source: NWConnection, to destination: NWConnection) {
        guard !isClosed else { return }
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) {
            [weak self] data, _, isComplete, error in
            guard let self else {
                source.cancel()
                destination.cancel()
                return
            }
            guard !self.isClosed, error == nil else {
                self.closeNow()
                return
            }
            guard let data, !data.isEmpty else {
                if isComplete {
                    self.closeNow()
                } else {
                    self.pump(from: source, to: destination)
                }
                return
            }

            self.recordActivity()
            destination.send(content: data, completion: .contentProcessed { [weak self] sendError in
                guard let self else {
                    source.cancel()
                    destination.cancel()
                    return
                }
                guard sendError == nil, !self.isClosed, !isComplete else {
                    self.closeNow()
                    return
                }
                self.pump(from: source, to: destination)
            })
        }
    }

    private func startHandshakeTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + handshakeTimeout)
        timer.setEventHandler { [weak self] in self?.closeNow() }
        handshakeTimer = timer
        timer.resume()
    }

    private func startIdleTimer() {
        let interval = min(5, max(1, idleTimeout / 3))
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastActivity >= self.idleTimeout {
                self.closeNow()
            }
        }
        idleTimer = timer
        timer.resume()
    }

    private func recordActivity() {
        lastActivity = ProcessInfo.processInfo.systemUptime
    }

    private func closeNow() {
        guard !isClosed else { return }
        isClosed = true
        handshakeTimer?.cancel()
        handshakeTimer = nil
        idleTimer?.cancel()
        idleTimer = nil
        client.stateUpdateHandler = nil
        upstream?.stateUpdateHandler = nil
        client.cancel()
        upstream?.cancel()
        upstream = nil
        onClose()
    }
}
