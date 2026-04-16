// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HandleHookEventRoutingSwiftTests.swift
// Verifies that the socket-level hook-event command routes the new
// CwdChanged and FileChanged payloads into the receiver and that they
// reach Combine subscribers as fully decoded events.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

private final class LockedHookEventBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [HookEvent] = []

    func append(_ event: HookEvent) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    func snapshot() -> [HookEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

@Suite("AppSocketCommandHandler routing for CwdChanged / FileChanged")
struct HandleHookEventRoutingSwiftTests {

    @Test("CwdChanged hook-event command increments receiver counters")
    func cwdChangedRoutesIntoReceiver() {
        let receiver = HookEventReceiverImpl()
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: receiver
        )

        let payload = #"""
        {
            "hook_event_name": "CwdChanged",
            "session_id": "sess-routing-001",
            "cwd": "/tmp/new",
            "previous_cwd": "/tmp/old"
        }
        """#

        let request = SocketRequest(
            id: "rt-1",
            command: "hook-event",
            params: ["payload": payload]
        )
        let response = handler.handleCommand(request)

        #expect(response.success)
        #expect(receiver.receivedEventCount == 1)
        #expect(receiver.failedEventCount == 0)
    }

    @Test("FileChanged hook-event command publishes a fully decoded event")
    func fileChangedReachesSubscriber() async throws {
        let receiver = HookEventReceiverImpl()
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: receiver
        )

        // Capture the next event published on the eventPublisher.
        let collectedEvents = LockedHookEventBuffer()
        var cancellable: AnyCancellable?
        cancellable = receiver.eventPublisher
            .sink { event in
                collectedEvents.append(event)
            }
        defer { cancellable?.cancel() }

        let payload = #"""
        {
            "hook_event_name": "FileChanged",
            "session_id": "sess-routing-002",
            "cwd": "/tmp/project",
            "file_path": "/tmp/project/README.md",
            "change_type": "write"
        }
        """#

        let request = SocketRequest(
            id: "rt-2",
            command: "hook-event",
            params: ["payload": payload]
        )
        let response = handler.handleCommand(request)

        #expect(response.success)

        // Event publishing is synchronous from receiveRawJSON, but small
        // sleep keeps the test resilient to scheduler quirks under load.
        try await Task.sleep(nanoseconds: 50_000_000)

        let events = collectedEvents.snapshot()

        guard let event = events.first else {
            Issue.record("No hook event reached the subscriber")
            return
        }
        #expect(event.type == .fileChanged)
        #expect(event.cwd == "/tmp/project")
        guard case .fileChanged(let data) = event.data else {
            Issue.record("Expected .fileChanged data on routed event")
            return
        }
        #expect(data.filePath == "/tmp/project/README.md")
        #expect(data.changeType == "write")
    }

    @Test("hook-event routing keeps existing failure modes for unknown event names")
    func unknownEventNameStillReturnsFailure() {
        let receiver = HookEventReceiverImpl()
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: receiver
        )
        let payload = #"""
        {
            "hook_event_name": "TotallyMadeUpEvent",
            "session_id": "sess-routing-003",
            "cwd": "/x"
        }
        """#
        let request = SocketRequest(
            id: "rt-3",
            command: "hook-event",
            params: ["payload": payload]
        )
        let response = handler.handleCommand(request)
        #expect(!response.success)
        #expect(receiver.failedEventCount == 1)
    }
}
