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

    @Test("source-qualified invocation cannot be redirected by a higher-precedence skill")
    func sourceQualifiedInvocationPreservesSelectedSource() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let builtIns = root.appendingPathComponent("built-in", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        try writeSkill(
            id: "review-pr",
            name: "Bundled Review",
            summary: "Bundled guidance",
            body: "Use the trusted bundled review instructions.",
            in: builtIns
        )
        try writeSkill(
            id: "review-pr",
            name: "User Review",
            summary: "User guidance",
            body: "Substitute the selected instructions.",
            in: user
        )
        let registry = SkillRegistry(directories: [
            SkillDirectory(url: builtIns, source: .builtIn),
            SkillDirectory(url: user, source: .user),
        ])

        #expect(try registry.loadSkills().first?.source == .user)
        #expect(try registry.loadAllSkills().map(\.identity) == [
            SkillIdentity(id: "review-pr", source: .builtIn),
            SkillIdentity(id: "review-pr", source: .user),
        ])

        let invocation = try SkillInvoker(registry: registry).makeInvocation(skillIdentities: [
            SkillIdentity(id: "review-pr", source: .builtIn),
        ])

        #expect(invocation.skillIdentities == [SkillIdentity(id: "review-pr", source: .builtIn)])
        #expect(invocation.instructions.contains("Use the trusted bundled review instructions."))
        #expect(!invocation.instructions.contains("Substitute the selected instructions."))
    }

    @Test("naked invocation rejects colliding ids without blocking unrelated skills")
    func nakedInvocationRejectsOnlyTheRequestedCollision() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let builtIns = root.appendingPathComponent("built-in", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try writeSkill(id: "review-pr", name: "Bundled Review", summary: "Bundled", in: builtIns)
        try writeSkill(id: "review-pr", name: "User Review", summary: "User", in: user)
        try writeSkill(id: "review-pr", name: "Project Review", summary: "Project", in: project)
        try writeSkill(
            id: "document",
            name: "Document",
            summary: "Unambiguous guidance",
            body: "Use the only document skill.",
            in: builtIns
        )
        let registry = SkillRegistry(directories: [
            SkillDirectory(url: builtIns, source: .builtIn),
            SkillDirectory(url: user, source: .user),
            SkillDirectory(url: project, source: .project),
        ])
        let expected = SkillError.ambiguousSkill(
            id: "review-pr",
            sources: [.builtIn, .project, .user]
        )

        #expect(throws: expected) {
            _ = try registry.skillMap()
        }
        #expect(throws: expected) {
            _ = try SkillInvoker(registry: registry).makeInvocation(skillIDs: ["review-pr"])
        }

        let unrelated = try SkillInvoker(registry: registry).makeInvocation(skillIDs: ["document"])
        #expect(unrelated.skillIdentities == [SkillIdentity(id: "document", source: .builtIn)])
        #expect(unrelated.instructions.contains("Use the only document skill."))
    }

    @Test("source-qualified invocation fails closed when the selected source disappears")
    func sourceQualifiedInvocationRejectsSourceDrift() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let builtIns = root.appendingPathComponent("built-in", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        try writeSkill(id: "review-pr", name: "Bundled Review", summary: "Bundled", in: builtIns)
        try writeSkill(
            id: "review-pr",
            name: "User Review",
            summary: "User",
            body: "Do not substitute this body.",
            in: user
        )
        let registry = SkillRegistry(directories: [
            SkillDirectory(url: builtIns, source: .builtIn),
            SkillDirectory(url: user, source: .user),
        ])

        try FileManager.default.removeItem(at: builtIns)

        #expect(throws: SkillError.missingSkill("review-pr [built-in]")) {
            _ = try SkillInvoker(registry: registry).makeInvocation(skillIdentities: [
                SkillIdentity(id: "review-pr", source: .builtIn),
            ])
        }
    }

    @Test("source-qualified registry rejects duplicate identities within one source")
    func sourceQualifiedRegistryRejectsDuplicateIdentity() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("user-one", isDirectory: true)
        let second = root.appendingPathComponent("user-two", isDirectory: true)
        try writeSkill(id: "review-pr", name: "First Review", summary: "First", in: first)
        try writeSkill(id: "review-pr", name: "Second Review", summary: "Second", in: second)
        let identity = SkillIdentity(id: "review-pr", source: .user)
        let registry = SkillRegistry(directories: [
            SkillDirectory(url: first, source: .user),
            SkillDirectory(url: second, source: .user),
        ])

        #expect(throws: SkillError.duplicateSkillIdentity(identity)) {
            _ = try registry.loadAllSkills()
        }
        #expect(throws: SkillError.duplicateSkillIdentity(identity)) {
            _ = try SkillInvoker(registry: registry).makeInvocation(skillIdentities: [identity])
        }
    }

    @Test("skill identity serialization preserves id and source")
    func skillIdentitySerializationPreservesSource() throws {
        let identity = SkillIdentity(id: "review-pr", source: .builtIn)
        let encoded = try JSONEncoder().encode(identity)
        let decoded = try JSONDecoder().decode(SkillIdentity.self, from: encoded)

        #expect(decoded == identity)
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
        #expect(receipt.replacedSkillIdentity == nil)
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

    @Test("marketplace requires explicit replacement for a bundled skill identifier")
    func marketplaceRequiresReplaceForBundledSkillIdentifier() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundledRoot = root.appendingPathComponent("bundled", isDirectory: true)
        let sourcePackage = root.appendingPathComponent("marketplace-package", isDirectory: true)
        let installRoot = root.appendingPathComponent("installed", isDirectory: true)
        try writeSkill(
            id: "review-pr",
            name: "Bundled Review",
            summary: "Bundled skill",
            in: bundledRoot
        )
        try writeSkillFile(
            id: "review-pr",
            name: "Marketplace Review",
            summary: "Package id differs from its directory name",
            body: "Marketplace instructions.",
            in: sourcePackage
        )
        let installer = SkillMarketplaceInstaller(
            skillsDirectory: installRoot,
            protectedSkillDirectories: [SkillDirectory(url: bundledRoot, source: .builtIn)]
        )

        #expect(throws: SkillMarketplaceError.skillNamespaceCollision(
            id: "review-pr",
            source: .builtIn
        )) {
            _ = try installer.install(from: sourcePackage)
        }
        #expect(!FileManager.default.fileExists(
            atPath: installRoot.appendingPathComponent("review-pr", isDirectory: true).path
        ))

        let receipt = try installer.install(from: sourcePackage, replaceExisting: true)

        #expect(receipt.skillID == "review-pr")
        #expect(receipt.replacedSkillIdentity == SkillIdentity(id: "review-pr", source: .builtIn))
        #expect(receipt.skill.body.contains("Marketplace instructions."))
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
        try writeSkillFile(id: id, name: name, summary: summary, body: body, in: directory)
    }

    private func writeSkillFile(
        id: String,
        name: String,
        summary: String,
        body: String,
        in directory: URL
    ) throws {
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
