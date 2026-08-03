// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskInboxEntryKind+ProjectHome.swift - Project inbox icon presentation.

extension TaskInboxEntryKind {
    var projectHomeIconName: String {
        switch self {
        case .fanOut: return "square.stack.3d.up"
        case .queuedTask: return "calendar.badge.clock"
        case .liveAgent: return "terminal"
        case .handoff: return "arrow.right.arrow.left"
        }
    }
}
