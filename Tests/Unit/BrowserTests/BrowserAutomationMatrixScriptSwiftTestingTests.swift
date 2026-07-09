// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing

@Suite("Browser automation matrix smoke script")
struct BrowserAutomationMatrixScriptSwiftTestingTests {
    @Test("matrix script persists action screenshots and covers core Browser V2 surfaces")
    func matrixScriptCoversActionEvidenceAndCoreScenarios() throws {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/smoke-browser-automation-matrix.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(script.contains("COCXY_BROWSER_ACTION_EVIDENCE_DIR"))
        #expect(script.contains("action-screenshots"))
        #expect(script.contains("matrix.tsv"))
        #expect(script.contains("BROWSER_MATRIX_MIN_SCENARIOS=80"))
        #expect(script.contains("scenario_count="))
        #expect(script.contains("scenario_count < BROWSER_MATRIX_MIN_SCENARIOS"))
        #expect(script.contains("browser split"))
        #expect(!script.contains("pkill -x CocxyTerminal"))

        for command in [
            "browser snapshot",
            "browser context",
            "browser state save",
            "browser state load",
            "browser text",
            "browser tabs",
            "browser frames",
            "browser get html",
            "browser get value",
            "browser get attr",
            "browser get title",
            "browser get count",
            "browser get box",
            "browser get styles",
            "browser is visible",
            "browser is enabled",
            "browser is checked",
            "browser find text",
            "browser find placeholder",
            "browser find alt",
            "browser find title",
            "browser find first",
            "browser find last",
            "browser find nth",
            "browser screenshot",
            "browser console",
            "browser wait",
            "browser cookies set",
            "browser cookies list",
            "browser cookies delete",
            "browser network",
            "browser downloads",
            "browser storage set",
            "browser add script",
            "browser init scripts add",
            "browser focus",
            "browser fill",
            "browser type",
            "browser press",
            "browser hover",
            "browser click",
            "browser dblclick",
            "browser check",
            "browser uncheck",
            "browser upload",
            "browser select",
            "browser scroll",
            "browser scroll-into-view"
        ] {
            #expect(script.contains(command))
        }
    }
}
