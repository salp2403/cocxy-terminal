// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WindowEventBus.swift - Typed event bus for cross-window communication.

import Foundation
import Combine

// MARK: - Window Event

/// Events that can be broadcast between application windows.
///
/// Each case carries the minimum payload needed for the receiver to act.
/// Heavy data (themes, configs) is resolved by the receiver from its
/// local services — only the event trigger crosses the bus.
enum WindowEvent: Sendable, Equatable {
    /// A terminal theme was changed. All windows should apply it.
    case themeChanged(themeName: String)

    /// The font family or size was changed. All windows should refresh.
    case fontChanged

    /// The configuration file was reloaded. All windows should re-apply.
    case configReloaded

    /// A specific session should be focused (e.g., from a cross-window
    /// dashboard click or notification). Only the owning window acts.
    case focusSession(sessionID: SessionID)

    /// A global keyboard shortcut was invoked. Windows decide whether
    /// to handle it based on their current state.
    case globalShortcut(action: GlobalAction)

    /// An arbitrary named event with string key-value payload.
    /// Reserved for plugin/extension use in future phases.
    case custom(name: String, payload: [String: String])
}

/// Actions that can be triggered by global shortcuts.
enum GlobalAction: String, Sendable, Equatable {
    case newWindow
    case closeWindow
    case toggleFullScreen
    case showCommandPalette
    case showDashboard
    case showTimeline
}

// MARK: - Protocol

/// Contract for the window event bus.
///
/// The event bus is a simple publish-subscribe system for cross-window
/// communication. All events are broadcast to every subscriber; each
/// subscriber decides whether to act based on the event content.
///
/// Thread model: all operations on `@MainActor`. Subscribers receive
/// events synchronously on the main thread.
///
/// The bus does NOT store history. Late subscribers miss past events.
/// This is intentional — events are triggers, not state.
@MainActor
protocol WindowEventBroadcasting: AnyObject {

    /// Broadcasts an event to all subscribers.
    ///
    /// - Parameter event: The event to broadcast.
    func broadcast(_ event: WindowEvent)

    /// A publisher that emits every broadcast event.
    ///
    /// Subscribers should filter for events they care about.
    /// Use `.filter { ... }` or `switch` in the sink closure.
    var events: AnyPublisher<WindowEvent, Never> { get }
}

// MARK: - Implementation

/// Production implementation of the window event bus.
///
/// Wraps a `PassthroughSubject` for zero-history event delivery.
/// Lightweight — no storage, no replay, no persistence.
///
/// ## Memory Model
///
/// The bus holds no references to subscribers. Combine's subscription
/// model handles retain via `AnyCancellable` in each subscriber.
/// When a `MainWindowController` is deallocated, its cancellables
/// are released and the subscription is automatically removed.
@MainActor
final class WindowEventBusImpl: WindowEventBroadcasting {

    // MARK: - Subject

    private let subject = PassthroughSubject<WindowEvent, Never>()

    // MARK: - Protocol

    func broadcast(_ event: WindowEvent) {
        subject.send(event)
    }

    var events: AnyPublisher<WindowEvent, Never> {
        subject.eraseToAnyPublisher()
    }
}
