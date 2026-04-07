// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WindowEventBusTests.swift - Tests for WindowEventBusImpl.

import Testing
import Foundation
import Combine
@testable import CocxyTerminal

// MARK: - Window Event Bus Tests

@Suite("Window Event Bus")
@MainActor
struct WindowEventBusTests {

    private func makeBus() -> WindowEventBusImpl {
        WindowEventBusImpl()
    }

    // MARK: - Broadcast and Subscribe

    @Test("Broadcast delivers event to subscriber")
    func broadcastDeliversEvent() {
        let bus = makeBus()
        var received: WindowEvent?

        let cancellable = bus.events.sink { received = $0 }
        bus.broadcast(.themeChanged(themeName: "One Dark"))

        #expect(received == .themeChanged(themeName: "One Dark"))
        _ = cancellable
    }

    @Test("Broadcast delivers to multiple subscribers")
    func broadcastToMultipleSubscribers() {
        let bus = makeBus()
        var count = 0

        let c1 = bus.events.sink { _ in count += 1 }
        let c2 = bus.events.sink { _ in count += 1 }
        let c3 = bus.events.sink { _ in count += 1 }
        bus.broadcast(.fontChanged)

        #expect(count == 3)
        _ = (c1, c2, c3)
    }

    @Test("Cancelled subscription does not receive events")
    func cancelledSubscriptionSilent() {
        let bus = makeBus()
        var received = false

        let cancellable = bus.events.sink { _ in received = true }
        cancellable.cancel()
        bus.broadcast(.configReloaded)

        #expect(!received)
    }

    @Test("No subscribers does not crash")
    func noSubscribersNoCrash() {
        let bus = makeBus()
        // Should not crash or raise.
        bus.broadcast(.fontChanged)
    }

    // MARK: - Event Payloads

    @Test("Theme changed carries correct name")
    func themeChangedPayload() {
        let bus = makeBus()
        var themeName: String?

        let cancellable = bus.events.sink { event in
            if case .themeChanged(let name) = event {
                themeName = name
            }
        }
        bus.broadcast(.themeChanged(themeName: "Dracula"))

        #expect(themeName == "Dracula")
        _ = cancellable
    }

    @Test("Focus session carries correct session ID")
    func focusSessionPayload() {
        let bus = makeBus()
        let targetID = SessionID()
        var receivedID: SessionID?

        let cancellable = bus.events.sink { event in
            if case .focusSession(let id) = event {
                receivedID = id
            }
        }
        bus.broadcast(.focusSession(sessionID: targetID))

        #expect(receivedID == targetID)
        _ = cancellable
    }

    @Test("Global shortcut carries correct action")
    func globalShortcutPayload() {
        let bus = makeBus()
        var receivedAction: GlobalAction?

        let cancellable = bus.events.sink { event in
            if case .globalShortcut(let action) = event {
                receivedAction = action
            }
        }
        bus.broadcast(.globalShortcut(action: .showDashboard))

        #expect(receivedAction == .showDashboard)
        _ = cancellable
    }

    @Test("Custom event carries name and payload")
    func customEventPayload() {
        let bus = makeBus()
        var receivedName: String?
        var receivedPayload: [String: String]?

        let cancellable = bus.events.sink { event in
            if case .custom(let name, let payload) = event {
                receivedName = name
                receivedPayload = payload
            }
        }
        bus.broadcast(.custom(name: "plugin.activate", payload: ["id": "abc123"]))

        #expect(receivedName == "plugin.activate")
        #expect(receivedPayload == ["id": "abc123"])
        _ = cancellable
    }

    // MARK: - Event Sequence

    @Test("Multiple broadcasts deliver events in order")
    func broadcastsInOrder() {
        let bus = makeBus()
        var events: [WindowEvent] = []

        let cancellable = bus.events.sink { events.append($0) }

        bus.broadcast(.themeChanged(themeName: "A"))
        bus.broadcast(.fontChanged)
        bus.broadcast(.configReloaded)

        #expect(events.count == 3)
        #expect(events[0] == .themeChanged(themeName: "A"))
        #expect(events[1] == .fontChanged)
        #expect(events[2] == .configReloaded)
        _ = cancellable
    }

    @Test("Late subscriber misses past events")
    func lateSubscriberMissesPast() {
        let bus = makeBus()
        bus.broadcast(.themeChanged(themeName: "Early"))

        var received: [WindowEvent] = []
        let cancellable = bus.events.sink { received.append($0) }

        bus.broadcast(.fontChanged)

        #expect(received.count == 1)
        #expect(received.first == .fontChanged)
        _ = cancellable
    }
}
