// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TimelineNavigating.swift - Protocol for navigating from timeline events to terminal positions.

import Foundation

// MARK: - Timeline Navigating Protocol

/// Contract for navigating the terminal scrollback to the position of a timeline event.
///
/// When a user taps on a timeline event row, the navigator scrolls the terminal
/// to the approximate position where that event occurred and optionally highlights
/// the affected file.
///
/// The concrete implementation depends on the active terminal engine's
/// scrollback/navigation support. A production implementation can be injected
/// through `TimelineNavigatorImpl`, while `TimelineNavigatorStub` remains useful
/// for tests.
///
/// - SeeAlso: `TimelineNavigationDispatcher` (dispatch helper with nil-safety)
/// - SeeAlso: `TimelineNavigatorStub` (logging stub for development)
/// - SeeAlso: HU-108 (Agent Timeline View)
protocol TimelineNavigating: AnyObject {
    /// Navigate terminal scrollback to the approximate position of this event.
    ///
    /// The implementation should scroll the terminal view to the line range
    /// where this event's output appeared. If the exact position cannot be
    /// determined, a best-effort approximation is acceptable.
    ///
    /// - Parameter event: The timeline event to navigate to.
    func navigateToEvent(_ event: TimelineEvent)

    /// Highlight the file mentioned in the event, if applicable.
    ///
    /// For events involving file operations (Write, Read, Edit), this method
    /// can be used to visually indicate which file was affected. The concrete
    /// implementation may open a file preview or highlight the path in the UI.
    ///
    /// - Parameter filePath: The absolute path of the file to highlight.
    func highlightFile(_ filePath: String)
}

// MARK: - Timeline Navigation Dispatcher

/// Nil-safe dispatcher for timeline navigation events.
///
/// Holds an optional weak reference to a `TimelineNavigating` implementation.
/// When the navigator is nil (not yet connected), navigation calls are silently ignored.
///
/// This pattern allows SwiftUI views to dispatch navigation without worrying about
/// the lifecycle of the navigator (which lives in the AppKit layer).
///
/// - SeeAlso: `TimelineNavigating`
final class TimelineNavigationDispatcher {

    /// The navigator to dispatch events to. Nil means navigation is a no-op.
    /// Strong reference: the dispatcher owns the navigator's lifecycle.
    var navigator: TimelineNavigating?

    /// Dispatches a navigation request for the given event.
    ///
    /// If the navigator is nil, this is a silent no-op.
    /// If the event has a `filePath`, `highlightFile` is also called.
    ///
    /// - Parameter event: The timeline event to navigate to.
    func dispatchNavigation(for event: TimelineEvent) {
        guard let navigator = navigator else { return }
        navigator.navigateToEvent(event)
        if let filePath = event.filePath {
            navigator.highlightFile(filePath)
        }
    }
}

// MARK: - Timeline Navigator Implementation

/// Closure-driven production implementation of `TimelineNavigating`.
///
/// Keeps the domain contract free of AppKit dependencies while letting the
/// AppDelegate inject concrete cross-window/tab navigation behavior.
final class TimelineNavigatorImpl: TimelineNavigating {
    typealias NavigateHandler = (TimelineEvent) -> Void
    typealias HighlightHandler = (String) -> Void

    private let navigateHandler: NavigateHandler
    private let highlightHandler: HighlightHandler

    init(
        navigateHandler: @escaping NavigateHandler,
        highlightHandler: @escaping HighlightHandler = { _ in }
    ) {
        self.navigateHandler = navigateHandler
        self.highlightHandler = highlightHandler
    }

    func navigateToEvent(_ event: TimelineEvent) {
        navigateHandler(event)
    }

    func highlightFile(_ filePath: String) {
        highlightHandler(filePath)
    }
}

// MARK: - Timeline Navigator Stub

/// Logging stub implementation of `TimelineNavigating`.
///
/// Records all calls for inspection. Intended for unit tests and lightweight
/// instrumentation of navigation flows.
///
/// - SeeAlso: `TimelineNavigating`
final class TimelineNavigatorStub: TimelineNavigating {

    /// All events passed to `navigateToEvent(_:)`, in order of invocation.
    private(set) var navigatedEvents: [TimelineEvent] = []

    /// All file paths passed to `highlightFile(_:)`, in order of invocation.
    private(set) var highlightedFiles: [String] = []

    func navigateToEvent(_ event: TimelineEvent) {
        navigatedEvents.append(event)
    }

    func highlightFile(_ filePath: String) {
        highlightedFiles.append(filePath)
    }
}
