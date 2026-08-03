// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalPasteNormalizationSwiftTestingTests.swift - Shared paste normalization coverage.

import Testing
@testable import CocxyTerminal

@MainActor
extension CocxyCoreViewTests {
    @Test("terminal paste text normalizes Notes control characters")
    func terminalPasteTextNormalizesNotesControlCharacters() {
        let text = "alpha\rbravo\r\ncharlie\u{2028}delta\u{2029}echo\u{0000}\u{001B}[31m"
        let normalized = CocxyCoreView.normalizedTerminalPasteText(text)
        #expect(normalized == "alpha\nbravo\ncharlie\ndelta\necho[31m")
    }
}
