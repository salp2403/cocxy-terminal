// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TimelineProjectFilterSwiftTestingTests.swift - Project timeline compatibility and filtering.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Timeline project identity")
struct TimelineProjectFilterSwiftTestingTests {
    @Test("legacy event decodes without project identity and canonical event round-trips")
    func timelineProjectIdentityCodableCompatibility() throws {
        let legacy = TimelineEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timestamp: Date(timeIntervalSinceReferenceDate: 10),
            type: .toolUse,
            sessionId: "legacy",
            summary: "Legacy",
            isError: false
        )
        let decoder = JSONDecoder()
        let legacyData = try JSONEncoder().encode(legacy)
        #expect(try decoder.decode(TimelineEvent.self, from: legacyData).projectIdentity == nil)

        let identity = ProjectID(rawValue: "/tmp/project-a")
        let canonical = legacy.assigningProjectIdentity(identity)
        let roundTrip = try decoder.decode(
            TimelineEvent.self,
            from: JSONEncoder().encode(canonical)
        )
        #expect(roundTrip.projectIdentity == identity)
    }

    @Test("hook mapping preserves canonical project identity")
    func hookMappingPreservesCanonicalProjectIdentity() {
        let identity = ProjectID(rawValue: "/tmp/project-a")
        let hook = HookEvent(
            type: .userPromptSubmit,
            sessionId: "session-a",
            timestamp: Date()
        )

        let event = TimelineEvent.from(hookEvent: hook, projectIdentity: identity)

        #expect(event.projectIdentity == identity)
    }

    @Test("project window and event filters compose without cross-project rows")
    func projectWindowAndEventFiltersCompose() {
        let projectA = ProjectID(rawValue: "/tmp/project-a")
        let projectB = ProjectID(rawValue: "/tmp/project-b")
        let windowA = WindowID()
        let windowB = WindowID()
        let events = [
            event("a-start", type: .subagentStart, project: projectA, window: windowA),
            event("a-stop", type: .subagentStop, project: projectA, window: windowA),
            event("a-tool", type: .toolUse, project: projectA, window: windowA),
            event("b-start", type: .subagentStart, project: projectB, window: windowA),
            event("a-other-window", type: .subagentStart, project: projectA, window: windowB),
            event("legacy", type: .subagentStart, project: nil, window: windowA),
        ]

        let filtered = TimelineEventFilter(
            eventType: .subagentStart,
            windowID: windowA,
            projectIdentity: projectA
        ).apply(to: events)

        #expect(filtered.map(\.summary) == ["a-start", "a-stop"])
    }

    private func event(
        _ summary: String,
        type: TimelineEventType,
        project: ProjectID?,
        window: WindowID
    ) -> TimelineEvent {
        TimelineEvent(
            type: type,
            sessionId: summary,
            windowID: window,
            projectIdentity: project,
            summary: summary
        )
    }
}
