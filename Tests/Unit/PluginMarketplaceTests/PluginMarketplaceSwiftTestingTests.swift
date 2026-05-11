// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginMarketplaceSwiftTestingTests.swift - Decentralized plugin marketplace coverage.

import Foundation
import Testing
import CocxyCommandSignatures
@testable import CocxyTerminal

@Suite("Plugin marketplace")
struct PluginMarketplaceSwiftTestingTests {

    private func temporaryDirectory(_ name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-plugin-marketplace-tests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("source store persists decentralized plugin sources")
    func sourceStorePersistsDecentralizedSources() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let storeURL = root.appendingPathComponent("sources.json")
        let store = PluginSourceStore(fileURL: storeURL)
        let sourceURL = try #require(URL(string: "https://github.com/example/cocxy-docker-helper.git"))

        try store.add(
            PluginSource(
                url: sourceURL,
                displayName: "Docker helpers"
            )
        )

        let reloaded = try PluginSourceStore(fileURL: storeURL).load()

        #expect(reloaded.count == 1)
        #expect(reloaded[0].url == sourceURL)
        #expect(reloaded[0].displayName == "Docker helpers")
    }

    @Test("source URL resolver accepts HTTPS, SSH shorthand, and local paths")
    func sourceURLResolverAcceptsSupportedForms() throws {
        #expect(PluginSourceURLResolver.resolve("https://github.com/example/plugin.git")?.scheme == "https")

        let sshURL = try #require(PluginSourceURLResolver.resolve("git@github.com:example/plugin.git"))
        #expect(sshURL.scheme == "ssh")
        #expect(sshURL.host == "github.com")
        #expect(sshURL.path == "/example/plugin.git")

        let fileURL = try #require(PluginSourceURLResolver.resolve("~/plugin"))
        #expect(fileURL.isFileURL)
    }

    @Test("marketplace manifest parses capabilities and optional signature")
    func manifestParsesMarketplaceFields() throws {
        let manifest = try PluginManifestParser.parse(
            content: """
            name = "Docker Helper"
            description = "Adds local Docker shortcuts"
            version = "1.2.3"
            author = "Cocxy"
            repository = "https://github.com/example/cocxy-docker-helper.git"
            license = "MIT"
            events = ["session-start", "command-complete"]
            capabilities = ["filesystem-read", "process-spawn"]
            """,
            directoryPath: "/tmp/cocxy-docker-helper",
            manifestFileName: PluginManifest.marketplaceManifestFileName
        )

        #expect(manifest.id == "cocxy-docker-helper")
        #expect(manifest.manifestFileName == PluginManifest.marketplaceManifestFileName)
        #expect(manifest.repositoryURL == "https://github.com/example/cocxy-docker-helper.git")
        #expect(manifest.capabilities == [.filesystemRead, .processSpawn])
        #expect(manifest.signature == nil)
    }

    @Test("validator allows unsigned plugins but reports unsigned status")
    func validatorAllowsUnsignedPlugin() throws {
        let manifest = PluginManifest(
            id: "unsigned-helper",
            name: "Unsigned Helper",
            description: "Local helper",
            version: "0.1.0",
            author: "Dev",
            minCocxyVersion: nil,
            events: [],
            directoryPath: "/tmp/unsigned-helper",
            manifestFileName: PluginManifest.marketplaceManifestFileName,
            capabilities: [.filesystemRead]
        )
        let sourceURL = try #require(URL(string: "https://github.com/example/unsigned-helper.git"))

        let report = try PluginValidator().validate(
            manifest: manifest,
            sourceURL: sourceURL,
            pluginDirectory: URL(fileURLWithPath: manifest.directoryPath)
        )

        #expect(report.isInstallable)
        #expect(report.signatureStatus == .unsignedAllowed)
        #expect(report.warnings.contains(.unsignedPlugin))
    }

    @Test("validator verifies signed plugin manifests with trusted authors")
    func validatorVerifiesSignedPluginManifestsWithTrustedAuthors() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginDirectory = root.appendingPathComponent("signed-helper", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)

        let unsignedManifest = """
        name = "Signed Helper"
        version = "1.0.0"
        author = "Cocxy"
        capabilities = ["environment-read"]
        """
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        let artifact = try SignatureSigner().sign(
            payload: Data((unsignedManifest + "\n").utf8),
            author: "Cocxy",
            keyPair: keyPair,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try (unsignedManifest + """

        signature = "\(artifact.signature)"
        signature-algorithm = "\(artifact.algorithm.rawValue)"
        signature-key-id = "\(artifact.keyID)"
        signature-author = "\(artifact.author)"
        signature-timestamp = "\(ISO8601DateFormatter.cocxySignature.string(from: artifact.timestamp))"
        signature-payload-sha256 = "\(artifact.payloadSHA256)"
        """).write(
            to: pluginDirectory.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        let manifest = try PluginRegistry.loadManifest(from: pluginDirectory)
        var registry = TrustedAuthorRegistry()
        try registry.trust(displayName: "Cocxy", publicKey: keyPair.publicKey)

        let report = try PluginValidator(trustedAuthors: registry).validate(
            manifest: manifest,
            sourceURL: pluginDirectory,
            pluginDirectory: pluginDirectory
        )

        #expect(report.isInstallable)
        #expect(report.signatureStatus == .verified)
        #expect(report.warnings.isEmpty)
    }

    @Test("validator blocks signed plugin manifests that fail verification")
    func validatorBlocksSignedPluginManifestsThatFailVerification() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginDirectory = root.appendingPathComponent("tampered-helper", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)

        let unsignedManifest = """
        name = "Tampered Helper"
        version = "1.0.0"
        author = "Cocxy"
        """
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        let artifact = try SignatureSigner().sign(
            payload: Data((unsignedManifest + "\n").utf8),
            author: "Cocxy",
            keyPair: keyPair,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try """
        name = "Tampered Helper"
        version = "2.0.0"
        author = "Cocxy"
        signature = "\(artifact.signature)"
        signature-algorithm = "\(artifact.algorithm.rawValue)"
        signature-key-id = "\(artifact.keyID)"
        signature-author = "\(artifact.author)"
        signature-timestamp = "\(ISO8601DateFormatter.cocxySignature.string(from: artifact.timestamp))"
        signature-payload-sha256 = "\(artifact.payloadSHA256)"
        """.write(
            to: pluginDirectory.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        let manifest = try PluginRegistry.loadManifest(from: pluginDirectory)
        var registry = TrustedAuthorRegistry()
        try registry.trust(displayName: "Cocxy", publicKey: keyPair.publicKey)

        let report = try PluginValidator(trustedAuthors: registry).validate(
            manifest: manifest,
            sourceURL: pluginDirectory,
            pluginDirectory: pluginDirectory
        )

        #expect(!report.isInstallable)
        #expect(report.signatureStatus == .invalid)
        #expect(report.warnings.contains(.invalidSignature))
    }

    @Test("installer refuses plugins with invalid signatures")
    func installerRefusesPluginsWithInvalidSignatures() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("signed-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        let unsignedManifest = """
        name = "Signed Plugin"
        version = "1.0.0"
        author = "Cocxy"
        """
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        let artifact = try SignatureSigner().sign(
            payload: Data((unsignedManifest + "\n").utf8),
            author: "Cocxy",
            keyPair: keyPair,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try """
        name = "Signed Plugin"
        version = "9.9.9"
        author = "Cocxy"
        signature = "\(artifact.signature)"
        signature-algorithm = "\(artifact.algorithm.rawValue)"
        signature-key-id = "\(artifact.keyID)"
        signature-author = "\(artifact.author)"
        signature-timestamp = "\(ISO8601DateFormatter.cocxySignature.string(from: artifact.timestamp))"
        signature-payload-sha256 = "\(artifact.payloadSHA256)"
        """.write(
            to: repo.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        var registry = TrustedAuthorRegistry()
        try registry.trust(displayName: "Cocxy", publicKey: keyPair.publicKey)
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let installer = PluginInstaller(
            pluginsDirectory: pluginsDirectory,
            validator: PluginValidator(trustedAuthors: registry)
        )

        #expect(throws: PluginInstallerError.invalidSignature("signed-plugin")) {
            _ = try installer.install(from: repo)
        }
        #expect(!FileManager.default.fileExists(
            atPath: pluginsDirectory.appendingPathComponent("signed-plugin").path
        ))
    }

    @Test("installer stages local repo and installed plugin loads next scan")
    @MainActor
    func installerRegistersPluginForNextScan() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try """
        name = "Starter Plugin"
        version = "1.0.0"
        author = "Dev"
        events = ["session-start"]
        capabilities = ["environment-read"]
        """.write(
            to: repo.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo ok\n".write(
            to: repo.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )

        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let installer = PluginInstaller(pluginsDirectory: pluginsDirectory)

        let receipt = try installer.install(from: repo)

        #expect(receipt.pluginID == "repo")
        #expect(receipt.signatureStatus == .unsignedAllowed)
        #expect(FileManager.default.fileExists(
            atPath: pluginsDirectory
                .appendingPathComponent("repo", isDirectory: true)
                .appendingPathComponent(PluginManifest.marketplaceManifestFileName)
                .path
        ))

        let manager = PluginManager(pluginsDirectory: pluginsDirectory.path)
        manager.scanPlugins()

        #expect(manager.plugins.count == 1)
        #expect(manager.plugins[0].id == "repo")
        #expect(manager.plugins[0].manifest.capabilities == [.environmentRead])
    }

    @Test("installed plugin can be enabled dispatched and uninstalled")
    @MainActor
    func installedPluginCanBeEnabledDispatchedAndUninstalled() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("run-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try """
        name = "Run Plugin"
        version = "1.0.0"
        author = "Dev"
        events = ["session-start"]
        capabilities = ["environment-read"]
        """.write(
            to: repo.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo run\n".write(
            to: repo.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )

        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let installer = PluginInstaller(pluginsDirectory: pluginsDirectory)
        let receipt = try installer.install(from: repo)

        let sandbox = RecordingPluginSandbox()
        let manager = PluginManager(
            pluginsDirectory: pluginsDirectory.path,
            sandbox: sandbox
        )
        manager.scanPlugins()
        try manager.enablePlugin(id: receipt.pluginID)

        manager.dispatchEvent(.sessionStart, environment: ["COCXY_SESSION_ID": "session-1"])

        #expect(sandbox.executions.count == 1)
        #expect(sandbox.executions[0].pluginID == "run-plugin")
        #expect(sandbox.executions[0].scriptPath.hasSuffix("/run-plugin/on-session-start.sh"))
        #expect(sandbox.executions[0].environment["COCXY_SESSION_ID"] == "session-1")
        #expect(sandbox.executions[0].capabilities == [.environmentRead])
        #expect(manager.plugin(id: "run-plugin")?.lastTriggeredAt != nil)

        try installer.uninstall(id: "run-plugin")
        manager.scanPlugins()

        #expect(manager.plugin(id: "run-plugin") == nil)
    }

    @Test("plugin dispatch merges persisted sandbox grants with manifest capabilities")
    @MainActor
    func pluginDispatchMergesPersistedSandboxGrants() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("granted-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try """
        name = "Granted Plugin"
        version = "1.0.0"
        author = "Dev"
        events = ["session-start"]
        capabilities = ["environment-read"]
        """.write(
            to: repo.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo granted\n".write(
            to: repo.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )

        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let installer = PluginInstaller(pluginsDirectory: pluginsDirectory)
        let receipt = try installer.install(from: repo)

        let sandbox = RecordingPluginSandbox()
        let manager = PluginManager(
            pluginsDirectory: pluginsDirectory.path,
            sandbox: sandbox,
            grantedCapabilitiesProvider: { pluginID in
                pluginID == "granted-plugin" ? [.networkClient] : []
            }
        )
        manager.scanPlugins()
        try manager.enablePlugin(id: receipt.pluginID)

        manager.dispatchEvent(.sessionStart)

        #expect(sandbox.executions.count == 1)
        #expect(sandbox.executions[0].capabilities == [.environmentRead, .networkClient])
    }

    @Test("rich input submit plugin event dispatches through sandbox")
    @MainActor
    func richInputSubmitPluginEventDispatchesThroughSandbox() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("rich-input-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try """
        name = "Rich Input Plugin"
        version = "1.0.0"
        author = "Dev"
        events = ["rich-input-submit"]
        capabilities = ["environment-read"]
        """.write(
            to: repo.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo rich-input\n".write(
            to: repo.appendingPathComponent("on-rich-input-submit.sh"),
            atomically: true,
            encoding: .utf8
        )

        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let installer = PluginInstaller(pluginsDirectory: pluginsDirectory)
        let receipt = try installer.install(from: repo)

        let sandbox = RecordingPluginSandbox()
        let manager = PluginManager(
            pluginsDirectory: pluginsDirectory.path,
            sandbox: sandbox
        )
        manager.scanPlugins()
        try manager.enablePlugin(id: receipt.pluginID)

        manager.dispatchEvent(.richInputSubmit, environment: [
            "COCXY_RICH_INPUT_TEXT": "local prompt",
            "COCXY_RICH_INPUT_ATTACHMENT_COUNT": "1",
        ])

        #expect(sandbox.executions.count == 1)
        #expect(sandbox.executions[0].pluginID == "rich-input-plugin")
        #expect(sandbox.executions[0].scriptPath.hasSuffix("/rich-input-plugin/on-rich-input-submit.sh"))
        #expect(sandbox.executions[0].environment["COCXY_RICH_INPUT_TEXT"] == "local prompt")
        #expect(sandbox.executions[0].environment["COCXY_RICH_INPUT_ATTACHMENT_COUNT"] == "1")
    }

    @Test("uninstall removes persisted enabled state")
    func uninstallRemovesPersistedEnabledState() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("stateful-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try """
        name = "Stateful Plugin"
        version = "1.0.0"
        author = "Dev"
        events = ["session-start"]
        """.write(
            to: repo.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )

        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let installer = PluginInstaller(pluginsDirectory: pluginsDirectory)
        _ = try installer.install(from: repo)

        let stateURL = pluginsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("plugins.json")
        let enabledData = try JSONEncoder().encode(["stateful-plugin"])
        try enabledData.write(to: stateURL)

        try installer.uninstall(id: "stateful-plugin")

        let updatedData = try Data(contentsOf: stateURL)
        let updatedIDs = try JSONDecoder().decode([String].self, from: updatedData)

        #expect(updatedIDs.isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: pluginsDirectory
                .appendingPathComponent("stateful-plugin", isDirectory: true)
                .path
        ))
    }

    @Test("bundled plugin catalog loads manifests")
    func bundledPluginCatalogLoadsManifests() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundled = root.appendingPathComponent("Plugins", isDirectory: true)
        let plugin = bundled.appendingPathComponent("cocxy-sample", isDirectory: true)
        try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
        try """
        name = "Bundled Sample"
        version = "1.0.0"
        author = "Cocxy"
        capabilities = ["environment-read"]
        """.write(
            to: plugin.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )

        let manifests = try BundledPluginCatalog(pluginsDirectory: bundled).loadManifests()

        #expect(manifests.count == 1)
        #expect(manifests[0].id == "cocxy-sample")
        #expect(manifests[0].capabilities == [.environmentRead])
    }

    @Test("bundled plugin catalog includes DB and cloud helper set")
    func bundledPluginCatalogIncludesDBAndCloudHelperSet() throws {
        let pluginsRoot = repositoryRoot()
            .appendingPathComponent("Resources/Plugins", isDirectory: true)
        let manifests = try BundledPluginCatalog(pluginsDirectory: pluginsRoot).loadManifests()
        let manifestsByID = Dictionary(uniqueKeysWithValues: manifests.map { ($0.id, $0) })
        let expectedIDs: Set<String> = [
            "cocxy-aws-cli-helper",
            "cocxy-azure-cli",
            "cocxy-cloudflare",
            "cocxy-db-mysql",
            "cocxy-db-postgres",
            "cocxy-db-redis",
            "cocxy-db-sqlite",
            "cocxy-docker-helper",
            "cocxy-gcp-cli",
            "cocxy-kubernetes",
        ]

        #expect(Set(manifestsByID.keys).isSuperset(of: expectedIDs))
        for id in expectedIDs {
            let manifest = try #require(manifestsByID[id])
            #expect(manifest.repositoryURL?.hasPrefix("bundled://") == true)
            #expect(manifest.capabilities.contains(.processSpawn))
        }
        #expect(manifestsByID["cocxy-db-sqlite"]?.capabilities.contains(.filesystemRead) == true)
    }

    @Test("plugin updater reports newer semver tags")
    func pluginUpdaterReportsNewerSemverTags() {
        let manifest = PluginManifest(
            id: "tagged-plugin",
            name: "Tagged Plugin",
            description: "Tagged plugin",
            version: "1.1.0",
            author: "Dev",
            minCocxyVersion: nil,
            events: [],
            directoryPath: "/tmp/tagged-plugin"
        )
        let updater = PluginUpdater { _, arguments in
            if arguments.first == "tag" {
                return "v1.2.0\nv1.1.0\n"
            }
            return ""
        }

        let updates = updater.availableUpdates(for: [manifest])

        #expect(updates.count == 1)
        #expect(updates[0].pluginID == "tagged-plugin")
        #expect(updates[0].latestVersion == "1.2.0")
    }

    @Test("plugin updater ignores same or older tags")
    func pluginUpdaterIgnoresSameOrOlderTags() {
        let manifest = PluginManifest(
            id: "current-plugin",
            name: "Current Plugin",
            description: "Current plugin",
            version: "2.0.0",
            author: "Dev",
            minCocxyVersion: nil,
            events: [],
            directoryPath: "/tmp/current-plugin"
        )
        let updater = PluginUpdater { _, arguments in
            if arguments.first == "tag" {
                return "v2.0.0\nv1.9.0\n"
            }
            return ""
        }

        #expect(updater.availableUpdates(for: [manifest]).isEmpty)
    }

    @Test("sandbox rejects scripts outside plugin directory")
    func sandboxRejectsScriptOutsidePluginDirectory() throws {
        let sandbox = PluginSandbox()

        #expect(throws: PluginSandboxError.self) {
            _ = try sandbox.makeExecutionPlan(
                scriptPath: "/tmp/other/on-session-start.sh",
                environment: ["COCXY_EVENT": "session-start"],
                pluginID: "safe-plugin",
                pluginDirectory: "/tmp/safe-plugin",
                capabilities: []
            )
        }
    }

    @Test("sandbox builds sanitized execution plan for plugin script")
    func sandboxBuildsSanitizedExecutionPlan() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let pluginDirectory = root.appendingPathComponent("safe-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: pluginDirectory.appendingPathComponent("state", isDirectory: true),
            withIntermediateDirectories: true
        )
        let scriptURL = pluginDirectory.appendingPathComponent("on-session-start.sh")
        try "#!/bin/sh\nexit 0\n".write(to: scriptURL, atomically: true, encoding: .utf8)

        let longValue = String(repeating: "x", count: 9_000)
        let sandbox = PluginSandbox(
            sandboxExecutor: SandboxExecutor(
                sandboxExecURL: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
                fileManager: StubPluginSandboxFileManager(executablePaths: ["/usr/bin/sandbox-exec"])
            )
        )
        let plan = try sandbox.makeExecutionPlan(
            scriptPath: scriptURL.path,
            environment: [
                "COCXY_EVENT": "session-start",
                "LONG_VALUE": longValue,
            ],
            pluginID: "safe-plugin",
            pluginDirectory: pluginDirectory.path,
            capabilities: [.networkClient, .filesystemRead, .filesystemWrite]
        )

        let resolvedScriptPath = scriptURL.resolvingSymlinksInPath().standardizedFileURL.path
        let profile = try #require(plan.kernelSandboxProfile)
        #expect(plan.executableURL.path == "/usr/bin/sandbox-exec")
        #expect(Array(plan.arguments.prefix(3)) == ["-p", profile, "/bin/sh"])
        #expect(plan.arguments.dropFirst(3).first == resolvedScriptPath)
        #expect(plan.currentDirectoryURL.path == pluginDirectory.resolvingSymlinksInPath().standardizedFileURL.path)
        #expect(plan.environment["COCXY_EVENT"] == "session-start")
        #expect(plan.environment["COCXY_PLUGIN_ID"] == "safe-plugin")
        #expect(plan.environment["COCXY_SCRIPT_PATH"] == resolvedScriptPath)
        #expect(plan.environment["COCXY_PLUGIN_CAPABILITIES"] == "filesystem-read,filesystem-write,network-client")
        #expect(plan.environment["COCXY_PLUGIN_SANDBOX_MODE"] == "kernel")
        #expect(plan.environment["PATH"] == "/usr/local/bin:/usr/bin:/bin")
        #expect(plan.environment["HOME"] == NSHomeDirectory())
        #expect(plan.environment["LONG_VALUE"]?.count == 8_192)
        #expect(profile.contains("(deny default)"))
        #expect(profile.contains("(allow network-outbound)"))
        #expect(profile.contains(#"(allow file-read* "#))
        #expect(profile.contains(#"(subpath "\#(pluginDirectory.resolvingSymlinksInPath().standardizedFileURL.path)")"#))
        #expect(profile.contains(#"(allow file-write* "#))
        #expect(profile.contains(#"(subpath "\#(pluginDirectory.appendingPathComponent("state", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL.path)")"#))
        #expect(profile.contains(#"(literal "/bin/sh")"#))
        #expect(profile.contains(#"(literal "/bin/bash")"#))
    }

    @Test("sandbox falls back explicitly when sandbox-exec is unavailable")
    func sandboxFallsBackWhenSandboxExecUnavailable() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let pluginDirectory = root.appendingPathComponent("safe-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        let scriptURL = pluginDirectory.appendingPathComponent("on-session-start.sh")
        try "#!/bin/sh\nexit 0\n".write(to: scriptURL, atomically: true, encoding: .utf8)

        let sandbox = PluginSandbox(
            sandboxExecutor: SandboxExecutor(
                sandboxExecURL: URL(fileURLWithPath: "/missing/sandbox-exec"),
                fileManager: StubPluginSandboxFileManager(executablePaths: [])
            )
        )
        let plan = try sandbox.makeExecutionPlan(
            scriptPath: scriptURL.path,
            environment: ["COCXY_EVENT": "session-start"],
            pluginID: "safe-plugin",
            pluginDirectory: pluginDirectory.path,
            capabilities: [.environmentRead]
        )

        #expect(plan.executableURL.path == "/bin/sh")
        #expect(plan.arguments == [scriptURL.resolvingSymlinksInPath().standardizedFileURL.path])
        #expect(plan.kernelSandboxProfile == nil)
        #expect(plan.environment["COCXY_PLUGIN_SANDBOX_MODE"] == "legacy-unavailable")
    }

    @Test("sandbox profile keeps plugin writes scoped to state directory")
    func sandboxProfileKeepsPluginWritesScopedToStateDirectory() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let pluginDirectory = root.appendingPathComponent("safe-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        let scriptURL = pluginDirectory.appendingPathComponent("on-session-start.sh")
        try "#!/bin/sh\nexit 0\n".write(to: scriptURL, atomically: true, encoding: .utf8)

        let sandbox = PluginSandbox(
            sandboxExecutor: SandboxExecutor(
                sandboxExecURL: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
                fileManager: StubPluginSandboxFileManager(executablePaths: ["/usr/bin/sandbox-exec"])
            )
        )
        let noWritePlan = try sandbox.makeExecutionPlan(
            scriptPath: scriptURL.path,
            environment: ["COCXY_EVENT": "session-start"],
            pluginID: "safe-plugin",
            pluginDirectory: pluginDirectory.path,
            capabilities: [.environmentRead]
        )
        let writePlan = try sandbox.makeExecutionPlan(
            scriptPath: scriptURL.path,
            environment: ["COCXY_EVENT": "session-start"],
            pluginID: "safe-plugin",
            pluginDirectory: pluginDirectory.path,
            capabilities: [.filesystemWrite]
        )

        #expect(noWritePlan.kernelSandboxProfile?.contains("file-write*") == false)
        #expect(noWritePlan.kernelSandboxProfile?.contains("network-outbound") == false)
        #expect(writePlan.kernelSandboxProfile?.contains("file-write*") == true)
        #expect(writePlan.kernelSandboxProfile?.contains("/state") == true)
        let parentPath = root
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        #expect(writePlan.kernelSandboxProfile?.contains(#"(subpath "\#(parentPath)")"#) == false)
    }

    @Test("kernel sandbox denies plugin writes outside granted state directory")
    func kernelSandboxDeniesPluginWritesOutsideGrantedStateDirectory() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else {
            return
        }

        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("cocxy-plugin-sandbox-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginDirectory = root.appendingPathComponent("safe-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: pluginDirectory.appendingPathComponent("state", isDirectory: true),
            withIntermediateDirectories: true
        )
        let touchURL = URL(fileURLWithPath: "/usr/bin/touch")
        guard FileManager.default.isExecutableFile(atPath: touchURL.path) else {
            return
        }
        let allowedURL = pluginDirectory.appendingPathComponent("state/allowed.txt")
        let outsideURL = root.appendingPathComponent("outside.txt")

        let profile = SandboxProfileBuilder().profile(
            capabilities: [.filesystemRead, .filesystemWrite, .processExec],
            readablePaths: [pluginDirectory],
            writablePaths: [pluginDirectory.appendingPathComponent("state", isDirectory: true)],
            executablePaths: [touchURL],
            readableLiteralPaths: SandboxProfileBuilder.parentDirectoryLiterals(for: pluginDirectory),
            includeSystemReadBaseline: true
        )
        let plan = try SandboxExecutor().launchPlan(
            commandURL: touchURL,
            arguments: [allowedURL.path, outsideURL.path],
            profile: profile,
            environment: [:],
            currentDirectoryURL: pluginDirectory
        )
        let process = Process()
        process.executableURL = plan.executableURL
        process.arguments = plan.arguments
        process.environment = plan.environment
        process.currentDirectoryURL = plan.currentDirectoryURL
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus != 0)
        #expect(FileManager.default.fileExists(atPath: allowedURL.path))
        #expect(!FileManager.default.fileExists(atPath: outsideURL.path))
    }

    @Test("sandbox rejects unsafe environment keys before launch")
    func sandboxRejectsUnsafeEnvironmentKeysBeforeLaunch() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let pluginDirectory = root.appendingPathComponent("safe-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        let scriptURL = pluginDirectory.appendingPathComponent("on-session-start.sh")
        try "#!/bin/sh\nexit 0\n".write(to: scriptURL, atomically: true, encoding: .utf8)

        #expect(throws: PluginSandboxError.self) {
            _ = try PluginSandbox().makeExecutionPlan(
                scriptPath: scriptURL.path,
                environment: ["lowercase": "blocked"],
                pluginID: "safe-plugin",
                pluginDirectory: pluginDirectory.path,
                capabilities: []
            )
        }
    }

    @Test("sandbox executes plugin script with sanitized environment")
    func sandboxExecutesPluginScriptWithSanitizedEnvironment() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let pluginDirectory = root.appendingPathComponent("safe-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        let markerURL = root.appendingPathComponent("marker.txt")
        let scriptURL = pluginDirectory.appendingPathComponent("on-session-start.sh")
        try """
        #!/bin/sh
        printf "%s|%s|%s|%s" "$COCXY_PLUGIN_ID" "$COCXY_EVENT" "$COCXY_PLUGIN_CAPABILITIES" "$(pwd)" > "$MARKER_PATH"
        """.write(to: scriptURL, atomically: true, encoding: .utf8)

        PluginSandbox(timeoutSeconds: 2, kernelSandboxEnabled: false).execute(
            scriptPath: scriptURL.path,
            environment: [
                "COCXY_EVENT": "session-start",
                "MARKER_PATH": markerURL.path,
            ],
            pluginID: "safe-plugin",
            pluginDirectory: pluginDirectory.path,
            capabilities: [.environmentRead]
        )

        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: markerURL.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        let marker = try String(contentsOf: markerURL, encoding: .utf8)
        let expectedDirectory = pluginDirectory.path
        let privateVarDirectory = "/private" + expectedDirectory
        #expect([
            "safe-plugin|session-start|environment-read|\(expectedDirectory)",
            "safe-plugin|session-start|environment-read|\(privateVarDirectory)",
        ].contains(marker))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class RecordingPluginSandbox: PluginSandboxing, @unchecked Sendable {
    struct Execution: Equatable {
        let scriptPath: String
        let environment: [String: String]
        let pluginID: String
        let pluginDirectory: String
        let capabilities: Set<PluginCapability>
    }

    private(set) var executions: [Execution] = []

    func execute(
        scriptPath: String,
        environment: [String: String],
        pluginID: String,
        pluginDirectory: String,
        capabilities: Set<PluginCapability>
    ) {
        executions.append(Execution(
            scriptPath: scriptPath,
            environment: environment,
            pluginID: pluginID,
            pluginDirectory: pluginDirectory,
            capabilities: capabilities
        ))
    }
}

private final class StubPluginSandboxFileManager: SandboxFileManaging {
    private let executablePaths: Set<String>

    init(executablePaths: Set<String>) {
        self.executablePaths = executablePaths
    }

    func isExecutableFile(atPath path: String) -> Bool {
        executablePaths.contains(path)
    }
}
