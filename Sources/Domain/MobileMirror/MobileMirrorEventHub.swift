// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorEventHub.swift - Bounded, isolated event delivery for paired clients.

import Dispatch
import Foundation

final class MobileMirrorEventHub: @unchecked Sendable {
    typealias Sender = @Sendable (Data, Int32) -> Bool

    private let lock = NSLock()
    private var clients: [Int32: MobileMirrorEventClientWriter] = [:]
    private var clientOrder: [Int32] = []
    private let heartbeatQueue = DispatchQueue(label: "dev.cocxy.mobile.events")
    private let sender: Sender
    private var heartbeat: DispatchSourceTimer?

    init(sender: @escaping Sender = { MobileMirrorGateway.sendAll($0, to: $1) }) {
        self.sender = sender
    }

    func add(descriptor: Int32, close: @escaping @Sendable () -> Void) {
        let writer = MobileMirrorEventClientWriter(
            descriptor: descriptor,
            sender: sender,
            close: close
        ) { [weak self] descriptor, identifier in
            self?.remove(descriptor: descriptor, identifier: identifier)
        }
        lock.lock()
        clients[descriptor]?.stop()
        clients[descriptor] = writer
        clientOrder.removeAll { $0 == descriptor }
        clientOrder.append(descriptor)
        let needsHeartbeat = heartbeat == nil
        lock.unlock()
        if needsHeartbeat { startHeartbeat() }
        publish(event: "state", data: "{}")
    }

    func publish(event: String, data: String) {
        guard event.utf8.count <= 64,
              event.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
              data.utf8.count <= 16 * 1_024,
              !data.contains("\r"),
              !data.contains("\n") else {
            return
        }
        let payload = Data("event: \(event)\ndata: \(data)\n\n".utf8)
        heartbeatQueue.async { [weak self] in
            self?.send(payload)
        }
    }

    func stop() {
        heartbeatQueue.sync {
            heartbeat?.cancel()
            heartbeat = nil
        }
        lock.lock()
        let current = clientOrder.compactMap { clients[$0] }
        clients.removeAll()
        clientOrder.removeAll()
        lock.unlock()
        current.forEach { $0.stop() }
    }

    private func startHeartbeat() {
        heartbeatQueue.async { [weak self] in
            guard let self, self.heartbeat == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.heartbeatQueue)
            timer.schedule(deadline: .now() + 15, repeating: 15)
            timer.setEventHandler { [weak self] in
                self?.send(Data(": keep-alive\n\n".utf8))
            }
            self.heartbeat = timer
            timer.resume()
        }
    }

    private func send(_ data: Data) {
        lock.lock()
        let current = clientOrder.compactMap { clients[$0] }
        lock.unlock()
        current.forEach { $0.enqueue(data) }
    }

    private func remove(descriptor: Int32, identifier: UUID) {
        lock.lock()
        if clients[descriptor]?.identifier == identifier {
            clients.removeValue(forKey: descriptor)
            clientOrder.removeAll { $0 == descriptor }
        }
        lock.unlock()
    }
}

private final class MobileMirrorEventClientWriter: @unchecked Sendable {
    static let maximumPendingBytes = 64 * 1_024

    let descriptor: Int32
    let identifier = UUID()

    private let lock = NSLock()
    private let queue: DispatchQueue
    private let sender: MobileMirrorEventHub.Sender
    private let close: @Sendable () -> Void
    private let didStop: @Sendable (Int32, UUID) -> Void
    private var pendingBytes = 0
    private var stopped = false
    private var finishScheduled = false

    init(
        descriptor: Int32,
        sender: @escaping MobileMirrorEventHub.Sender,
        close: @escaping @Sendable () -> Void,
        didStop: @escaping @Sendable (Int32, UUID) -> Void
    ) {
        self.descriptor = descriptor
        self.sender = sender
        self.close = close
        self.didStop = didStop
        self.queue = DispatchQueue(label: "dev.cocxy.mobile.events.client.\(descriptor)")
    }

    func enqueue(_ data: Data) {
        lock.lock()
        guard !stopped,
              pendingBytes <= Self.maximumPendingBytes - data.count else {
            stopped = true
            let shouldFinish = !finishScheduled
            finishScheduled = true
            lock.unlock()
            if shouldFinish { finishOnQueue() }
            return
        }
        pendingBytes += data.count
        lock.unlock()
        queue.async { [weak self] in self?.send(data) }
    }

    func stop() {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        let shouldFinish = !finishScheduled
        finishScheduled = true
        lock.unlock()
        if shouldFinish { finishOnQueue() }
    }

    private func send(_ data: Data) {
        lock.lock()
        let shouldSend = !stopped
        lock.unlock()
        guard shouldSend else { return }

        let succeeded = sender(data, descriptor)
        lock.lock()
        pendingBytes -= data.count
        if !succeeded { stopped = true }
        let shouldFinish = !succeeded && !finishScheduled
        if shouldFinish { finishScheduled = true }
        lock.unlock()
        if shouldFinish { finish() }
    }

    private func finishOnQueue() {
        queue.async { [weak self] in self?.finish() }
    }

    private func finish() {
        didStop(descriptor, identifier)
        close()
    }
}
