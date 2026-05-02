// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SkillRegistrySwiftTestingTests.swift - Local skill registry foundation.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("SkillRegistry")
struct SkillRegistrySwiftTestingTests {

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
}
