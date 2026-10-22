// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import SwiftUI
import Testing
@testable import CocxyTerminal

@Suite("Terminal history UX")
@MainActor
struct TerminalHistoryPillViewTests {
    @Test("history pill appears only above live output and invokes its return action")
    func historyPillVisibilityAndAction() {
        let pill = TerminalHistoryPillView()
        var jumpCount = 0
        pill.onJumpToBottom = { jumpCount += 1 }

        #expect(pill.isHidden == true)
        pill.update(linesAbove: 42)
        #expect(pill.isHidden == false)
        #expect(pill.linesAbove == 42)
        #expect(pill.title.contains("42 lines up"))

        pill.performClick(nil)
        #expect(jumpCount == 1)

        pill.update(linesAbove: 0)
        #expect(pill.isHidden == true)
    }

    @Test("classic and Aurora status models expose terminal mouse capture")
    func statusModelsExposeMouseCapture() {
        let classic = StatusBarView(
            hostname: "user@mac",
            gitBranch: nil,
            agentSummary: AgentSummary(),
            isTerminalMouseCaptured: true
        )
        let aurora = Design.AuroraStatusBarView(
            workspaces: [],
            ports: [],
            timeline: .constant(.init(progress: 1)),
            clockLabel: "12:00",
            isTerminalMouseCaptured: true
        )

        #expect(classic.isTerminalMouseCaptured == true)
        #expect(aurora.isTerminalMouseCaptured == true)
    }
}
