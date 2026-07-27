// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProxyConnectionRelay.swift - Backpressured client-to-SSH byte relay.

import Foundation
import Network

/// Relays one authenticated client connection to one SSH direct-tcpip stream.
@MainActor
final class ProxyConnectionRelay {
    private let client: NWConnection
    private let upstream: any ProxyUpstreamTransport
    private let onClose: @MainActor () -> Void

    private var isClosed = false
    private var clientReadComplete = false
    private var upstreamReadComplete = false

    init(
        client: NWConnection,
        upstream: any ProxyUpstreamTransport,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.client = client
        self.upstream = upstream
        self.onClose = onClose
    }

    func start(initialClientData: Data = Data()) {
        client.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor in self?.close() }
            default:
                break
            }
        }

        if initialClientData.isEmpty {
            relayClientToUpstream()
        } else {
            sendToUpstream(initialClientData) { [weak self] succeeded in
                guard let self, succeeded else { return }
                self.relayClientToUpstream()
            }
        }
        relayUpstreamToClient()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        client.stateUpdateHandler = nil
        client.cancel()
        upstream.cancel()
        onClose()
    }

    private func relayClientToUpstream() {
        guard !isClosed, !clientReadComplete else { return }
        client.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, !self.isClosed else { return }
                if let error {
                    _ = error
                    self.close()
                    return
                }
                if let data, !data.isEmpty {
                    self.sendToUpstream(data) { [weak self] succeeded in
                        guard let self, succeeded else { return }
                        if isComplete {
                            self.finishClientRead()
                        } else {
                            self.relayClientToUpstream()
                        }
                    }
                } else if isComplete {
                    self.finishClientRead()
                } else {
                    self.relayClientToUpstream()
                }
            }
        }
    }

    private func sendToUpstream(
        _ data: Data,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        upstream.send(data) { [weak self] result in
            Task { @MainActor in
                guard let self, !self.isClosed else { return }
                switch result {
                case .success:
                    completion(true)
                case .failure:
                    self.close()
                    completion(false)
                }
            }
        }
    }

    private func finishClientRead() {
        guard !clientReadComplete else { return }
        clientReadComplete = true
        upstream.closeWrite()
        finishIfComplete()
    }

    private func relayUpstreamToClient() {
        guard !isClosed, !upstreamReadComplete else { return }
        upstream.receive(maximumLength: 65_536) { [weak self] result in
            Task { @MainActor in
                guard let self, !self.isClosed else { return }
                switch result {
                case .success(let data?):
                    self.client.send(
                        content: data,
                        completion: .contentProcessed { [weak self] error in
                            Task { @MainActor in
                                guard let self, !self.isClosed else { return }
                                if error == nil {
                                    self.relayUpstreamToClient()
                                } else {
                                    self.close()
                                }
                            }
                        }
                    )
                case .success(nil):
                    self.finishUpstreamRead()
                case .failure:
                    self.close()
                }
            }
        }
    }

    private func finishUpstreamRead() {
        guard !upstreamReadComplete else { return }
        upstreamReadComplete = true
        client.send(
            content: nil,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    guard let self, !self.isClosed else { return }
                    if error != nil {
                        self.close()
                    } else {
                        self.finishIfComplete()
                    }
                }
            }
        )
    }

    private func finishIfComplete() {
        if clientReadComplete && upstreamReadComplete {
            close()
        }
    }
}
