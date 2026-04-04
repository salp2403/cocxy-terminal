// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HookEventReceiver.swift - Receives and validates hook events from the socket.

import Foundation
import Combine

// MARK: - Hook Event Receiving Protocol

/// Contract for receiving raw hook event JSON from the CLI/socket layer.
///
/// The receiver validates JSON, tracks active sessions, and publishes
/// parsed events via Combine for downstream consumers.
///
/// - SeeAlso: ADR-008 Section 1.2
protocol HookEventReceiving: AnyObject {
    /// Processes raw JSON data from a hook event.
    ///
    /// - Parameter data: Raw JSON bytes.
    /// - Returns: `true` if the event was successfully parsed and published.
    @discardableResult
    func receiveRawJSON(_ data: Data) -> Bool

    /// Publisher that emits successfully parsed hook events.
    var eventPublisher: AnyPublisher<HookEvent, Never> { get }

    /// Set of session IDs that are currently active (have received SessionStart
    /// but not SessionEnd/Stop).
    var activeSessionIds: Set<String> { get }

    /// Number of events successfully received.
    var receivedEventCount: Int { get }

    /// Number of events that failed to parse.
    var failedEventCount: Int { get }
}

// MARK: - Hook Event Receiver Implementation

/// Thread-safe receiver that parses hook event JSON and publishes via Combine.
///
/// Designed to be called from the socket server's background threads.
/// Uses NSLock for thread safety on mutable state.
///
/// Invalid JSON is logged and skipped -- never crashes.
///
/// - SeeAlso: ADR-008 (Agent Intelligence Architecture)
final class HookEventReceiverImpl: HookEventReceiving, @unchecked Sendable {

    // MARK: - Publishers

    var eventPublisher: AnyPublisher<HookEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    // MARK: - State

    /// Active session IDs. Thread-safe via lock.
    private(set) var activeSessionIds: Set<String> {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _activeSessionIds
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _activeSessionIds = newValue
        }
    }

    /// Number of successfully received events.
    private(set) var receivedEventCount: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _receivedEventCount
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _receivedEventCount = newValue
        }
    }

    /// Number of failed parse attempts.
    private(set) var failedEventCount: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _failedEventCount
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _failedEventCount = newValue
        }
    }

    // MARK: - Last Event Context

    /// The session ID from the most recently received event.
    /// Used by the wiring layer to map events to the correct tab.
    private(set) var lastReceivedSessionId: String? {
        get { lock.lock(); defer { lock.unlock() }; return _lastSessionId }
        set { lock.lock(); defer { lock.unlock() }; _lastSessionId = newValue }
    }

    /// The working directory from the most recently received event.
    /// Used by the wiring layer to match events to tabs by directory.
    private(set) var lastReceivedCwd: String? {
        get { lock.lock(); defer { lock.unlock() }; return _lastCwd }
        set { lock.lock(); defer { lock.unlock() }; _lastCwd = newValue }
    }

    // MARK: - Private

    private let eventSubject = PassthroughSubject<HookEvent, Never>()
    private let lock = NSLock()
    private var _activeSessionIds: Set<String> = []
    private var _receivedEventCount: Int = 0
    private var _failedEventCount: Int = 0
    private var _lastSessionId: String?
    private var _lastCwd: String?

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - HookEventReceiving

    @discardableResult
    func receiveRawJSON(_ data: Data) -> Bool {
        guard !data.isEmpty else {
            incrementFailedCount()
            return false
        }

        // Extract session_id and cwd from raw JSON before decoding into HookEvent.
        // These fields are used to map events to the correct tab.
        if let rawJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            lastReceivedSessionId = rawJSON["session_id"] as? String
            lastReceivedCwd = rawJSON["cwd"] as? String
        }

        let event: HookEvent
        do {
            event = try decoder.decode(HookEvent.self, from: data)
        } catch {
            incrementFailedCount()
            return false
        }

        // Track active sessions
        updateSessionTracking(for: event)

        // Increment success counter BEFORE publishing, so subscribers
        // see a consistent count when they receive the event.
        incrementReceivedCount()

        // Publish to subscribers (after counter is updated)
        eventSubject.send(event)

        return true
    }

    /// Publishes an already-decoded hook event through the same pipeline used
    /// for socket-delivered JSON. This is used by internal producers such as
    /// CocxyCore's semantic adapter, which already operate on typed events.
    func receive(_ event: HookEvent) {
        lastReceivedSessionId = event.sessionId
        lastReceivedCwd = event.cwd
        updateSessionTracking(for: event)
        incrementReceivedCount()
        eventSubject.send(event)
    }

    // MARK: - Private Helpers

    private func updateSessionTracking(for event: HookEvent) {
        lock.lock()
        defer { lock.unlock() }

        switch event.type {
        case .sessionStart:
            _activeSessionIds.insert(event.sessionId)
        case .sessionEnd, .stop:
            _activeSessionIds.remove(event.sessionId)
        default:
            break
        }
    }

    private func incrementReceivedCount() {
        lock.lock()
        defer { lock.unlock() }
        _receivedEventCount += 1
    }

    private func incrementFailedCount() {
        lock.lock()
        defer { lock.unlock() }
        _failedEventCount += 1
    }
}
