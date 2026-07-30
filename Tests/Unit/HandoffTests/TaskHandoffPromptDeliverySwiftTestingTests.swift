// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("Task handoff prompt delivery")
struct TaskHandoffPromptDeliverySwiftTestingTests {
    @Test("multiline prompt is one bracketed paste followed by one submit")
    func multilinePromptUsesBracketedPaste() {
        let payload = MainWindowController.agentTeamPromptPayload(
            "# Task Handoff\n\nContinue.",
            usesBracketedPaste: true
        )

        #expect(payload == "\u{1B}[200~# Task Handoff\n\nContinue.\u{1B}[201~\r")
    }

    @Test("fallback preserves multiline content without intermediate submits")
    func fallbackIsOneLine() {
        let payload = MainWindowController.agentTeamPromptPayload(
            "first\\value\nsecond",
            usesBracketedPaste: false
        )

        #expect(payload == "Task context with encoded newlines: first\\\\value\\nsecond\r")
        #expect(payload.filter { $0 == "\r" }.count == 1)
        #expect(!payload.dropLast().contains("\n"))
    }
}
