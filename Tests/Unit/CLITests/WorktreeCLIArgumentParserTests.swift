// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeCLIArgumentParserTests.swift - Coverage for the four
// `cocxy worktree <subcommand>` forms introduced in v0.1.81.

import Foundation
import Testing
@testable import CocxyCLILib

@Suite("CLIArgumentParser — worktree")
struct WorktreeCLIArgumentParserTests {

    // MARK: - add

    @Test("worktree add with no flags defaults to nil agent/branch/base-ref")
    func addBareDefaults() throws {
        let parsed = try CLIArgumentParser.parse(["worktree", "add"])
        switch parsed {
        case .worktreeAdd(let agent, let branch, let baseRef):
            #expect(agent == nil)
            #expect(branch == nil)
            #expect(baseRef == nil)
        default:
            Issue.record("Expected worktreeAdd, got \(parsed)")
        }
    }

    @Test("worktree add --agent populates the agent field")
    func addAgentFlag() throws {
        let parsed = try CLIArgumentParser.parse(
            ["worktree", "add", "--agent", "claude"]
        )
        switch parsed {
        case .worktreeAdd(let agent, _, _):
            #expect(agent == "claude")
        default:
            Issue.record("Expected worktreeAdd")
        }
    }

    @Test("worktree add --branch sets the template override")
    func addBranchFlag() throws {
        let parsed = try CLIArgumentParser.parse(
            ["worktree", "add", "--branch", "feature/{id}"]
        )
        switch parsed {
        case .worktreeAdd(_, let branch, _):
            #expect(branch == "feature/{id}")
        default:
            Issue.record("Expected worktreeAdd")
        }
    }

    @Test("worktree add --base-ref sets the base commit override")
    func addBaseRefFlag() throws {
        let parsed = try CLIArgumentParser.parse(
            ["worktree", "add", "--base-ref", "develop"]
        )
        switch parsed {
        case .worktreeAdd(_, _, let baseRef):
            #expect(baseRef == "develop")
        default:
            Issue.record("Expected worktreeAdd")
        }
    }

    @Test("worktree add accepts every flag at once")
    func addAllFlags() throws {
        let parsed = try CLIArgumentParser.parse([
            "worktree", "add",
            "--agent", "codex",
            "--branch", "task/{id}",
            "--base-ref", "main"
        ])
        switch parsed {
        case .worktreeAdd(let agent, let branch, let baseRef):
            #expect(agent == "codex")
            #expect(branch == "task/{id}")
            #expect(baseRef == "main")
        default:
            Issue.record("Expected worktreeAdd")
        }
    }

    @Test("worktree add rejects unknown flags")
    func addUnknownFlagThrows() {
        #expect(throws: CLIError.self) {
            _ = try CLIArgumentParser.parse(
                ["worktree", "add", "--bogus", "value"]
            )
        }
    }

    @Test("worktree add rejects --agent without a value")
    func addMissingAgentValueThrows() {
        #expect(throws: CLIError.self) {
            _ = try CLIArgumentParser.parse(
                ["worktree", "add", "--agent"]
            )
        }
    }

    // MARK: - list

    @Test("worktree list parses to worktreeList")
    func listParses() throws {
        let parsed = try CLIArgumentParser.parse(["worktree", "list"])
        #expect(parsed == .worktreeList)
    }

    // MARK: - remove

    @Test("worktree remove requires an id")
    func removeRequiresID() {
        #expect(throws: CLIError.self) {
            _ = try CLIArgumentParser.parse(["worktree", "remove"])
        }
    }

    @Test("worktree remove sets force=false by default")
    func removeDefaultNonForce() throws {
        let parsed = try CLIArgumentParser.parse(
            ["worktree", "remove", "abc123"]
        )
        switch parsed {
        case .worktreeRemove(let id, let force):
            #expect(id == "abc123")
            #expect(!force)
        default:
            Issue.record("Expected worktreeRemove")
        }
    }

    @Test("worktree remove --force sets force=true")
    func removeForceFlag() throws {
        let parsed = try CLIArgumentParser.parse(
            ["worktree", "remove", "abc123", "--force"]
        )
        switch parsed {
        case .worktreeRemove(_, let force):
            #expect(force)
        default:
            Issue.record("Expected worktreeRemove")
        }
    }

    @Test("worktree remove -f is the short alias for --force")
    func removeForceShortAlias() throws {
        let parsed = try CLIArgumentParser.parse(
            ["worktree", "remove", "abc123", "-f"]
        )
        switch parsed {
        case .worktreeRemove(_, let force):
            #expect(force)
        default:
            Issue.record("Expected worktreeRemove")
        }
    }

    @Test("worktree remove rejects unknown options")
    func removeUnknownOptionThrows() {
        #expect(throws: CLIError.self) {
            _ = try CLIArgumentParser.parse(
                ["worktree", "remove", "abc123", "--bogus"]
            )
        }
    }

    // MARK: - prune

    @Test("worktree prune parses to worktreePrune")
    func pruneParses() throws {
        let parsed = try CLIArgumentParser.parse(["worktree", "prune"])
        #expect(parsed == .worktreePrune)
    }

    // MARK: - shape

    @Test("worktree with no subcommand throws a helpful error")
    func missingSubcommandThrows() {
        #expect(throws: CLIError.self) {
            _ = try CLIArgumentParser.parse(["worktree"])
        }
    }

    @Test("worktree with unknown subcommand throws")
    func unknownSubcommandThrows() {
        #expect(throws: CLIError.self) {
            _ = try CLIArgumentParser.parse(["worktree", "burn-down"])
        }
    }
}
