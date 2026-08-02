// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TimelineEventFilter.swift - Composable project, window, and type filtering.

import Foundation

struct TimelineEventFilter: Sendable, Equatable {
    var eventType: TimelineEventType?
    var windowID: WindowID?
    var projectIdentity: ProjectID?

    func apply(to events: [TimelineEvent]) -> [TimelineEvent] {
        events.filter { event in
            matchesWindow(event)
                && matchesProject(event)
                && matchesType(event)
        }
    }

    private func matchesWindow(_ event: TimelineEvent) -> Bool {
        windowID.map { event.windowID == $0 } ?? true
    }

    private func matchesProject(_ event: TimelineEvent) -> Bool {
        projectIdentity.map { event.projectIdentity == $0 } ?? true
    }

    private func matchesType(_ event: TimelineEvent) -> Bool {
        guard let eventType else { return true }
        if eventType == .subagentStart {
            return event.type == .subagentStart || event.type == .subagentStop
        }
        return event.type == eventType
    }
}
