// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorEventHub.swift - Bounded, isolated event delivery for paired clients.

import Dispatch
import Foundation

final class MobileMirrorEventHub: @unchecked Sendable {
    typealias Sender = @Sendable (Data, Int32) -> Bool

    private struct RetainedEvent {
        let id: UInt64
        let payload: Data
    }

    private static let maximumRetainedEvents = 128
    private static let maximumRetainedBytes = 256 * 1_024

    private let lock = NSLock()
    private var clients: [Int32: MobileMirrorEventClientWriter] = [:]
    private var clientOrder: [Int32] = []
    private let heartbeatQueue = DispatchQueue(label: "dev.cocxy.mobile.events")
    private let sender: Sender
    private var heartbeat: DispatchSourceTimer?
    private var nextEventID: UInt64 = 0
    private var retainedEvents: [RetainedEvent] = []
    private var retainedBytes = 0

    init(sender: @escaping Sender = { MobileMirrorGateway.sendAll($0, to: $1) }) {
        self.sender = sender
    }

    func add(
        descriptor: Int32,
        afterEventID: UInt64? = nil,
        close: @escaping @Sendable () -> Void
    ) {
        let writer = MobileMirrorEventClientWriter(
            descriptor: descriptor,
            sender: sender,
            close: close
        ) { [weak self] descriptor, identifier in
            self?.remove(descriptor: descriptor, identifier: identifier)
        }
        heartbeatQueue.sync {
            self.lock.lock()
            self.clients[descriptor]?.stop()
            self.clients[descriptor] = writer
            self.clientOrder.removeAll { $0 == descriptor }
            self.clientOrder.append(descriptor)
            self.lock.unlock()

            self.startHeartbeatIfNeeded()
            if let afterEventID {
                for event in self.retainedEvents where event.id > afterEventID {
                    writer.enqueue(event.payload)
                }
            }
            writer.enqueue(self.makePayload(event: "state", data: "{}"))
        }
    }

    func publish(event: String, data: String) {
        guard event.utf8.count <= 64,
              event.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
              data.utf8.count <= 16 * 1_024,
              !data.contains("\r"),
              !data.contains("\n") else {
            return
        }
        heartbeatQueue.async { [weak self] in
            guard let self else { return }
            let payload = self.makePayload(event: event, data: data)
            if event != "state" {
                self.retain(payload: payload, id: self.nextEventID)
            }
            self.send(payload)
        }
    }

    func disconnect(descriptor: Int32) {
        lock.lock()
        let client = clients.removeValue(forKey: descriptor)
        clientOrder.removeAll { $0 == descriptor }
        lock.unlock()
        client?.stop()
    }

    func stop() {
        heartbeatQueue.sync {
            heartbeat?.cancel()
            heartbeat = nil
            nextEventID = 0
            retainedEvents.removeAll(keepingCapacity: false)
            retainedBytes = 0
        }
        lock.lock()
        let current = clientOrder.compactMap { clients[$0] }
        clients.removeAll()
        clientOrder.removeAll()
        lock.unlock()
        current.forEach { $0.stop() }
    }

    private func startHeartbeatIfNeeded() {
        guard heartbeat == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: heartbeatQueue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            self?.send(Data(": keep-alive\n\n".utf8))
        }
        heartbeat = timer
        timer.resume()
    }

    private func makePayload(event: String, data: String) -> Data {
        if nextEventID == UInt64.max {
            nextEventID = 1
            retainedEvents.removeAll(keepingCapacity: true)
            retainedBytes = 0
        } else {
            nextEventID += 1
        }
        return Data("id: \(nextEventID)\nevent: \(event)\ndata: \(data)\n\n".utf8)
    }

    private func retain(payload: Data, id: UInt64) {
        retainedEvents.append(RetainedEvent(id: id, payload: payload))
        retainedBytes += payload.count
        while retainedEvents.count > Self.maximumRetainedEvents
            || retainedBytes > Self.maximumRetainedBytes {
            retainedBytes -= retainedEvents.removeFirst().payload.count
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
