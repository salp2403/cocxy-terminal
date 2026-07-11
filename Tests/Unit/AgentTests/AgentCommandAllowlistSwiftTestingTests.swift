// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentCommandAllowlistSwiftTestingTests.swift - Local command allowlist parsing.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AgentCommandAllowlist")
struct AgentCommandAllowlistSwiftTestingTests {

    @Test("allowlist loads exact rules and preserves prefix entries")
    func allowlistLoadsExactAndPrefixRules() throws {
        let allowlist = AgentCommandAllowlist(fileProvider: InMemoryAgentCommandAllowlistFileProvider(content: """
        # User-controlled local allowlist for non-destructive commands.
        exact = ["git status --short", "swift build"]
        prefix = ["swift test --filter", "git diff --"]
        """))

        let rules = try allowlist.loadRules()

        #expect(rules == [
            .exact("git status --short"),
            .exact("swift build"),
            .prefix("swift test --filter"),
            .prefix("git diff --"),
        ])
    }

    @Test("preserved prefix entries cannot grant automatic approval")
    func preservedPrefixEntriesCannotGrantAutomaticApproval() throws {
        let allowlist = AgentCommandAllowlist(fileProvider: InMemoryAgentCommandAllowlistFileProvider(content: """
        prefix = ["swift test --filter"]
        """))

        let rule = try #require(allowlist.loadRules().first)

        #expect(rule == .prefix("swift test --filter"))
        #expect(!rule.allowsAutomaticApproval(for: "swift test --filter AgentTests"))
    }

    @Test("allowlist ignores empty strings unsupported keys and malformed arrays")
    func allowlistIgnoresUnsupportedContent() throws {
        let allowlist = AgentCommandAllowlist(fileProvider: InMemoryAgentCommandAllowlistFileProvider(content: """
        exact = ["", "   ", "git status"]
        prefix = not-an-array
        glob = ["rm *"]
        """))

        let rules = try allowlist.loadRules()

        #expect(rules == [.exact("git status")])
    }

    @Test("missing allowlist file returns no rules")
    func missingAllowlistReturnsNoRules() throws {
        let allowlist = AgentCommandAllowlist(fileProvider: InMemoryAgentCommandAllowlistFileProvider(content: nil))

        #expect(try allowlist.loadRules().isEmpty)
    }
}

private struct InMemoryAgentCommandAllowlistFileProvider: AgentCommandAllowlistFileProviding {
    let content: String?

    func readCommandAllowlistFile() throws -> String? {
        content
    }
}
