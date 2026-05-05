// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SkillRegistrySwiftTestingTests.swift - Local skill registry foundation.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("SkillRegistry")
struct SkillRegistrySwiftTestingTests {
    private static let expectedBuiltInSkillIDs = [
        "debug-systematic",
        "dependency-audit",
        "document",
        "fix-error",
        "git-blame-explain",
        "performance-profile",
        "refactor-extract",
        "release-checklist",
        "review-pr",
        "security-review",
        "triage-issue",
        "write-tests",
    ]

    @Test("loader parses front matter metadata and markdown body")
    func loaderParsesFrontMatterMetadataAndMarkdownBody() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let skillDirectory = root.appendingPathComponent("review-pr", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try """
        ---
        id: review-pr
        name: Review PR
        description: Review a local pull request diff.
        ---
        # Review PR

        Inspect the diff and report risks first.
        """.write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let loadedSkill = try SkillLoader().loadSkill(from: skillDirectory, source: .user)
        let skill = try #require(loadedSkill)

        #expect(skill.id == "review-pr")
        #expect(skill.name == "Review PR")
        #expect(skill.summary == "Review a local pull request diff.")
        #expect(skill.body.contains("Inspect the diff"))
        #expect(skill.source == .user)
    }

    @Test("registry merges built-in, user, and project skills with project precedence")
    func registryMergesSkillsWithProjectPrecedence() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let builtIns = root.appendingPathComponent("built-in", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try writeSkill(id: "write-tests", name: "Write Tests", summary: "Built-in test writer", in: builtIns)
        try writeSkill(id: "write-tests", name: "Project Test Writer", summary: "Project override", in: project)
        try writeSkill(id: "debug-systematic", name: "Debug Systematic", summary: "User debugger", in: user)
        try writeInvalidSkillDirectory(named: "../bad", in: user)

        let registry = SkillRegistry(
            directories: [
                SkillDirectory(url: builtIns, source: .builtIn),
                SkillDirectory(url: user, source: .user),
                SkillDirectory(url: project, source: .project),
            ]
        )
        let skills = try registry.loadSkills()

        #expect(skills.map(\.id) == ["debug-systematic", "write-tests"])
        let writeTests = try #require(skills.first { $0.id == "write-tests" })
        #expect(writeTests.name == "Project Test Writer")
        #expect(writeTests.source == .project)
    }

    @Test("registry accepts a root directory that directly contains SKILL.md")
    func registryAcceptsRootDirectoryThatDirectlyContainsSkillFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        ---
        id: direct-skill
        name: Direct Skill
        description: Loaded from the root directory.
        ---
        # Direct Skill

        Use the current workspace.
        """.write(to: root.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let registry = SkillRegistry(directories: [SkillDirectory(url: root, source: .project)])
        let skills = try registry.loadSkills()

        #expect(skills.map(\.id) == ["direct-skill"])
        #expect(skills.first?.source == .project)
    }

    @Test("loader rejects invalid front matter")
    func loaderRejectsInvalidFrontMatter() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let skillDirectory = root.appendingPathComponent("bad-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try "# Bad Skill\n\nMissing metadata fence.\n".write(
            to: skillDirectory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        #expect(throws: SkillError.invalidFrontMatter(skillDirectory.appendingPathComponent("SKILL.md"))) {
            _ = try SkillLoader().loadSkill(from: skillDirectory, source: .user)
        }
    }

    @Test("loader rejects unsafe identifiers")
    func loaderRejectsUnsafeIdentifiers() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let skillDirectory = root.appendingPathComponent("bad-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try """
        ---
        id: ../escape
        name: Bad Skill
        description: Should fail.
        ---
        Bad body.
        """.write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        #expect(throws: SkillError.invalidIdentifier("../escape")) {
            _ = try SkillLoader().loadSkill(from: skillDirectory, source: .user)
        }
    }

    @Test("invoker produces deterministic instructions for selected local skills")
    func invokerProducesDeterministicInstructionsForSelectedSkills() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSkill(
            id: "document",
            name: "Document",
            summary: "Write docs from code evidence",
            body: "Use code references and keep wording concrete.",
            in: root
        )
        try writeSkill(
            id: "refactor-extract",
            name: "Refactor Extract",
            summary: "Extract focused helpers",
            body: "Keep behavior unchanged and verify callers.",
            in: root
        )

        let registry = SkillRegistry(directories: [SkillDirectory(url: root, source: .builtIn)])
        let invocation = try SkillInvoker(registry: registry).makeInvocation(skillIDs: [
            "refactor-extract",
            "document",
        ])

        #expect(invocation.skillIDs == ["document", "refactor-extract"])
        #expect(invocation.instructions.contains("## Document"))
        #expect(invocation.instructions.contains("Use code references"))
        #expect(invocation.instructions.contains("## Refactor Extract"))
        #expect(invocation.instructions.contains("Keep behavior unchanged"))
    }

    @Test("invoker deduplicates and normalizes selected skill IDs")
    func invokerDeduplicatesAndNormalizesSelectedSkillIDs() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSkill(id: "write-tests", name: "Write Tests", summary: "Add tests", in: root)

        let registry = SkillRegistry(directories: [SkillDirectory(url: root, source: .builtIn)])
        let invocation = try SkillInvoker(registry: registry).makeInvocation(skillIDs: [
            "WRITE-TESTS",
            "write-tests",
        ])

        #expect(invocation.skillIDs == ["write-tests"])
    }

    @Test("invoker reports missing selected skills")
    func invokerReportsMissingSelectedSkills() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = SkillRegistry(directories: [SkillDirectory(url: root, source: .builtIn)])

        #expect(throws: SkillError.missingSkill("missing-skill")) {
            _ = try SkillInvoker(registry: registry).makeInvocation(skillIDs: ["missing-skill"])
        }
    }

    @Test("list snapshot preserves sorted skill metadata")
    func listSnapshotPreservesSortedSkillMetadata() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSkill(id: "write-tests", name: "Write Tests", summary: "Add tests", in: root)
        try writeSkill(id: "review-pr", name: "Review PR", summary: "Review a diff", in: root)

        let skills = try SkillRegistry(
            directories: [SkillDirectory(url: root, source: .builtIn)]
        ).loadSkills()
        let snapshot = SkillListSnapshot(skills: skills)

        #expect(snapshot.count == 2)
        #expect(snapshot.skills.map(\.id) == ["review-pr", "write-tests"])
        #expect(snapshot.skills.first?.source == "built-in")
    }

    @Test("marketplace installs local skill into user registry")
    func marketplaceInstallsLocalSkillIntoUserRegistry() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        let installRoot = root.appendingPathComponent("installed", isDirectory: true)
        try writeSkill(
            id: "local-review",
            name: "Local Review",
            summary: "Local marketplace skill",
            body: "Review only local evidence.",
            in: sourceRoot
        )

        let receipt = try SkillMarketplaceInstaller(
            skillsDirectory: installRoot
        ).install(from: sourceRoot.appendingPathComponent("local-review", isDirectory: true))

        #expect(receipt.skillID == "local-review")
        #expect(receipt.skill.source == .user)
        #expect(FileManager.default.fileExists(
            atPath: installRoot.appendingPathComponent("local-review/SKILL.md").path
        ))

        let installed = try SkillRegistry(
            directories: [SkillDirectory(url: installRoot, source: .user)]
        ).skillMap()["local-review"]
        #expect(installed?.summary == "Local marketplace skill")
    }

    @Test("marketplace requires replace when installed skill already exists")
    func marketplaceRequiresReplaceWhenInstalledSkillAlreadyExists() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        let installRoot = root.appendingPathComponent("installed", isDirectory: true)
        try writeSkill(id: "local-review", name: "Local Review", summary: "Initial", in: sourceRoot)

        let installer = SkillMarketplaceInstaller(skillsDirectory: installRoot)
        _ = try installer.install(from: sourceRoot.appendingPathComponent("local-review", isDirectory: true))

        #expect(throws: SkillMarketplaceError.skillAlreadyInstalled("local-review")) {
            _ = try installer.install(from: sourceRoot.appendingPathComponent("local-review", isDirectory: true))
        }
    }

    @Test("marketplace rejects local sources without skill files")
    func marketplaceRejectsLocalSourcesWithoutSkillFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let emptySource = root.appendingPathComponent("empty-source", isDirectory: true)
        try FileManager.default.createDirectory(at: emptySource, withIntermediateDirectories: true)

        #expect(throws: SkillMarketplaceError.missingSkillFile(emptySource.path)) {
            _ = try SkillMarketplaceInstaller(
                skillsDirectory: root.appendingPathComponent("installed", isDirectory: true)
            ).install(from: emptySource)
        }
    }

    @Test("marketplace source store deduplicates URLs and rejects unsupported schemes")
    func marketplaceSourceStoreDeduplicatesURLsAndRejectsUnsupportedSchemes() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SkillSourceStore(fileURL: root.appendingPathComponent("sources.json"))
        let sourceURL = try #require(URL(string: "https://example.com/skills/local-review.git"))

        try store.add(SkillMarketplaceSource(url: sourceURL, displayName: "Local Review"))
        try store.add(SkillMarketplaceSource(url: sourceURL, displayName: "Updated Local Review"))

        let sources = try store.load()
        #expect(sources.count == 1)
        #expect(sources.first?.displayName == "Updated Local Review")
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(throws: SkillMarketplaceError.invalidSourceScheme("ftp")) {
            try store.add(SkillMarketplaceSource(
                url: #require(URL(string: "ftp://example.com/skills.git"))
            ))
        }
    }

    @Test("all bundled skills parse with canonical metadata")
    func allBundledSkillsParseWithCanonicalMetadata() throws {
        let root = repositoryRoot()
        let skillsRoot = root.appendingPathComponent("Resources/Skills", isDirectory: true)
        let skills = try SkillRegistry(
            directories: [SkillDirectory(url: skillsRoot, source: .builtIn)]
        ).loadSkills()

        #expect(skills.map(\.id) == Self.expectedBuiltInSkillIDs)
        for skill in skills {
            #expect(!skill.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!skill.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!skill.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(skill.fileURL.lastPathComponent == "SKILL.md")
            #expect(skill.source == .builtIn)
        }
    }

    @Test("app bundle scripts copy and verify bundled skills")
    func appBundleScriptsCopyAndVerifyBundledSkills() throws {
        let root = repositoryRoot()
        let buildScript = try String(
            contentsOf: root.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )
        let verifyScript = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-app-bundle.sh"),
            encoding: .utf8
        )
        let skillsRoot = root.appendingPathComponent("Resources/Skills", isDirectory: true)

        #expect(buildScript.contains("Resources/Skills"))
        #expect(verifyScript.contains("[Skills]"))
        #expect(verifyScript.contains("$RESOURCES/Skills"))
        for skillID in Self.expectedBuiltInSkillIDs {
            #expect(FileManager.default.fileExists(
                atPath: skillsRoot
                    .appendingPathComponent(skillID, isDirectory: true)
                    .appendingPathComponent("SKILL.md")
                    .path
            ))
            #expect(verifyScript.contains("Skills/\(skillID)/SKILL.md"))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-skills-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeSkill(
        id: String,
        name: String,
        summary: String,
        body: String = "Follow the local codebase evidence.",
        in root: URL
    ) throws {
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        ---
        id: \(id)
        name: \(name)
        description: \(summary)
        ---
        # \(name)

        \(body)
        """.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    private func writeInvalidSkillDirectory(named name: String, in root: URL) throws {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        ---
        id: invalid/path
        name: Bad Skill
        description: Should be ignored.
        ---
        Bad body.
        """.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
