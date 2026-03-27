// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTimelineStore.swift - Protocol and implementation for the agent timeline store.

import Foundation
import Combine

// MARK: - Agent Timeline Providing Protocol

/// Contract for accessing the structured timeline of agent actions per session.
///
/// The timeline is an append-only log of events organized by session ID.
/// Primary source: Layer 0 hooks (rich, structured data).
/// Fallback: Layers 1-3 state transitions (degraded, summary-only).
///
/// The store enforces a maximum of 1000 events per session to stay within
/// the 5 MB memory budget defined in ADR-008.
///
/// - SeeAlso: ADR-008 Section 5.1 (AgentTimelineProviding)
/// - SeeAlso: HU-108, HU-109 in PRD-002
protocol AgentTimelineProviding: AnyObject {
    /// Returns all events for a specific session, in chronological order.
    ///
    /// - Parameter sessionId: The session to query.
    /// - Returns: Events sorted by timestamp (oldest first).
    func events(for sessionId: String) -> [TimelineEvent]

    /// Returns all events across all sessions, in chronological order.
    var allEvents: [TimelineEvent] { get }

    /// Appends a new event to the timeline for its session.
    ///
    /// If the session has reached the maximum event count (1000),
    /// the oldest event is evicted (FIFO).
    ///
    /// - Parameter event: The event to add.
    func addEvent(_ event: TimelineEvent)

    /// Publisher that emits the event list for a specific session whenever it changes.
    ///
    /// - Parameter sessionId: The session to observe.
    /// - Returns: A publisher emitting the full event list on each change.
    func eventsPublisher(for sessionId: String) -> AnyPublisher<[TimelineEvent], Never>

    /// Exports all events for a session as formatted JSON.
    ///
    /// - Parameter sessionId: The session to export.
    /// - Returns: UTF-8 encoded JSON data.
    func exportJSON(for sessionId: String) -> Data

    /// Exports all events for a session as a Markdown table.
    ///
    /// - Parameter sessionId: The session to export.
    /// - Returns: Markdown-formatted string.
    func exportMarkdown(for sessionId: String) -> String

    /// Removes all events for a specific session.
    ///
    /// - Parameter sessionId: The session to clear.
    func clearEvents(for sessionId: String)

    /// Returns the number of events stored for a specific session.
    ///
    /// - Parameter sessionId: The session to query.
    /// - Returns: The event count.
    func eventCount(for sessionId: String) -> Int
}

// MARK: - Agent Timeline Store Implementation

/// Thread-safe, in-memory store for agent timeline events.
///
/// Organizes events by session ID in a dictionary. Uses NSLock for
/// thread safety since hook events can arrive from background threads.
///
/// ## FIFO Eviction
///
/// Each session can hold at most `maxEventsPerSession` events (default 1000).
/// When a new event arrives and the session is at capacity, the oldest event
/// is removed before the new one is appended.
///
/// ## Reactive Updates
///
/// Subscribers receive the full event list for a session on every change
/// via `eventsPublisher(for:)`. This is implemented using a
/// `PassthroughSubject` that emits after each mutation.
///
/// - SeeAlso: ADR-008 Section 5.1
final class AgentTimelineStoreImpl: AgentTimelineProviding, @unchecked Sendable {

    // MARK: - Configuration

    /// Maximum number of events stored per session before FIFO eviction.
    let maxEventsPerSession: Int

    // MARK: - Private State

    /// Events organized by session ID. Protected by `lock`.
    private var eventsBySession: [String: [TimelineEvent]] = [:]

    /// Subject for publishing changes. Key is session ID.
    private var subjects: [String: PassthroughSubject<[TimelineEvent], Never>] = [:]

    /// Lock for thread-safe access to mutable state.
    private let lock = NSLock()

    // MARK: - Initialization

    /// Creates a new timeline store.
    ///
    /// - Parameter maxEventsPerSession: Maximum events per session before FIFO eviction.
    ///   Defaults to 1000.
    init(maxEventsPerSession: Int = 1000) {
        self.maxEventsPerSession = maxEventsPerSession
    }

    // MARK: - AgentTimelineProviding

    func events(for sessionId: String) -> [TimelineEvent] {
        lock.lock()
        defer { lock.unlock() }
        return eventsBySession[sessionId] ?? []
    }

    var allEvents: [TimelineEvent] {
        lock.lock()
        defer { lock.unlock() }
        return eventsBySession.values
            .flatMap { $0 }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func addEvent(_ event: TimelineEvent) {
        lock.lock()

        var sessionEvents = eventsBySession[event.sessionId] ?? []

        // FIFO eviction: remove the oldest if at capacity
        if sessionEvents.count >= maxEventsPerSession {
            sessionEvents.removeFirst()
        }

        sessionEvents.append(event)
        eventsBySession[event.sessionId] = sessionEvents

        let currentEvents = sessionEvents
        let subject = getOrCreateSubject(for: event.sessionId)

        lock.unlock()

        // Publish outside the lock to avoid potential deadlocks with subscribers.
        subject.send(currentEvents)
    }

    func eventsPublisher(for sessionId: String) -> AnyPublisher<[TimelineEvent], Never> {
        lock.lock()
        let subject = getOrCreateSubject(for: sessionId)
        lock.unlock()
        return subject.eraseToAnyPublisher()
    }

    func exportJSON(for sessionId: String) -> Data {
        let sessionEvents = events(for: sessionId)
        return TimelineExporter.exportJSON(events: sessionEvents)
    }

    func exportMarkdown(for sessionId: String) -> String {
        let sessionEvents = events(for: sessionId)
        return TimelineExporter.exportMarkdown(events: sessionEvents)
    }

    func clearEvents(for sessionId: String) {
        lock.lock()
        eventsBySession.removeValue(forKey: sessionId)
        let subject = subjects[sessionId]
        lock.unlock()

        subject?.send([])
    }

    func eventCount(for sessionId: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return eventsBySession[sessionId]?.count ?? 0
    }

    // MARK: - Private Helpers

    /// Returns the existing subject for a session or creates a new one.
    /// MUST be called while holding the lock.
    private func getOrCreateSubject(for sessionId: String) -> PassthroughSubject<[TimelineEvent], Never> {
        if let existing = subjects[sessionId] {
            return existing
        }
        let subject = PassthroughSubject<[TimelineEvent], Never>()
        subjects[sessionId] = subject
        return subject
    }
}
