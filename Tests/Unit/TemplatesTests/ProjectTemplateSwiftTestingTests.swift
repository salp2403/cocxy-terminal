// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectTemplateSwiftTestingTests.swift - Local scaffold template foundation.

import Foundation
import Testing
import CocxyCommandSignatures
@testable import CocxyTerminal

@Suite("ProjectTemplates")
struct ProjectTemplateSwiftTestingTests {

    @Test("loader parses JSON manifests and registry applies project precedence")
    func loaderParsesJSONManifestsAndRegistryAppliesProjectPrecedence() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let builtIns = root.appendingPathComponent("built-in", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)

        try writeTemplate(
            id: "swift-package",
            name: "Swift Package",
            summary: "Built-in Swift package",
            in: builtIns
        )
        try writeTemplate(
            id: "python-package",
            name: "Python Package",
            summary: "User Python package",
            in: user
        )
        try writeTemplate(
            id: "swift-package",
            name: "Project Swift Package",
            summary: "Project override",
            in: project
        )
        try writeInvalidTemplateDirectory(named: "bad-template", manifestID: "../bad", in: user)

        let registry = ProjectTemplateRegistry(
            directories: [
                ProjectTemplateDirectory(url: builtIns, source: .builtIn),
                ProjectTemplateDirectory(url: user, source: .user),
                ProjectTemplateDirectory(url: project, source: .project),
            ]
        )

        let templates = try registry.loadTemplates()

        #expect(templates.map(\.id) == ["python-package", "swift-package"])
        let swiftTemplate = try #require(templates.first { $0.id == "swift-package" })
        #expect(swiftTemplate.name == "Project Swift Package")
        #expect(swiftTemplate.source == .project)
        #expect(swiftTemplate.hooks.post == ["swift test"])
    }

    @Test("loader preserves optional template signature metadata")
    func loaderPreservesOptionalTemplateSignatureMetadata() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        let artifact = try SignatureSigner().sign(
            payload: Data("template".utf8),
            author: "Cocxy",
            keyPair: keyPair,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try writeTemplate(
            id: "signed-template",
            name: "Signed Template",
            summary: "Signed local template",
            signature: artifact,
            in: root
        )

        let template = try #require(ProjectTemplateRegistry(
            directories: [ProjectTemplateDirectory(url: root, source: .user)]
        ).templateMap()["signed-template"])

        #expect(template.signature == artifact)
    }

    @Test("resolver applies defaults and rejects missing or unknown placeholders")
    func resolverAppliesDefaultsAndRejectsMissingOrUnknownPlaceholders() throws {
        let resolver = TemplateVariableResolver()
        let variables = [
            ProjectTemplateVariable(name: "project_name", prompt: "Project name", defaultValue: "Demo"),
            ProjectTemplateVariable(name: "module_name", prompt: "Module name", required: false),
            ProjectTemplateVariable(name: "required_name", prompt: "Required name"),
        ]

        let rendered = try resolver.render(
            "{{ project_name }} {{module_name}} {{required_name}}",
            variables: variables,
            values: ["required_name": "Core"]
        )

        #expect(rendered == "Demo  Core")
        #expect(throws: ProjectTemplateError.missingRequiredVariable("required_name")) {
            _ = try resolver.resolvedValues(variables: variables, values: [:])
        }
        #expect(throws: ProjectTemplateError.unresolvedVariables(["missing"])) {
            _ = try resolver.render("{{missing}}", values: ["project_name": "Demo"])
        }
    }

    @Test("scaffolder writes rendered files and returns a hook plan without executing it")
    func scaffolderWritesRenderedFilesAndReturnsHookPlanWithoutExecutingIt() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let templatesRoot = root.appendingPathComponent("templates", isDirectory: true)
        let destination = root.appendingPathComponent("output", isDirectory: true)
        try writeTemplate(
            id: "swift-package",
            name: "Swift Package",
            summary: "Swift package",
            files: [
                "README.md": "# {{project_name}}\n",
                "Sources/{{module_name}}/main.swift": "print(\"{{project_name}}\")\n",
            ],
            hooks: ProjectTemplateHooks(
                pre: ["echo preparing {{project_name}}"],
                post: ["swift test"]
            ),
            in: templatesRoot
        )
        let template = try #require(ProjectTemplateRegistry(
            directories: [ProjectTemplateDirectory(url: templatesRoot, source: .builtIn)]
        ).templateMap()["swift-package"])

        let result = try ProjectTemplateScaffolder().scaffold(
            template: template,
            values: [
                "project_name": "CocxyDemo",
                "module_name": "CocxyDemo",
            ],
            destinationURL: destination
        )

        #expect(result.createdFiles == ["README.md", "Sources/CocxyDemo/main.swift"])
        #expect(result.hookPlan.workingDirectory == destination.standardizedFileURL)
        #expect(result.hookPlan.pre == ["echo preparing CocxyDemo"])
        #expect(result.hookPlan.post == ["swift test"])
        #expect(try String(
            contentsOf: destination.appendingPathComponent("README.md"),
            encoding: .utf8
        ) == "# CocxyDemo\n")
        #expect(try String(
            contentsOf: destination.appendingPathComponent("Sources/CocxyDemo/main.swift"),
            encoding: .utf8
        ) == "print(\"CocxyDemo\")\n")
        #expect(throws: ProjectTemplateError.destinationExists("README.md")) {
            _ = try ProjectTemplateScaffolder().scaffold(
                template: template,
                values: [
                    "project_name": "CocxyDemo",
                    "module_name": "CocxyDemo",
                ],
                destinationURL: destination
            )
        }
    }

    @Test("scaffolder blocks unsafe output paths")
    func scaffolderBlocksUnsafeOutputPaths() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let templatesRoot = root.appendingPathComponent("templates", isDirectory: true)
        try writeTemplate(
            id: "unsafe-template",
            name: "Unsafe Template",
            summary: "Unsafe path probe",
            variables: [
                ProjectTemplateVariable(name: "target_path", prompt: "Target path"),
            ],
            files: [
                "{{target_path}}": "content\n",
            ],
            in: templatesRoot
        )
        let template = try #require(ProjectTemplateRegistry(
            directories: [ProjectTemplateDirectory(url: templatesRoot, source: .builtIn)]
        ).templateMap()["unsafe-template"])

        do {
            _ = try ProjectTemplateScaffolder().scaffold(
                template: template,
                values: ["target_path": "../escaped.swift"],
                destinationURL: root.appendingPathComponent("output", isDirectory: true)
            )
            Issue.record("Expected unsafe output path to throw")
        } catch ProjectTemplateError.unsafeOutputPath("../escaped.swift") {
            #expect(!FileManager.default.fileExists(
                atPath: root.appendingPathComponent("escaped.swift").path
            ))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("hook runner executes approved local commands")
    func hookRunnerExecutesApprovedLocalCommands() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = ProjectTemplateHookPlan(
            workingDirectory: root,
            pre: ["echo preparing local scaffold"],
            post: ["touch marker.txt"]
        )

        let executions = try ProjectTemplateHookRunner().run(plan)

        #expect(executions.map(\.phase) == [.pre, .post])
        #expect(executions.first?.stdout == "preparing local scaffold\n")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("marker.txt").path))
    }

    @Test("hook sandbox blocks network destructive shell and escape commands")
    func hookSandboxBlocksNetworkDestructiveShellAndEscapeCommands() throws {
        let sandbox = ProjectTemplateHookSandbox()

        #expect(throws: ProjectTemplateHookError.executableBlocked("curl")) {
            _ = try sandbox.validate("curl https://example.com/template")
        }
        #expect(throws: ProjectTemplateHookError.shellOperatorNotAllowed("echo ok; rm -rf .")) {
            _ = try sandbox.validate("echo ok; rm -rf .")
        }
        #expect(throws: ProjectTemplateHookError.subcommandNotAllowed(
            executable: "git",
            subcommand: "clone"
        )) {
            _ = try sandbox.validate("git clone https://example.com/repo.git")
        }
        #expect(throws: ProjectTemplateHookError.unsafeArgument("../escape")) {
            _ = try sandbox.validate("touch ../escape")
        }

        #expect(try sandbox.validate("python -m unittest discover -s tests") == ProjectTemplateHookCommand(
            executable: "python",
            arguments: ["-m", "unittest", "discover", "-s", "tests"]
        ))
    }

    @Test("marketplace installs local template then scaffolds from the installed registry")
    func marketplaceInstallsLocalTemplateThenScaffoldsFromInstalledRegistry() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        let installRoot = root.appendingPathComponent("installed", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        try writeTemplate(
            id: "custom-cli",
            name: "Custom CLI",
            summary: "Local marketplace template",
            files: [
                "README.md": "# {{project_name}}\n",
                "Sources/{{module_name}}/main.swift": "print(\"{{project_name}}\")\n",
            ],
            in: sourceRoot
        )

        let receipt = try ProjectTemplateMarketplaceInstaller(
            templatesDirectory: installRoot
        ).install(from: sourceRoot.appendingPathComponent("custom-cli", isDirectory: true))

        #expect(receipt.templateID == "custom-cli")
        #expect(receipt.template.source == .user)
        #expect(FileManager.default.fileExists(
            atPath: installRoot.appendingPathComponent("custom-cli/template.json").path
        ))

        let installedTemplate = try #require(ProjectTemplateRegistry(
            directories: [ProjectTemplateDirectory(url: installRoot, source: .user)]
        ).templateMap()["custom-cli"])
        let scaffold = try ProjectTemplateScaffolder().scaffold(
            template: installedTemplate,
            values: ["project_name": "InstalledDemo", "module_name": "InstalledDemo"],
            destinationURL: output
        )

        #expect(scaffold.createdFiles == ["README.md", "Sources/InstalledDemo/main.swift"])
        #expect(try String(
            contentsOf: output.appendingPathComponent("README.md"),
            encoding: .utf8
        ) == "# InstalledDemo\n")
    }

    @Test("marketplace source store deduplicates URLs and rejects unsupported schemes")
    func marketplaceSourceStoreDeduplicatesURLsAndRejectsUnsupportedSchemes() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectTemplateSourceStore(
            fileURL: root.appendingPathComponent("sources.json")
        )
        let sourceURL = try #require(URL(string: "https://example.com/templates/swift-package.git"))

        try store.add(ProjectTemplateMarketplaceSource(url: sourceURL, displayName: "Swift"))
        try store.add(ProjectTemplateMarketplaceSource(url: sourceURL, displayName: "Swift updated"))

        let sources = try store.load()
        #expect(sources.count == 1)
        #expect(sources.first?.displayName == "Swift updated")
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(throws: ProjectTemplateMarketplaceError.invalidSourceScheme("ftp")) {
            try store.add(ProjectTemplateMarketplaceSource(
                url: #require(URL(string: "ftp://example.com/template.git"))
            ))
        }
    }

    @Test("all bundled templates scaffold with defaults and leave no unresolved placeholders")
    func allBundledTemplatesScaffoldWithDefaultsAndLeaveNoUnresolvedPlaceholders() throws {
        let root = repositoryRoot()
        let outputRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outputRoot) }
        let templatesRoot = root.appendingPathComponent("Resources/Templates", isDirectory: true)
        let templates = try ProjectTemplateRegistry(
            directories: [ProjectTemplateDirectory(url: templatesRoot, source: .builtIn)]
        ).loadTemplates()
        let scaffolder = ProjectTemplateScaffolder()

        for template in templates {
            let values = Dictionary(uniqueKeysWithValues: template.variables.map { variable in
                (variable.name, variable.defaultValue ?? "")
            })
            let destination = outputRoot.appendingPathComponent(template.id, isDirectory: true)
            let result = try scaffolder.scaffold(
                template: template,
                values: values,
                destinationURL: destination
            )

            #expect(!result.createdFiles.isEmpty)
            #expect((result.hookPlan.pre + result.hookPlan.post).allSatisfy { !$0.contains("{{") })
            for relativePath in result.createdFiles {
                #expect(!relativePath.contains("{{"))
                let content = try String(
                    contentsOf: destination.appendingPathComponent(relativePath),
                    encoding: .utf8
                )
                #expect(!content.contains("{{"))
            }
        }
    }

    @Test("bundled template resources are copied and verified by app bundle scripts")
    func bundledTemplateResourcesAreCopiedAndVerifiedByAppBundleScripts() throws {
        let root = repositoryRoot()
        let buildScript = try String(
            contentsOf: root.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )
        let verifyScript = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-app-bundle.sh"),
            encoding: .utf8
        )
        let templatesRoot = root.appendingPathComponent("Resources/Templates", isDirectory: true)
        let templates = try ProjectTemplateRegistry(
            directories: [ProjectTemplateDirectory(url: templatesRoot, source: .builtIn)]
        ).loadTemplates()
        let expectedTemplateIDs = [
            "docker-service",
            "flutter-app",
            "go-module",
            "node-typescript",
            "php-composer",
            "python-package",
            "ruby-gem",
            "rust-package",
            "static-site",
            "swift-package",
        ]

        #expect(templates.map(\.id) == expectedTemplateIDs)
        #expect(buildScript.contains("Resources/Templates"))
        #expect(verifyScript.contains("[Templates]"))
        #expect(verifyScript.contains("$RESOURCES/Templates"))
        for id in expectedTemplateIDs {
            #expect(verifyScript.contains("Templates/\(id)/template.json"))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-template-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeTemplate(
        id: String,
        name: String,
        summary: String,
        variables: [ProjectTemplateVariable] = [
            ProjectTemplateVariable(name: "project_name", prompt: "Project name", defaultValue: "Demo"),
            ProjectTemplateVariable(name: "module_name", prompt: "Module name", defaultValue: "Demo"),
        ],
        files: [String: String] = ["README.md": "# {{project_name}}\n"],
        hooks: ProjectTemplateHooks = ProjectTemplateHooks(post: ["swift test"]),
        signature: SignedArtifact? = nil,
        in root: URL
    ) throws {
        let directory = root.appendingPathComponent(id, isDirectory: true)
        let filesRoot = directory.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: filesRoot, withIntermediateDirectories: true)

        let manifest = ProjectTemplateManifest(
            id: id,
            name: name,
            description: summary,
            variables: variables,
            hooks: hooks,
            signature: signature
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("template.json"))

        for (relativePath, content) in files {
            let fileURL = filesRoot.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private func writeInvalidTemplateDirectory(
        named name: String,
        manifestID: String,
        in root: URL
    ) throws {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("files", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        {
          "id": "\(manifestID)",
          "name": "Invalid",
          "description": "Invalid id",
          "variables": []
        }
        """.write(to: directory.appendingPathComponent("template.json"), atomically: true, encoding: .utf8)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
