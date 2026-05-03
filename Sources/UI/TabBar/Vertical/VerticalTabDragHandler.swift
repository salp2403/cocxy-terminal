// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VerticalTabDragHandler.swift - Drag payload parsing for vertical tab rows and split panes.

import Foundation

extension Design {

    enum VerticalTabDragPayload: Equatable, Sendable {
        case session(String)
        case pane(String)

        init?(encodedValue: String) {
            if let value = encodedValue.verticalTabPayloadValue(prefix: "session:") {
                self = .session(value)
                return
            }
            if let value = encodedValue.verticalTabPayloadValue(prefix: "pane:") {
                self = .pane(value)
                return
            }
            return nil
        }

        var encodedValue: String {
            switch self {
            case .session(let id): return "session:\(id)"
            case .pane(let id): return "pane:\(id)"
            }
        }
    }

    struct VerticalTabDragHandler {
        let currentSessionID: String
        var onMoveSessionBefore: ((String) -> Void)? = nil
        var onMovePaneToSession: ((String) -> Void)? = nil

        @discardableResult
        func handle(_ payload: VerticalTabDragPayload) -> Bool {
            switch payload {
            case .session(let sourceSessionID):
                guard sourceSessionID != currentSessionID,
                      let onMoveSessionBefore else {
                    return false
                }
                onMoveSessionBefore(sourceSessionID)
                return true
            case .pane(let paneID):
                guard let onMovePaneToSession else {
                    return false
                }
                onMovePaneToSession(paneID)
                return true
            }
        }
    }
}

private extension String {
    func verticalTabPayloadValue(prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        let value = String(dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }
}
