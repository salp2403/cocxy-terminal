// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TimelineViewModel.swift - Reactive ViewModel bridging timeline store to SwiftUI.

import Foundation
import Combine

// MARK: - Timeline ViewModel

/// Bridges the thread-safe `AgentTimelineStoreImpl` to SwiftUI via `@Published`.
///
/// Subscribes to the store's `allEventsPublisher` so that the timeline view
/// updates in real-time as new events arrive, without needing to close and
/// reopen the panel.
@MainActor
final class TimelineViewModel: ObservableObject {

    /// All timeline events across sessions, sorted chronologically.
    @Published private(set) var events: [TimelineEvent] = []

    /// Callback for JSON export of all events.
    let onExportJSON: () -> Void

    /// Callback for Markdown export of all events.
    let onExportMarkdown: () -> Void

    private var cancellable: AnyCancellable?

    /// Creates a reactive timeline ViewModel.
    ///
    /// - Parameters:
    ///   - store: The timeline event store to subscribe to.
    ///   - onExportJSON: Called when the user requests JSON export.
    ///   - onExportMarkdown: Called when the user requests Markdown export.
    init(
        store: AgentTimelineStoreImpl,
        onExportJSON: @escaping () -> Void,
        onExportMarkdown: @escaping () -> Void
    ) {
        self.onExportJSON = onExportJSON
        self.onExportMarkdown = onExportMarkdown

        // Load initial snapshot.
        self.events = store.allEvents

        // Subscribe to live updates.
        self.cancellable = store.allEventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newEvents in
                self?.events = newEvents
            }
    }
}
