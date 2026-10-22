// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Agent team executable preflight")
struct AgentTeamExecutablePreflightSwiftTestingTests {
    @Test("handoff aliases resolve before provider executable preflight")
    func handoffAliasesResolveBeforePreflight() {
        #expect(AppDelegate.agentTeamProviderForPreflight(
            command: .handoffImport,
            params: ["agent": " droid "]
        ) == .factory)
        #expect(AppDelegate.agentTeamProviderForPreflight(
            command: .handoffImport,
            params: ["agent": "open-code"]
        ) == .opencode)
        #expect(AppDelegate.agentTeamProviderForPreflight(
            command: .agentTeamLaunch,
            params: ["provider": "codex"]
        ) == .codex)
        #expect(AppDelegate.agentTeamProviderForPreflight(
            command: .agentTeamLaunch,
            params: ["provider": " \n "]
        ) == .claudeCode)
        #expect(AppDelegate.agentTeamProviderForPreflight(
            command: .handoffImport,
            params: ["agent": "  \n"]
        ) == .claudeCode)
    }

    @Test("verbose shell lookup retains its bounded tail and final executable line")
    func executableLookupRetainsBoundedTail() {
        var capture = Data()
        BoundedDataTail.append(
            Data(String(repeating: "profile notice\n", count: 400).utf8),
            to: &capture,
            limit: 4_096
        )
        BoundedDataTail.append(
            Data("/opt/tools/codex\n".utf8),
            to: &capture,
            limit: 4_096
        )

        #expect(capture.count == 4_096)
        #expect(AgentTeamExecutableLocator.lastNonemptyLine(
            in: String(decoding: capture, as: UTF8.self)
        ) == "/opt/tools/codex")
    }
}
