// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectConfigWorktreeOverridesTests.swift - Coverage for per-project
// `[worktree]` overrides loaded from `.cocxy.toml` files (v0.1.81).

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ProjectConfig — [worktree] per-project overrides")
struct ProjectConfigWorktreeOverridesTests {

    // MARK: - Parsing

    @Test("cocxy.toml with full [worktree] overrides populates every field")
    func fullWorktreeOverridesPopulate() {
        let toml = """
        [worktree]
        enabled = true
        base-ref = "release/v2"
        branch-template = "feat/{agent}-{id}"
        on-close = "prompt"
        open-in-new-tab = false
        inherit-project-config = false
        show-badge = false
        """
        let parsed = ProjectConfigService().parse(toml)
        let unwrapped = try? #require(parsed)

        #expect(unwrapped?.worktreeEnabled == true)
        #expect(unwrapped?.worktreeBaseRef == "release/v2")
        #expect(unwrapped?.worktreeBranchTemplate == "feat/{agent}-{id}")
        #expect(unwrapped?.worktreeOnClose == .prompt)
        #expect(unwrapped?.worktreeOpenInNewTab == false)
        #expect(unwrapped?.worktreeInheritProjectConfig == false)
        #expect(unwrapped?.worktreeShowBadge == false)
    }

    @Test("partial [worktree] overrides leave unset fields nil")
    func partialWorktreeOverridesKeepRestNil() {
        let toml = """
        [worktree]
        enabled = true
        """
        let parsed = ProjectConfigService().parse(toml)
        let unwrapped = try? #require(parsed)

        #expect(unwrapped?.worktreeEnabled == true)
        #expect(unwrapped?.worktreeBaseRef == nil)
        #expect(unwrapped?.worktreeBranchTemplate == nil)
        #expect(unwrapped?.worktreeOnClose == nil)
        #expect(unwrapped?.worktreeOpenInNewTab == nil)
        #expect(unwrapped?.worktreeInheritProjectConfig == nil)
        #expect(unwrapped?.worktreeShowBadge == nil)
    }

    @Test("unknown on-close string yields nil override, never a wrong enum")
    func unknownOnCloseYieldsNilOverride() {
        let toml = """
        [worktree]
        on-close = "nuke"
        """
        let parsed = ProjectConfigService().parse(toml)

        // The worktree table contained only an invalid value, so no
        // usable override exists — `parse` returns nil because
        // `isEmpty` considers the config empty.
        #expect(parsed == nil)
    }

    @Test("empty [worktree] table produces no overrides")
    func emptyWorktreeTableProducesNothing() {
        let toml = """
        [worktree]
        """
        let parsed = ProjectConfigService().parse(toml)
        #expect(parsed == nil)
    }

    @Test("wrong value types silently drop overrides (never crash)")
    func wrongValueTypesDropOverrides() {
        let toml = """
        [worktree]
        enabled = "yes"
        open-in-new-tab = 1
        """
        let parsed = ProjectConfigService().parse(toml)

        // No valid bools extracted → no overrides → parse returns nil.
        #expect(parsed == nil)
    }

    // MARK: - Merging with CocxyConfig.applying

    @Test("applying() replaces global worktree fields with overrides")
    func applyingReplacesGlobalFieldsWithOverrides() {
        let base = CocxyConfig.defaults
        let globalEnabled = WorktreeConfig(
            enabled: false,
            basePath: "~/.cocxy/worktrees",
            branchTemplate: "cocxy/{agent}/{id}",
            baseRef: "HEAD",
            onClose: .keep,
            openInNewTab: true,
            idLength: 6,
            inheritProjectConfig: true,
            showBadge: true
        )
        let root = CocxyConfig(
            general: base.general,
            appearance: base.appearance,
            terminal: base.terminal,
            agentDetection: base.agentDetection,
            codeReview: base.codeReview,
            notifications: base.notifications,
            quickTerminal: base.quickTerminal,
            keybindings: base.keybindings,
            sessions: base.sessions,
            worktree: globalEnabled
        )

        let overrides = ProjectConfig(
            worktreeEnabled: true,
            worktreeBaseRef: "main",
            worktreeBranchTemplate: "task/{id}",
            worktreeOnClose: .prompt,
            worktreeOpenInNewTab: false,
            worktreeInheritProjectConfig: false,
            worktreeShowBadge: false
        )
        let merged = root.applying(projectOverrides: overrides)

        #expect(merged.worktree.enabled == true)
        #expect(merged.worktree.baseRef == "main")
        #expect(merged.worktree.branchTemplate == "task/{id}")
        #expect(merged.worktree.onClose == .prompt)
        #expect(merged.worktree.openInNewTab == false)
        #expect(merged.worktree.inheritProjectConfig == false)
        #expect(merged.worktree.showBadge == false)
        // basePath + idLength stay global on purpose.
        #expect(merged.worktree.basePath == globalEnabled.basePath)
        #expect(merged.worktree.idLength == globalEnabled.idLength)
    }

    @Test("applying() preserves unset global fields when overrides are nil")
    func applyingPreservesUnsetFields() {
        let base = CocxyConfig.defaults
        let overrides = ProjectConfig(
            worktreeBaseRef: "release/v2"
        )
        let merged = base.applying(projectOverrides: overrides)

        // Only baseRef changed; every other worktree field comes from
        // the global config.
        #expect(merged.worktree.baseRef == "release/v2")
        #expect(merged.worktree.enabled == base.worktree.enabled)
        #expect(merged.worktree.branchTemplate == base.worktree.branchTemplate)
        #expect(merged.worktree.onClose == base.worktree.onClose)
        #expect(merged.worktree.openInNewTab == base.worktree.openInNewTab)
        #expect(merged.worktree.inheritProjectConfig == base.worktree.inheritProjectConfig)
        #expect(merged.worktree.showBadge == base.worktree.showBadge)
    }

    @Test("basePath is never overridable per-project")
    func basePathNeverOverridable() {
        // Even a malicious .cocxy.toml cannot redirect the worktree
        // storage path because `ProjectConfig` has no `worktreeBasePath`
        // field in its initialiser. Compile-time guarantee; this test
        // just pins the invariant as a regression guard.
        let overrides = ProjectConfig()
        let merged = CocxyConfig.defaults.applying(projectOverrides: overrides)
        #expect(merged.worktree.basePath == "~/.cocxy/worktrees")
    }

    @Test("isEmpty returns true only when every override (including worktree) is nil")
    func isEmptyAccountsForWorktreeOverrides() {
        #expect(ProjectConfig().isEmpty == true)
        #expect(ProjectConfig(worktreeEnabled: true).isEmpty == false)
        #expect(ProjectConfig(worktreeBaseRef: "dev").isEmpty == false)
        #expect(ProjectConfig(worktreeBranchTemplate: "x").isEmpty == false)
        #expect(ProjectConfig(worktreeOnClose: .remove).isEmpty == false)
        #expect(ProjectConfig(worktreeOpenInNewTab: false).isEmpty == false)
        #expect(ProjectConfig(worktreeInheritProjectConfig: false).isEmpty == false)
        #expect(ProjectConfig(worktreeShowBadge: false).isEmpty == false)
    }
}
