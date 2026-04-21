// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeBranchTests.swift - Coverage for WorktreeBranch.expand and
// sanitizeGitRefComponent.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("WorktreeBranch.expand")
struct WorktreeBranchExpandTests {

    private static func fixedDate() -> Date {
        // 2026-04-21 12:00 UTC. Rendered with POSIX locale + UTC
        // timezone so every test gets the same "2026-04-21" string.
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 4, day: 21,
            hour: 12, minute: 0, second: 0
        )
        return components.date!
    }

    @Test("substitutes {agent}, {id} and {date}")
    func substitutesAllPlaceholders() {
        let result = WorktreeBranch.expand(
            template: "cocxy/{agent}/{date}-{id}",
            agent: "claude",
            id: "a3f7de",
            date: Self.fixedDate(),
            timeZone: TimeZone(identifier: "UTC")!
        )
        #expect(result == "cocxy/claude/2026-04-21-a3f7de")
    }

    @Test("nil agent falls back to 'worktree'")
    func nilAgentUsesFallback() {
        let result = WorktreeBranch.expand(
            template: "cocxy/{agent}/{id}",
            agent: nil,
            id: "abc123"
        )
        #expect(result == "cocxy/worktree/abc123")
    }

    @Test("agent name is sanitised against git ref rules")
    func agentIsSanitised() {
        let result = WorktreeBranch.expand(
            template: "{agent}/{id}",
            agent: "Claude Code",
            id: "wt-1"
        )
        // Space becomes dash; the id is kept as-is.
        #expect(result == "Claude-Code/wt-1")
    }

    @Test("agent name made entirely of forbidden characters falls back")
    func allInvalidAgentFallsBack() {
        let result = WorktreeBranch.expand(
            template: "{agent}/{id}",
            agent: "~^:?*[\\",
            id: "abc123"
        )
        #expect(result == "worktree/abc123")
    }

    @Test("template without {date} ignores the date parameter")
    func templateWithoutDateIgnoresDate() {
        let result = WorktreeBranch.expand(
            template: "cocxy/{agent}/{id}",
            agent: "claude",
            id: "abc",
            date: Self.fixedDate()
        )
        #expect(!result.contains("2026"))
    }

    @Test("double slashes in the template collapse to single slashes")
    func doubleSlashCollapses() {
        let result = WorktreeBranch.expand(
            template: "cocxy//{agent}/{id}",
            agent: "claude",
            id: "abc123"
        )
        #expect(result == "cocxy/claude/abc123")
    }

    @Test("double dots in the expanded branch collapse to a dash")
    func doubleDotsBecomeDashes() {
        let result = WorktreeBranch.expand(
            template: "cocxy/{agent}..{id}",
            agent: "claude",
            id: "abc123"
        )
        #expect(!result.contains(".."))
    }

    @Test("leading dots, slashes and dashes are stripped")
    func leadingSeparatorsStripped() {
        let result = WorktreeBranch.expand(
            template: "./{agent}/{id}",
            agent: "claude",
            id: "abc123"
        )
        #expect(result.first != ".")
        #expect(result.first != "/")
        #expect(result == "claude/abc123")
    }

    @Test("date is rendered deterministically in yyyy-MM-dd POSIX format")
    func dateIsRenderedDeterministically() {
        // Even if the system locale is es_ES, the output stays
        // "2026-04-21" because the helper forces `en_US_POSIX`.
        let result = WorktreeBranch.expand(
            template: "{date}",
            agent: nil,
            id: "abc123",
            date: Self.fixedDate(),
            timeZone: TimeZone(identifier: "UTC")!
        )
        #expect(result == "2026-04-21")
    }
}

@Suite("WorktreeBranch.sanitizeGitRefComponent")
struct WorktreeBranchSanitiseTests {

    @Test("keeps alphanumerics untouched")
    func keepsAlphanumerics() {
        #expect(WorktreeBranch.sanitizeGitRefComponent("Claude") == "Claude")
        #expect(WorktreeBranch.sanitizeGitRefComponent("codex123") == "codex123")
    }

    @Test("replaces spaces and git-forbidden characters with a dash")
    func replacesInvalidChars() {
        #expect(WorktreeBranch.sanitizeGitRefComponent("Claude Code") == "Claude-Code")
        #expect(WorktreeBranch.sanitizeGitRefComponent("foo:bar") == "foo-bar")
        #expect(WorktreeBranch.sanitizeGitRefComponent("foo?bar") == "foo-bar")
        #expect(WorktreeBranch.sanitizeGitRefComponent("foo*bar") == "foo-bar")
        #expect(WorktreeBranch.sanitizeGitRefComponent("foo[bar") == "foo-bar")
    }

    @Test("collapses consecutive invalid characters into a single dash")
    func collapsesConsecutiveInvalidChars() {
        #expect(WorktreeBranch.sanitizeGitRefComponent("foo!!!bar") == "foo-bar")
        #expect(WorktreeBranch.sanitizeGitRefComponent("foo   bar") == "foo-bar")
    }

    @Test("double dots are collapsed to a dash")
    func doubleDotsCollapsed() {
        let sanitised = WorktreeBranch.sanitizeGitRefComponent("foo..bar")
        #expect(!sanitised.contains(".."))
    }

    @Test("leading and trailing non-alphanumerics are trimmed")
    func trimsLeadingTrailing() {
        #expect(WorktreeBranch.sanitizeGitRefComponent(".foo.") == "foo")
        #expect(WorktreeBranch.sanitizeGitRefComponent("-foo-") == "foo")
        #expect(WorktreeBranch.sanitizeGitRefComponent("_foo_") == "foo")
    }

    @Test("empty and fully-invalid inputs return empty")
    func invalidInputsReturnEmpty() {
        #expect(WorktreeBranch.sanitizeGitRefComponent("") == "")
        // Pure invalid chars collapse to a single dash then trim leaves
        // nothing.
        #expect(WorktreeBranch.sanitizeGitRefComponent("???") == "")
    }

    @Test("slash is considered invalid at the component level")
    func slashIsInvalidInComponent() {
        // Slashes must come from the *template*, not from a sanitised
        // agent name, so a slash inside the input is treated like any
        // other forbidden character.
        #expect(WorktreeBranch.sanitizeGitRefComponent("foo/bar") == "foo-bar")
    }
}
