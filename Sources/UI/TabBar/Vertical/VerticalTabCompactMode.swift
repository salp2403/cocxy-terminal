// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VerticalTabCompactMode.swift - View traits for vertical sidebar density modes.

import Foundation

extension Design {

    struct VerticalTabCompactMode: Equatable, Sendable {
        let mode: AuroraSidebarDisplayMode

        init(mode: AuroraSidebarDisplayMode) {
            self.mode = mode
        }

        var rowSpacing: Double {
            mode == .compact ? 0 : 4
        }

        var showsPrimaryMetadata: Bool {
            mode.showsPrimaryMetadata
        }

        var showsPaneMatrix: Bool {
            mode.showsPaneMatrix
        }

        var showsCloseButton: Bool {
            mode.showsCloseButton
        }

        var verticalPadding: Double {
            mode.verticalPadding
        }
    }
}
