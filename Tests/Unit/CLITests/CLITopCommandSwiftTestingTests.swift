// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyCLILib

@Suite("CLI top command")
struct CLITopCommandSwiftTestingTests {

    @Test("top parses as interactive by default")
    func topParsesAsInteractiveByDefault() throws {
        #expect(try CLIArgumentParser.parse(["top"]) == .top(mode: .interactive(intervalSeconds: 1.0)))
    }

    @Test("top parses once and json modes")
    func topParsesOnceAndJSONModes() throws {
        #expect(try CLIArgumentParser.parse(["top", "--once"]) == .top(mode: .once))
        #expect(try CLIArgumentParser.parse(["top", "--json"]) == .top(mode: .json))
    }

    @Test("top parses custom interval")
    func topParsesCustomInterval() throws {
        #expect(try CLIArgumentParser.parse(["top", "--interval", "0.5"]) == .top(mode: .interactive(intervalSeconds: 0.5)))
    }

    @Test("top rejects conflicting output modes")
    func topRejectsConflictingOutputModes() {
        #expect(throws: CLIError.invalidArgument(
            command: "top",
            argument: "--json",
            reason: "Use only one of --once or --json."
        )) {
            try CLIArgumentParser.parse(["top", "--once", "--json"])
        }
    }

    @Test("snapshot merges status and tabs into top rows")
    func snapshotMergesStatusAndTabsIntoTopRows() {
        let snapshot = CLITopSnapshot.make(
            statusData: [
                "status": "running",
                "version": "1.0.5",
                "tabs": "2",
                "child_pid": "123",
                "process_alive": "true",
                "semantic_state_name": "command_running",
            ],
            tabData: [
                "count": "2",
                "tab_0_id": "tab-a",
                "tab_0_title": "Shell",
                "tab_0_active": "false",
                "tab_1_id": "tab-b",
                "tab_1_title": "Agent",
                "tab_1_active": "true",
            ],
            generatedAt: Date(timeIntervalSince1970: 0),
            activeMetrics: CLITopProcessMetrics(cpuPercent: "2.5", memoryRSS: "34.0M")
        )

        #expect(snapshot.tabCount == 2)
        #expect(snapshot.activeTabID == "tab-b")
        #expect(snapshot.tabs[0].pid == "n/a")
        #expect(snapshot.tabs[1].pid == "123")
        #expect(snapshot.tabs[1].cpu == "2.5")
        #expect(snapshot.tabs[1].memory == "34.0M")
        #expect(snapshot.tabs[1].agentState == "command_running")
    }

    @Test("renderer includes command hints and process columns")
    func rendererIncludesCommandHintsAndProcessColumns() {
        let snapshot = CLITopSnapshot.make(
            statusData: ["status": "running", "version": "1.0.5", "tabs": "1", "child_pid": "123"],
            tabData: [
                "count": "1",
                "tab_0_id": "tab-a",
                "tab_0_title": "Agent",
                "tab_0_active": "true",
            ],
            generatedAt: Date(timeIntervalSince1970: 0),
            activeMetrics: CLITopProcessMetrics(cpuPercent: "1.0", memoryRSS: "10.0M")
        )

        let output = CLITopRenderer.render(snapshot)

        #expect(output.contains("Cocxy top - running"))
        #expect(output.contains("PID"))
        #expect(output.contains("CPU%"))
        #expect(output.contains("MEM"))
        #expect(output.contains("AGENT"))
        #expect(output.contains("Agent"))
        #expect(output.contains("q quit"))
        #expect(output.contains("Enter focus tab"))
        #expect(output.contains("k close tab"))
    }

    @Test("json renderer emits schema and tabs")
    func jsonRendererEmitsSchemaAndTabs() throws {
        let snapshot = CLITopSnapshot.make(
            statusData: ["status": "running", "version": "1.0.5", "tabs": "1"],
            tabData: ["count": "0"],
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        let data = Data(try CLITopRenderer.renderJSON(snapshot).utf8)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["status"] as? String == "running")
        #expect(object["tabCount"] as? Int == 1)
        #expect((object["tabs"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test("help advertises top")
    func helpAdvertisesTop() {
        #expect(CLIArgumentParser.helpText().contains("cocxy top"))
    }
}
