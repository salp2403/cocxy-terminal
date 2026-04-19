// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraSourceBuilderSwiftTestingTests.swift - Hermetic coverage for the
// pure domain-to-presentation builder that feeds
// `Design.AuroraWorkspaceAdapter`.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("AuroraSourceBuilder — domain → Aurora sources")
struct AuroraSourceBuilderSwiftTestingTests {

    // MARK: - Stub resolver

    /// Dictionary-backed resolver stub. Maps tab working directory →
    /// resolved workspace root, returning `nil` for missing entries.
    private struct StubResolver: AuroraWorkspaceRootResolver, @unchecked Sendable {
        let table: [URL: URL]
        func workspaceRoot(for directory: URL) -> URL? { table[directory] }
    }

    private static let alwaysNilResolver = StubResolver(table: [:])

    // MARK: - Helpers

    private func makeTab(
        title: String = "tab",
        cwd: URL = URL(fileURLWithPath: "/Users/user/proj"),
        branch: String? = nil
    ) -> Tab {
        Tab(
            title: title,
            workingDirectory: cwd,
            gitBranch: branch
        )
    }

    private func makeStore(
        entries: [(SurfaceID, SurfaceAgentState)] = []
    ) -> AgentStatePerSurfaceStore {
        let store = AgentStatePerSurfaceStore()
        for (id, state) in entries {
            store.set(surfaceID: id, state: state)
        }
        return store
    }

    private func agent(_ name: String) -> DetectedAgent {
        DetectedAgent(
            name: name,
            launchCommand: name,
            startedAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - Invariant 1: empty input

    @Test
    func emptyTabsProduceEmptyOutput() {
        let result = AuroraSourceBuilder.buildSources(
            tabs: [],
            surfaceIDsByTab: [:],
            store: makeStore(),
            workspaceRootResolver: Self.alwaysNilResolver
        )
        #expect(result.isEmpty)
    }

    // MARK: - Invariant 2: tab order preserved

    @Test
    func tabOrderIsPreserved() {
        let a = makeTab(title: "a")
        let b = makeTab(title: "b")
        let c = makeTab(title: "c")
        let result = AuroraSourceBuilder.buildSources(
            tabs: [a, b, c],
            surfaceIDsByTab: [:],
            store: makeStore(),
            workspaceRootResolver: Self.alwaysNilResolver
        )
        #expect(result.count == 3)
        #expect(result[0].id == a.id.rawValue.uuidString)
        #expect(result[1].id == b.id.rawValue.uuidString)
        #expect(result[2].id == c.id.rawValue.uuidString)
    }

    // MARK: - Invariant 3: surfaces from map (caller-preserving order)

    @Test
    func surfacesFollowCallerOrderFromMap() {
        let tab = makeTab()
        let s1 = SurfaceID()
        let s2 = SurfaceID()
        let s3 = SurfaceID()
        let result = AuroraSourceBuilder.buildSources(
            tabs: [tab],
            surfaceIDsByTab: [tab.id: [s1, s2, s3]],
            store: makeStore(),
            workspaceRootResolver: Self.alwaysNilResolver
        )
        let surfaces = result.first?.surfaces ?? []
        #expect(surfaces.count == 3)
        #expect(surfaces[0].id == s1.rawValue.uuidString)
        #expect(surfaces[1].id == s2.rawValue.uuidString)
        #expect(surfaces[2].id == s3.rawValue.uuidString)
    }

    @Test
    func missingSurfaceMapEntryProducesZeroSurfaces() {
        let tab = makeTab()
        let result = AuroraSourceBuilder.buildSources(
            tabs: [tab],
            surfaceIDsByTab: [:], // no entry for this tab
            store: makeStore(),
            workspaceRootResolver: Self.alwaysNilResolver
        )
        #expect(result.first?.surfaces.isEmpty == true)
    }

    // MARK: - Invariant 4: workspaceGroup resolution

    @Test
    func workspaceGroupUsesResolverRootWhenAvailable() {
        let tab = makeTab(
            cwd: URL(fileURLWithPath: "/Users/user/proj/src/subdir"),
            branch: "main"
        )
        let resolver = StubResolver(table: [
            URL(fileURLWithPath: "/Users/user/proj/src/subdir")
                : URL(fileURLWithPath: "/Users/user/proj"),
        ])
        let result = AuroraSourceBuilder.buildSources(
            tabs: [tab],
            surfaceIDsByTab: [:],
            store: makeStore(),
            workspaceRootResolver: resolver
        )
        #expect(result.first?.workspaceGroup == "proj")
    }

    @Test
    func workspaceGroupFallsBackToTabCwdLastComponentWhenResolverReturnsNil() {
        let tab = makeTab(
            cwd: URL(fileURLWithPath: "/Users/user/orphan")
        )
        let result = AuroraSourceBuilder.buildSources(
            tabs: [tab],
            surfaceIDsByTab: [:],
            store: makeStore(),
            workspaceRootResolver: Self.alwaysNilResolver
        )
        #expect(result.first?.workspaceGroup == "orphan")
    }

    // MARK: - Invariant 5: branch passes through verbatim

    @Test
    func branchPassesThroughFromTab() {
        let tab = makeTab(branch: "feat/foo")
        let result = AuroraSourceBuilder.buildSources(
            tabs: [tab],
            surfaceIDsByTab: [:],
            store: makeStore(),
            workspaceRootResolver: Self.alwaysNilResolver
        )
        #expect(result.first?.branch == "feat/foo")
    }

    @Test
    func missingBranchStaysNil() {
        let tab = makeTab(branch: nil)
        let result = AuroraSourceBuilder.buildSources(
            tabs: [tab],
            surfaceIDsByTab: [:],
            store: makeStore(),
            workspaceRootResolver: Self.alwaysNilResolver
        )
        #expect(result.first?.branch == nil)
    }

    // MARK: - Invariant 6: surface name

    @Test
    func surfaceNameUsesDetectedAgentWhenPresent() {
        let tab = makeTab()
        let sid = SurfaceID()
        let state = SurfaceAgentState(
            agentState: .working,
            detectedAgent: agent("claude")
        )
        let result = AuroraSourceBuilder.buildSources(
            tabs: [tab],
            surfaceIDsByTab: [tab.id: [sid]],
            store: makeStore(entries: [(sid, state)]),
            workspaceRootResolver: Self.alwaysNilResolver
        )
        #expect(result.first?.surfaces.first?.name == "claude")
    }

    @Test
    func surfaceNameFallsBackToPaneIndexWithoutAgent() {
        let tab = makeTab()
        let s1 = SurfaceID()
        let s2 = SurfaceID()
        let result = AuroraSourceBuilder.buildSources(
            tabs: [tab],
            surfaceIDsByTab: [tab.id: [s1, s2]],
            store: makeStore(),
            workspaceRootResolver: Self.alwaysNilResolver
        )
        let surfaces = result.first?.surfaces ?? []
        #expect(surfaces[0].name == "pane 1")
        #expect(surfaces[1].name == "pane 2")
    }

    // MARK: - Invariant 7: agent / state mapping (total function)

    @Test
    func agentAccentMappingIsCaseInsensitive() {
        #expect(AuroraSourceBuilder.accent(for: agent("Claude")) == .claude)
        #expect(AuroraSourceBuilder.accent(for: agent("claude-code")) == .claude)
        #expect(AuroraSourceBuilder.accent(for: agent("Codex CLI")) == .codex)
        #expect(AuroraSourceBuilder.accent(for: agent("GEMINI")) == .gemini)
        #expect(AuroraSourceBuilder.accent(for: agent("aider-chat")) == .aider)
    }

    @Test
    func unknownAgentFallsBackToShell() {
        #expect(AuroraSourceBuilder.accent(for: agent("ripgrep")) == .shell)
        #expect(AuroraSourceBuilder.accent(for: nil) == .shell)
        let emptyAgent = DetectedAgent(name: "", launchCommand: "", startedAt: Date())
        #expect(AuroraSourceBuilder.accent(for: emptyAgent) == .shell)
    }

    @Test
    func stateRoleMappingIsTotal() {
        #expect(AuroraSourceBuilder.role(for: .idle) == .idle)
        #expect(AuroraSourceBuilder.role(for: .launched) == .launched)
        #expect(AuroraSourceBuilder.role(for: .working) == .working)
        #expect(AuroraSourceBuilder.role(for: .waitingInput) == .waiting)
        #expect(AuroraSourceBuilder.role(for: .finished) == .finished)
        #expect(AuroraSourceBuilder.role(for: .error) == .error)
    }

    // MARK: - End-to-end: realistic multi-tab snapshot

    @Test
    func endToEndMultiTabSnapshotProducesExpectedShape() {
        // tab A: 2 splits (claude working + codex waiting), on main branch,
        // inside /Users/user/alpha/src — resolver returns /Users/user/alpha.
        // tab B: 1 surface, no agent, in a path the resolver cannot resolve.
        let rootA = URL(fileURLWithPath: "/Users/user/alpha")
        let cwdA = URL(fileURLWithPath: "/Users/user/alpha/src")
        let cwdB = URL(fileURLWithPath: "/tmp/ephemeral")

        let tabA = makeTab(title: "alpha", cwd: cwdA, branch: "main")
        let tabB = makeTab(title: "beta", cwd: cwdB, branch: nil)

        let sA1 = SurfaceID()
        let sA2 = SurfaceID()
        let sB1 = SurfaceID()

        let stateA1 = SurfaceAgentState(
            agentState: .working,
            detectedAgent: agent("claude-code")
        )
        let stateA2 = SurfaceAgentState(
            agentState: .waitingInput,
            detectedAgent: agent("codex-cli")
        )
        let stateB1 = SurfaceAgentState(agentState: .idle)

        let resolver = StubResolver(table: [cwdA: rootA])
        let store = makeStore(entries: [
            (sA1, stateA1),
            (sA2, stateA2),
            (sB1, stateB1),
        ])

        let result = AuroraSourceBuilder.buildSources(
            tabs: [tabA, tabB],
            surfaceIDsByTab: [
                tabA.id: [sA1, sA2],
                tabB.id: [sB1],
            ],
            store: store,
            workspaceRootResolver: resolver
        )

        #expect(result.count == 2)

        let a = result[0]
        // `displayTitle` derives its label from `workingDirectory.lastPathComponent`,
        // not `title`. CWD is `/Users/user/alpha/src`, so the label becomes `src (main)`.
        #expect(a.name == "src (main)")
        #expect(a.workspaceGroup == "alpha")
        #expect(a.branch == "main")
        #expect(a.surfaces.count == 2)
        #expect(a.surfaces[0].agent == .claude)
        #expect(a.surfaces[0].state == .working)
        #expect(a.surfaces[1].agent == .codex)
        #expect(a.surfaces[1].state == .waiting)

        let b = result[1]
        #expect(b.name == "ephemeral")
        #expect(b.workspaceGroup == "ephemeral")
        #expect(b.branch == nil)
        #expect(b.surfaces.count == 1)
        #expect(b.surfaces[0].agent == .shell)
        #expect(b.surfaces[0].state == .idle)
    }
}

// MARK: - Git ancestor resolver

@Suite("GitAncestorWorkspaceRootResolver — ancestor walk")
struct GitAncestorWorkspaceRootResolverTests {

    private func makeTempRepo() throws -> (root: URL, subdir: URL, cleanup: () -> Void) {
        let uuid = UUID().uuidString
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-aurora-\(uuid)", isDirectory: true)
        let subdir = root.appendingPathComponent("src/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        return (root, subdir, {
            try? FileManager.default.removeItem(at: root)
        })
    }

    @Test
    func findsAncestorWithDotGit() throws {
        let repo = try makeTempRepo()
        defer { repo.cleanup() }

        let resolver = GitAncestorWorkspaceRootResolver(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        let root = resolver.workspaceRoot(for: repo.subdir)
        #expect(root?.standardizedFileURL == repo.root.standardizedFileURL)
    }

    @Test
    func returnsNilWhenNoDotGitInAnyAncestor() throws {
        let orphan = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-aurora-noroot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: orphan) }

        // Force the resolver to stop at a home directory we know does not
        // contain `.git` by using the orphan itself as the boundary.
        let resolver = GitAncestorWorkspaceRootResolver(
            homeDirectory: orphan.deletingLastPathComponent()
        )
        let root = resolver.workspaceRoot(for: orphan)
        #expect(root == nil)
    }

    @Test
    func respectsDepthBudget() throws {
        let repo = try makeTempRepo()
        defer { repo.cleanup() }

        // maxDepth = 1 cannot find the .git two levels up.
        let resolver = GitAncestorWorkspaceRootResolver(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            maxDepth: 1
        )
        let root = resolver.workspaceRoot(for: repo.subdir)
        #expect(root == nil)
    }

    @Test
    func stopsAtHomeBoundaryEvenIfHomeHasDotGit() throws {
        // Regression guard for the promised home-boundary behavior.
        // Layout: a dotfiles repo at `$HOME` (so `$HOME/.git` exists),
        // plus a tab rooted inside `$HOME/projects/demo` that itself
        // has no `.git` directory. Without the boundary check, the
        // ancestor walk would hit `$HOME/.git` and collapse every
        // local tab into one synthetic "home" workspace — the doc
        // comment explicitly forbids that.
        let uuid = UUID().uuidString
        let fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-aurora-fakehome-\(uuid)", isDirectory: true)
        let workDir = fakeHome.appendingPathComponent("projects/demo", isDirectory: true)
        let dotfilesGit = fakeHome.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dotfilesGit, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fakeHome) }

        let resolver = GitAncestorWorkspaceRootResolver(homeDirectory: fakeHome)
        let root = resolver.workspaceRoot(for: workDir)
        #expect(root == nil,
                "Resolver must stop at the $HOME boundary before probing `.git`")
    }

    @Test
    func queryingHomeDirectoryItselfDoesNotReturnIt() throws {
        // A tab whose working directory IS `$HOME` must not resolve
        // to `$HOME` as a workspace root either — this is the edge
        // case where the boundary is checked on the first iteration.
        let uuid = UUID().uuidString
        let fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-aurora-home-as-cwd-\(uuid)", isDirectory: true)
        let dotfilesGit = fakeHome.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: dotfilesGit, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fakeHome) }

        let resolver = GitAncestorWorkspaceRootResolver(homeDirectory: fakeHome)
        #expect(resolver.workspaceRoot(for: fakeHome) == nil)
    }
}
