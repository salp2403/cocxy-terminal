// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginMarketplaceSwiftTestingTests.swift - Decentralized plugin marketplace coverage.

import Darwin
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

    private func installExecutableScript(at url: URL, contents: String) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
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
        _ = try writeSignedPluginManifest(
            unsignedManifest,
            to: pluginDirectory,
            keyPair: keyPair,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
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
        let artifact = try writeSignedPluginManifest(
            unsignedManifest,
            to: pluginDirectory,
            keyPair: keyPair,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try signedManifestContent("""
        name = "Tampered Helper"
        version = "2.0.0"
        author = "Cocxy"
        """, artifact: artifact).write(
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
        let artifact = try writeSignedPluginManifest(
            unsignedManifest,
            to: repo,
            keyPair: keyPair,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try signedManifestContent("""
        name = "Signed Plugin"
        version = "9.9.9"
        author = "Cocxy"
        """, artifact: artifact).write(
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

    @Test("validator rejects a signed plugin after an event script changes")
    func validatorRejectsTamperedEventScript() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginDirectory = root.appendingPathComponent("script-signed", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        let scriptURL = pluginDirectory.appendingPathComponent("on-session-start.sh")
        try "echo trusted\n".write(to: scriptURL, atomically: true, encoding: .utf8)
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        _ = try writeSignedPluginManifest(
            """
            name = "Script Signed"
            version = "1.0.0"
            author = "Cocxy"
            events = ["session-start"]
            """,
            to: pluginDirectory,
            keyPair: keyPair,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        var registry = TrustedAuthorRegistry()
        try registry.trust(displayName: "Cocxy", publicKey: keyPair.publicKey)
        let validator = PluginValidator(trustedAuthors: registry)
        let manifest = try PluginRegistry.loadManifest(from: pluginDirectory)

        #expect(try validator.validate(
            manifest: manifest,
            sourceURL: pluginDirectory,
            pluginDirectory: pluginDirectory
        ).signatureStatus == .verified)

        try "echo substituted\n".write(to: scriptURL, atomically: true, encoding: .utf8)
        let tampered = try validator.validate(
            manifest: manifest,
            sourceURL: pluginDirectory,
            pluginDirectory: pluginDirectory
        )
        #expect(tampered.signatureStatus == .invalid)
        #expect(!tampered.isInstallable)
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
        let sourceGitDirectory = repo.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceGitDirectory,
            withIntermediateDirectories: true
        )
        try "[core]\nsshCommand = /tmp/untrusted-command\n".write(
            to: sourceGitDirectory.appendingPathComponent("config"),
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
        #expect(!FileManager.default.fileExists(
            atPath: pluginsDirectory
                .appendingPathComponent("repo/.git", isDirectory: true)
                .path
        ))
        #expect(try PluginUpdateSourceStore(pluginsDirectory: pluginsDirectory).source(for: "repo") == nil)

        let manager = PluginManager(pluginsDirectory: pluginsDirectory.path)
        manager.scanPlugins()

        #expect(manager.plugins.count == 1)
        #expect(manager.plugins[0].id == "repo")
        #expect(manager.plugins[0].manifest.capabilities == [.environmentRead])
    }

    @Test("installation receipt binds the exact installed tree")
    func installationReceiptBindsExactInstalledTree() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("tree-bound-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try "name = \"Tree Bound\"\nversion = \"1.0.0\"\n".write(
            to: repo.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo trusted\n".write(
            to: repo.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )
        let sidecarURL = repo.appendingPathComponent(".cocxy-signature.json")
        try "{\"metadata\":\"original\"}\n".write(
            to: sidecarURL,
            atomically: true,
            encoding: .utf8
        )

        let receipt = try PluginInstaller(
            pluginsDirectory: root.appendingPathComponent("plugins", isDirectory: true)
        ).install(from: repo)
        let installedDigest = try PluginInstalledTreeDigest.sha256(
            at: receipt.installedURL,
            manifestFileName: receipt.manifest.manifestFileName
        )

        #expect(receipt.packageTreeSHA256 == installedDigest)

        try "{\"metadata\":\"changed\"}\n".write(
            to: receipt.installedURL.appendingPathComponent(".cocxy-signature.json"),
            atomically: true,
            encoding: .utf8
        )
        #expect(try PluginInstalledTreeDigest.sha256(
            at: receipt.installedURL,
            manifestFileName: receipt.manifest.manifestFileName
        ) != receipt.packageTreeSHA256)
    }

    @Test("installer rejects legacy manifests from marketplace sources")
    func installerRejectsLegacyMarketplaceManifest() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("legacy-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try "name = \"Legacy Plugin\"\n".write(
            to: repo.appendingPathComponent(PluginManifest.legacyManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)

        #expect(throws: PluginInstallerError.legacyManifestRequiresMigration("legacy-plugin")) {
            _ = try PluginInstaller(pluginsDirectory: pluginsDirectory).install(from: repo)
        }
        #expect(!FileManager.default.fileExists(
            atPath: pluginsDirectory.appendingPathComponent("legacy-plugin").path
        ))
    }

    @Test("replacement clears enabled state and capability grants before installing new code")
    func replacementClearsPriorAuthority() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let grantStore = PluginCapabilityGrantStore(
            backend: MemoryPluginCapabilityGrantBackingStore()
        )
        let installer = PluginInstaller(
            pluginsDirectory: pluginsDirectory,
            capabilityGrantStore: grantStore
        )

        let original = root.appendingPathComponent("original-source", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        try "id = \"shared-plugin\"\nname = \"Original\"\n".write(
            to: original.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo original\n".write(
            to: original.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )
        _ = try installer.install(from: original)

        let stateURL = root.appendingPathComponent("plugins.json")
        try JSONEncoder().encode(["shared-plugin"]).write(to: stateURL, options: [.atomic])
        try grantStore.grant(.networkClient, for: "shared-plugin", reason: "Approved original")
        let resetRecorder = PluginAuthorizationResetSnapshotRecorder(
            pluginID: "shared-plugin",
            pluginsDirectory: pluginsDirectory,
            stateURL: stateURL,
            grantStore: grantStore
        )
        let resetObserver = NotificationCenter.default.addObserver(
            forName: .cocxyPluginAuthorizationDidReset,
            object: nil,
            queue: nil,
            using: resetRecorder.record
        )
        defer { NotificationCenter.default.removeObserver(resetObserver) }

        let replacement = root.appendingPathComponent("replacement-source", isDirectory: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        try "id = \"shared-plugin\"\nname = \"Replacement\"\n".write(
            to: replacement.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo replacement\n".write(
            to: replacement.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )

        _ = try installer.install(from: replacement, replaceExisting: true)

        let enabled = try JSONDecoder().decode([String].self, from: Data(contentsOf: stateURL))
        #expect(enabled.isEmpty)
        #expect(try grantStore.grants(for: "shared-plugin").isEmpty)
        #expect(resetRecorder.notificationCount == 1)
        #expect(resetRecorder.wasEnabledAtNotification == false)
        #expect(resetRecorder.hadGrantsAtNotification == false)
        let installedScript = try String(
            contentsOf: pluginsDirectory
                .appendingPathComponent("shared-plugin")
                .appendingPathComponent("on-session-start.sh"),
            encoding: .utf8
        )
        #expect(installedScript == "echo replacement\n")
    }

    @Test("unreadable update metadata aborts replacement before authority changes")
    func unreadableUpdateMetadataFailsWithoutMutation() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let grantStore = PluginCapabilityGrantStore(
            backend: MemoryPluginCapabilityGrantBackingStore()
        )
        let installer = PluginInstaller(
            pluginsDirectory: pluginsDirectory,
            capabilityGrantStore: grantStore
        )

        let original = root.appendingPathComponent("metadata-original", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        try "id = \"metadata-plugin\"\nname = \"Original\"\n".write(
            to: original.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo original\n".write(
            to: original.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )
        _ = try installer.install(from: original)

        let stateURL = root.appendingPathComponent("plugins.json")
        try JSONEncoder().encode(["metadata-plugin"]).write(to: stateURL, options: [.atomic])
        try grantStore.grant(.networkClient, for: "metadata-plugin", reason: "Original grant")
        let sourceDirectory = pluginsDirectory.appendingPathComponent(
            ".update-sources",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        try "not-json\n".write(
            to: sourceDirectory.appendingPathComponent("metadata-plugin.json"),
            atomically: true,
            encoding: .utf8
        )

        let replacement = root.appendingPathComponent("metadata-replacement", isDirectory: true)
        try FileManager.default.createDirectory(
            at: replacement,
            withIntermediateDirectories: true
        )
        try "id = \"metadata-plugin\"\nname = \"Replacement\"\n".write(
            to: replacement.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo replacement\n".write(
            to: replacement.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )

        #expect(throws: DecodingError.self) {
            _ = try installer.install(from: replacement, replaceExisting: true)
        }

        let installedScript = try String(
            contentsOf: pluginsDirectory
                .appendingPathComponent("metadata-plugin", isDirectory: true)
                .appendingPathComponent("on-session-start.sh"),
            encoding: .utf8
        )
        #expect(installedScript == "echo original\n")
        #expect(
            try JSONDecoder().decode([String].self, from: Data(contentsOf: stateURL))
                == ["metadata-plugin"]
        )
        #expect(try grantStore.isGranted(.networkClient, for: "metadata-plugin"))
    }

    @Test("replacement mutation is rejected and atomically restores the prior plugin")
    func replacementMutationRollsBackPriorPlugin() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)

        let original = root.appendingPathComponent("original-race-source", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        try "id = \"race-plugin\"\nname = \"Original\"\n".write(
            to: original.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo original\n".write(
            to: original.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )
        _ = try PluginInstaller(pluginsDirectory: pluginsDirectory).install(from: original)

        let replacement = root.appendingPathComponent("replacement-race-source", isDirectory: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        try "id = \"race-plugin\"\nname = \"Replacement\"\n".write(
            to: replacement.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo validated\n".write(
            to: replacement.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )
        let racingInstaller = PluginInstaller(
            pluginsDirectory: pluginsDirectory,
            prePromotionAction: { stagedPlugin in
                try "echo changed-after-validation\n".write(
                    to: stagedPlugin.appendingPathComponent("on-session-start.sh"),
                    atomically: true,
                    encoding: .utf8
                )
            }
        )

        #expect(throws: PluginInstallerError.packageChangedDuringInstall("race-plugin")) {
            _ = try racingInstaller.install(from: replacement, replaceExisting: true)
        }
        let installedScript = try String(
            contentsOf: pluginsDirectory
                .appendingPathComponent("race-plugin", isDirectory: true)
                .appendingPathComponent("on-session-start.sh"),
            encoding: .utf8
        )
        #expect(installedScript == "echo original\n")
    }

    @Test("new installation mutation is rejected without publishing a plugin")
    func newInstallationMutationRemovesPublishedPlugin() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let source = root.appendingPathComponent("new-race-source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "id = \"new-race-plugin\"\nname = \"New Race\"\n".write(
            to: source.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo validated\n".write(
            to: source.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )
        let racingInstaller = PluginInstaller(
            pluginsDirectory: pluginsDirectory,
            prePromotionAction: { stagedPlugin in
                try "echo changed-after-validation\n".write(
                    to: stagedPlugin.appendingPathComponent("on-session-start.sh"),
                    atomically: true,
                    encoding: .utf8
                )
            }
        )

        #expect(throws: PluginInstallerError.packageChangedDuringInstall("new-race-plugin")) {
            _ = try racingInstaller.install(from: source)
        }
        #expect(!FileManager.default.fileExists(
            atPath: pluginsDirectory.appendingPathComponent("new-race-plugin").path
        ))
    }

    @Test("live plugin manager observes replacement reset through a symlink alias")
    @MainActor
    func livePluginManagerDropsReplacementEnablement() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let installer = PluginInstaller(pluginsDirectory: pluginsDirectory)

        let original = root.appendingPathComponent("live-original", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        try "id = \"live-plugin\"\nname = \"Original\"\nevents = [\"session-start\"]\n".write(
            to: original.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo original\n".write(
            to: original.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )
        _ = try installer.install(from: original)

        let pluginsAlias = root.appendingPathComponent("plugins-alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: pluginsAlias,
            withDestinationURL: pluginsDirectory
        )
        #expect(
            PluginRegistrySynchronization.canonicalDirectoryURL(pluginsAlias)
                == PluginRegistrySynchronization.canonicalDirectoryURL(pluginsDirectory)
        )

        let sandbox = RecordingPluginSandbox()
        let manager = PluginManager(
            pluginsDirectory: pluginsAlias.path,
            sandbox: sandbox
        )
        manager.scanPlugins()
        try manager.enablePlugin(id: "live-plugin")
        #expect(manager.plugins.first?.isEnabled == true)

        let replacement = root.appendingPathComponent("live-replacement", isDirectory: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        try "id = \"live-plugin\"\nname = \"Replacement\"\nevents = [\"session-start\"]\n".write(
            to: replacement.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo replacement\n".write(
            to: replacement.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )

        _ = try installer.install(from: replacement, replaceExisting: true)
        #expect(manager.plugins.first?.isEnabled == false)

        manager.dispatchEvent(.sessionStart)

        #expect(manager.enabledPlugins.isEmpty)
        #expect(sandbox.executions.isEmpty)
    }

    @Test("queued event cannot execute code from a re-enabled replacement generation")
    @MainActor
    func queuedEventRejectsReenabledReplacementGeneration() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let installer = PluginInstaller(pluginsDirectory: pluginsDirectory)

        let original = root.appendingPathComponent("queued-original", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        try "id = \"queued-plugin\"\nname = \"Original\"\nevents = [\"session-start\"]\n".write(
            to: original.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo original\n".write(
            to: original.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )
        _ = try installer.install(from: original)

        let sandbox = DeferredPluginSandbox()
        let manager = PluginManager(
            pluginsDirectory: pluginsDirectory.path,
            sandbox: sandbox
        )
        manager.scanPlugins()
        try manager.enablePlugin(id: "queued-plugin")
        manager.dispatchEvent(.sessionStart)
        #expect(sandbox.pendingCount == 1)

        let replacement = root.appendingPathComponent("queued-replacement", isDirectory: true)
        try FileManager.default.createDirectory(
            at: replacement,
            withIntermediateDirectories: true
        )
        try "id = \"queued-plugin\"\nname = \"Replacement\"\nevents = [\"session-start\"]\n".write(
            to: replacement.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo replacement\n".write(
            to: replacement.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )
        _ = try installer.install(from: replacement, replaceExisting: true)
        manager.scanPlugins()
        try manager.enablePlugin(id: "queued-plugin")

        sandbox.runPendingExecutions()
        #expect(sandbox.executedScriptContents.isEmpty)

        manager.dispatchEvent(.sessionStart)
        sandbox.runPendingExecutions()
        #expect(sandbox.executedScriptContents == ["echo replacement\n"])
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
            sandbox: sandbox,
            grantedCapabilitiesProvider: { pluginID in
                pluginID == "run-plugin" ? [.environmentRead] : []
            }
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

    @Test("plugin dispatch only uses approved manifest capabilities")
    @MainActor
    func pluginDispatchOnlyUsesApprovedManifestCapabilities() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("granted-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try """
        name = "Granted Plugin"
        version = "1.0.0"
        author = "Dev"
        events = ["session-start"]
        capabilities = ["environment-read", "network-client"]
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
                pluginID == "granted-plugin" ? [.environmentRead, .networkClient, .processSpawn] : []
            }
        )
        manager.scanPlugins()
        try manager.enablePlugin(id: receipt.pluginID)

        manager.dispatchEvent(.sessionStart)

        #expect(sandbox.executions.count == 1)
        #expect(sandbox.executions[0].capabilities == [.environmentRead, .networkClient])
    }

    @Test("plugin dispatch drops revoked manifest capability")
    @MainActor
    func pluginDispatchDropsRevokedManifestCapability() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("revoked-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try """
        name = "Revoked Plugin"
        version = "1.0.0"
        author = "Dev"
        events = ["session-start"]
        capabilities = ["environment-read", "network-client"]
        """.write(
            to: repo.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo revoked\n".write(
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
                pluginID == "revoked-plugin" ? [.environmentRead] : []
            }
        )
        manager.scanPlugins()
        try manager.enablePlugin(id: receipt.pluginID)

        manager.dispatchEvent(.sessionStart)

        #expect(sandbox.executions.count == 1)
        #expect(sandbox.executions[0].capabilities == [.environmentRead])
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
            sandbox: sandbox,
            grantedCapabilitiesProvider: { pluginID in
                pluginID == "rich-input-plugin" ? [.environmentRead] : []
            }
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
        let grantStore = PluginCapabilityGrantStore(
            backend: MemoryPluginCapabilityGrantBackingStore()
        )
        let installer = PluginInstaller(
            pluginsDirectory: pluginsDirectory,
            capabilityGrantStore: grantStore
        )
        _ = try installer.install(from: repo)

        let stateURL = pluginsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("plugins.json")
        let enabledData = try JSONEncoder().encode(["stateful-plugin"])
        try enabledData.write(to: stateURL)
        try grantStore.grant(.networkClient, for: "stateful-plugin", reason: nil)

        try installer.uninstall(id: "stateful-plugin")

        let updatedData = try Data(contentsOf: stateURL)
        let updatedIDs = try JSONDecoder().decode([String].self, from: updatedData)

        #expect(updatedIDs.isEmpty)
        #expect(try grantStore.grants(for: "stateful-plugin").isEmpty)
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

    @Test("plugin update source store records only credential-free remote provenance")
    func pluginUpdateSourceStoreValidatesAndProtectsRemoteProvenance() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let store = PluginUpdateSourceStore(pluginsDirectory: pluginsDirectory)
        let source = try #require(PluginUpdateSource.remoteRepository(
            URL(string: "ssh://git@example.test/team/plugin.git")!
        ))

        try store.save(source, for: "tagged-plugin")

        #expect(try store.source(for: "tagged-plugin") == source)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: store.directoryURL.appendingPathComponent("tagged-plugin.json").path
        )
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(PluginUpdateSource.remoteRepository(
            URL(string: "https://token@example.test/team/plugin.git")!
        ) == nil)
        #expect(PluginUpdateSource.remoteRepository(
            URL(string: "https://example.test/team/plugin.git?token=secret")!
        ) == nil)
    }

    @Test("installer records remote update provenance only for verified packages")
    func installerRecordsOnlyVerifiedRemoteUpdateProvenance() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let sourceStore = PluginUpdateSourceStore(pluginsDirectory: pluginsDirectory)

        let unsignedSource = root.appendingPathComponent("unsigned-source", isDirectory: true)
        try FileManager.default.createDirectory(
            at: unsignedSource,
            withIntermediateDirectories: true
        )
        try "name = \"Unsigned Remote\"\nversion = \"1.0.0\"\n".write(
            to: unsignedSource.appendingPathComponent(
                PluginManifest.marketplaceManifestFileName
            ),
            atomically: true,
            encoding: .utf8
        )
        let unsignedGit = root.appendingPathComponent("git-unsigned")
        try installExecutableScript(
            at: unsignedGit,
            contents: """
            #!/bin/sh
            destination=
            for argument in "$@"; do destination="$argument"; done
            /bin/cp -R \(shellSingleQuoted(unsignedSource.path)) "$destination"
            """
        )
        let unsignedURL = try #require(URL(
            string: "https://example.test/unsigned-remote.git"
        ))
        let unsignedReceipt = try PluginInstaller(
            pluginsDirectory: pluginsDirectory,
            updateSourceStore: sourceStore,
            gitProcessRunner: MarketplaceGitProcessRunner(
                gitExecutableURL: unsignedGit,
                workingDirectory: root
            )
        ).install(from: unsignedURL)

        #expect(unsignedReceipt.signatureStatus == .unsignedAllowed)
        #expect(try sourceStore.source(for: unsignedReceipt.pluginID) == nil)

        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        let signedSource = root.appendingPathComponent("signed-source", isDirectory: true)
        _ = try writeSignedUpdateManifest(
            to: signedSource,
            name: "Signed Remote",
            version: "1.0.0",
            keyPair: keyPair
        )
        let signedGit = root.appendingPathComponent("git-signed")
        try installExecutableScript(
            at: signedGit,
            contents: """
            #!/bin/sh
            destination=
            for argument in "$@"; do destination="$argument"; done
            /bin/cp -R \(shellSingleQuoted(signedSource.path)) "$destination"
            """
        )
        let signedURL = try #require(URL(
            string: "https://example.test/signed-remote.git"
        ))
        let signedReceipt = try PluginInstaller(
            pluginsDirectory: pluginsDirectory,
            validator: try trustedValidator(for: keyPair),
            updateSourceStore: sourceStore,
            gitProcessRunner: MarketplaceGitProcessRunner(
                gitExecutableURL: signedGit,
                workingDirectory: root
            )
        ).install(from: signedURL)

        #expect(signedReceipt.signatureStatus == .verified)
        #expect(
            try sourceStore.source(for: signedReceipt.pluginID)
                == PluginUpdateSource.remoteRepository(signedURL)
        )
    }

    @Test("plugin updater reports newer semver tags from recorded remote source")
    func pluginUpdaterReportsNewerSemverTags() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let pluginDirectory = pluginsDirectory.appendingPathComponent("tagged-plugin", isDirectory: true)
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        let manifest = try writeSignedUpdateManifest(
            to: pluginDirectory,
            name: "Tagged Plugin",
            version: "1.1.0",
            keyPair: keyPair
        )
        let sourceStore = PluginUpdateSourceStore(pluginsDirectory: pluginsDirectory)
        let repositoryURL = URL(string: "https://example.test/tagged-plugin.git")!
        try sourceStore.save(
            try #require(PluginUpdateSource.remoteRepository(repositoryURL)),
            for: manifest.id
        )
        let updater = PluginUpdater(
            sourceStore: sourceStore,
            validator: try trustedValidator(for: keyPair)
        ) { sourceURL in
            #expect(sourceURL == repositoryURL)
            return "abc\trefs/tags/v1.1.0\ndef\trefs/tags/v1.2.0\n"
        }

        let updates = await updater.availableUpdates(for: [manifest])

        #expect(updates.count == 1)
        #expect(updates[0].pluginID == "tagged-plugin")
        #expect(updates[0].latestVersion == "1.2.0")
    }

    @Test("plugin updater ignores same, older, and malformed tags")
    func pluginUpdaterIgnoresSameOrOlderTags() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let pluginDirectory = pluginsDirectory.appendingPathComponent("current-plugin", isDirectory: true)
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        let manifest = try writeSignedUpdateManifest(
            to: pluginDirectory,
            name: "Current Plugin",
            version: "2.0.0",
            keyPair: keyPair
        )
        let sourceStore = PluginUpdateSourceStore(pluginsDirectory: pluginsDirectory)
        try sourceStore.save(
            try #require(PluginUpdateSource.remoteRepository(
                URL(string: "https://example.test/current-plugin.git")!
            )),
            for: manifest.id
        )
        let updater = PluginUpdater(
            sourceStore: sourceStore,
            validator: try trustedValidator(for: keyPair)
        ) { _ in
            "abc\trefs/tags/v2.0.0\ndef\trefs/tags/v1.9.0\nghi\trefs/tags/not-semver\n"
        }

        #expect(await updater.availableUpdates(for: [manifest]).isEmpty)
    }

    @Test("plugin updater skips packages without installer-recorded remote provenance")
    func pluginUpdaterSkipsUnrecordedPackages() async {
        let manifest = PluginManifest(
            id: "local-plugin",
            name: "Local Plugin",
            description: "Local plugin",
            version: "1.0.0",
            author: "Dev",
            minCocxyVersion: nil,
            events: [],
            directoryPath: "/tmp/local-plugin"
        )
        let updater = PluginUpdater(
            sourceStore: PluginUpdateSourceStore(
                pluginsDirectory: URL(fileURLWithPath: "/tmp/no-recorded-plugin-sources")
            )
        ) { _ in
            "abc\trefs/tags/v9.0.0\n"
        }

        #expect(await updater.availableUpdates(for: [manifest]).isEmpty)
    }

    @Test("plugin updater rejects unsigned untrusted and tampered packages before querying")
    func pluginUpdaterRequiresVerifiedInstalledPackage() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let sourceStore = PluginUpdateSourceStore(pluginsDirectory: pluginsDirectory)

        let unsignedDirectory = pluginsDirectory.appendingPathComponent(
            "unsigned-update",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: unsignedDirectory,
            withIntermediateDirectories: true
        )
        try "name = \"Unsigned Update\"\nversion = \"1.0.0\"\n".write(
            to: unsignedDirectory.appendingPathComponent(
                PluginManifest.marketplaceManifestFileName
            ),
            atomically: true,
            encoding: .utf8
        )
        let unsignedManifest = try PluginRegistry.loadManifest(from: unsignedDirectory)

        let unknownKeyPair = try SignatureKeyPair.generate(author: "Unknown")
        let untrustedManifest = try writeSignedUpdateManifest(
            to: pluginsDirectory.appendingPathComponent("untrusted-update", isDirectory: true),
            name: "Untrusted Update",
            version: "1.0.0",
            keyPair: unknownKeyPair
        )

        let trustedKeyPair = try SignatureKeyPair.generate(author: "Cocxy")
        let tamperedDirectory = pluginsDirectory.appendingPathComponent(
            "tampered-update",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: tamperedDirectory,
            withIntermediateDirectories: true
        )
        let tamperedScript = tamperedDirectory.appendingPathComponent("on-session-start.sh")
        try "echo trusted\n".write(
            to: tamperedScript,
            atomically: true,
            encoding: .utf8
        )
        let tamperedManifest = try writeSignedUpdateManifest(
            to: tamperedDirectory,
            name: "Tampered Update",
            version: "1.0.0",
            keyPair: trustedKeyPair
        )
        try "echo substituted\n".write(
            to: tamperedScript,
            atomically: true,
            encoding: .utf8
        )

        let currentManifest = try writeSignedUpdateManifest(
            to: pluginsDirectory.appendingPathComponent("stale-update", isDirectory: true),
            name: "Stale Update",
            version: "2.0.0",
            keyPair: trustedKeyPair
        )
        let staleManifest = PluginManifest(
            id: currentManifest.id,
            name: currentManifest.name,
            description: currentManifest.description,
            version: "1.0.0",
            author: currentManifest.author,
            minCocxyVersion: currentManifest.minCocxyVersion,
            events: currentManifest.events,
            directoryPath: currentManifest.directoryPath,
            manifestFileName: currentManifest.manifestFileName,
            repositoryURL: currentManifest.repositoryURL,
            homepageURL: currentManifest.homepageURL,
            license: currentManifest.license,
            capabilities: currentManifest.capabilities,
            signature: currentManifest.signature
        )

        let manifests = [
            unsignedManifest,
            untrustedManifest,
            tamperedManifest,
            staleManifest,
        ]
        for manifest in manifests {
            let sourceURL = try #require(URL(
                string: "https://example.test/\(manifest.id).git"
            ))
            try sourceStore.save(
                try #require(PluginUpdateSource.remoteRepository(sourceURL)),
                for: manifest.id
            )
        }
        let queryRecorder = PluginRemoteTagQueryRecorder()
        let updater = PluginUpdater(
            sourceStore: sourceStore,
            validator: try trustedValidator(for: trustedKeyPair)
        ) { sourceURL in
            queryRecorder.record(sourceURL)
            return "abc\trefs/tags/v9.0.0\n"
        }

        let result = await updater.checkAvailableUpdates(for: manifests)

        #expect(result.updates.isEmpty)
        #expect(result.checkedSourceCount == 0)
        #expect(result.failedSourceCount == 4)
        #expect(queryRecorder.urls.isEmpty)
    }

    @Test("plugin updater reports successful and failed source checks separately")
    func pluginUpdaterReportsPartialSourceFailures() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let sourceStore = PluginUpdateSourceStore(pluginsDirectory: pluginsDirectory)
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        let manifests = try ["current-plugin", "offline-plugin"].map { pluginID in
            try writeSignedUpdateManifest(
                to: pluginsDirectory.appendingPathComponent(pluginID, isDirectory: true),
                name: pluginID,
                version: "1.0.0",
                keyPair: keyPair
            )
        }
        for manifest in manifests {
            let sourceURL = try #require(URL(
                string: "https://example.test/\(manifest.id).git"
            ))
            try sourceStore.save(
                try #require(PluginUpdateSource.remoteRepository(sourceURL)),
                for: manifest.id
            )
        }
        let updater = PluginUpdater(
            sourceStore: sourceStore,
            validator: try trustedValidator(for: keyPair)
        ) { sourceURL in
            if sourceURL.lastPathComponent == "offline-plugin.git" {
                throw PluginUpdaterError.gitFailed(128)
            }
            return "abc\trefs/tags/v1.2.0\n"
        }

        let result = await updater.checkAvailableUpdates(for: manifests)

        #expect(result.updates.map(\.pluginID) == ["current-plugin"])
        #expect(result.checkedSourceCount == 1)
        #expect(result.failedSourceCount == 1)
        #expect(!result.wasCancelled)
    }

    @Test("plugin updater preserves cancellation instead of reporting a source failure")
    func pluginUpdaterPreservesCancellation() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let sourceStore = PluginUpdateSourceStore(pluginsDirectory: pluginsDirectory)
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        let manifest = try writeSignedUpdateManifest(
            to: pluginsDirectory.appendingPathComponent("cancelled-plugin", isDirectory: true),
            name: "Cancelled Plugin",
            version: "1.0.0",
            keyPair: keyPair
        )
        let sourceURL = try #require(URL(string: "https://example.test/cancelled-plugin.git"))
        try sourceStore.save(
            try #require(PluginUpdateSource.remoteRepository(sourceURL)),
            for: manifest.id
        )
        let updater = PluginUpdater(
            sourceStore: sourceStore,
            validator: try trustedValidator(for: keyPair)
        ) { _ in
            throw CancellationError()
        }

        let result = await updater.checkAvailableUpdates(for: [manifest])

        #expect(result.updates.isEmpty)
        #expect(result.checkedSourceCount == 0)
        #expect(result.failedSourceCount == 0)
        #expect(result.wasCancelled)
    }

    @Test("remote tag query strips inherited Git execution configuration")
    func remoteTagQueryUsesHardenedEnvironment() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fakeGit = root.appendingPathComponent("git")
        try installExecutableScript(
            at: fakeGit,
            contents: #"""
            #!/bin/sh
            printf 'env:%s|%s|%s|%s|%s\n' "$GIT_CONFIG_GLOBAL" "$GIT_CONFIG_NOSYSTEM" "$GIT_TERMINAL_PROMPT" "${GIT_CONFIG_COUNT:-}" "${UNRELATED_SECRET:-}"
            printf 'cwd:%s|%s\n' "$GIT_CEILING_DIRECTORIES" "$PWD"
            printf 'args:%s\n' "$*"
            printf 'abc\trefs/tags/v1.2.3\n'
            """#
        )
        let runner = MarketplaceGitProcessRunner(
            gitExecutableURL: fakeGit,
            workingDirectory: root,
            inheritedEnvironment: [
                "GIT_CONFIG_GLOBAL": "/tmp/attacker-config",
                "GIT_CONFIG_COUNT": "1",
                "GIT_CEILING_DIRECTORIES": "/",
                "UNRELATED_SECRET": "must-not-cross",
            ]
        )

        let output = try PluginUpdater.runGitTagQuery(
            sourceURL: URL(string: "https://example.test/plugin.git")!,
            processRunner: runner
        )

        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        #expect(lines.first == "env:/dev/null|1|0||")
        #expect(!output.contains("attacker-config"))
        #expect(!output.contains("must-not-cross"))
        let workingDirectories = try #require(
            lines.first(where: { $0.hasPrefix("cwd:") })?.dropFirst("cwd:".count)
        ).split(separator: "|", omittingEmptySubsequences: false)
        #expect(workingDirectories.count == 2)
        let ceilingDirectory = URL(fileURLWithPath: String(workingDirectories[0]))
            .resolvingSymlinksInPath()
        let processDirectory = URL(fileURLWithPath: String(workingDirectories[1]))
            .resolvingSymlinksInPath()
        #expect(ceilingDirectory == processDirectory)
        #expect(ceilingDirectory.lastPathComponent.hasPrefix(".cocxy-marketplace-git-"))
        #expect(!FileManager.default.fileExists(atPath: String(workingDirectories[0])))
        let invocation = try #require(lines.first(where: { $0.hasPrefix("args:") }))
        #expect(invocation.contains("core.askPass=/usr/bin/false"))
        #expect(invocation.contains("core.gitProxy=none"))
        #expect(invocation.contains("credential.helper="))
        #expect(invocation.contains("protocol.ext.allow=never"))
        #expect(invocation.contains("protocol.file.allow=never"))
    }

    @Test("remote tag query times out and reaps a signal-resistant process")
    func remoteTagQueryTimesOutAndReapsProcess() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fakeGit = root.appendingPathComponent("git")
        let pidFile = root.appendingPathComponent("git.pid")
        try installExecutableScript(
            at: fakeGit,
            contents: """
            #!/bin/sh
            printf '%s' "$$" > \(shellSingleQuoted(pidFile.path))
            trap '' TERM
            while :; do sleep 1; done
            """
        )
        let timeout: TimeInterval = 3
        let runner = MarketplaceGitProcessRunner(
            gitExecutableURL: fakeGit,
            workingDirectory: root,
            timeoutSeconds: timeout
        )
        let startedAt = Date()

        #expect(throws: PluginUpdaterError.timedOut(timeout)) {
            _ = try PluginUpdater.runGitTagQuery(
                sourceURL: URL(string: "https://example.test/plugin.git")!,
                processRunner: runner
            )
        }

        #expect(Date().timeIntervalSince(startedAt) < 6)
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8)))
        errno = 0
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test("remote tag query rejects output beyond its retained byte budget")
    func remoteTagQueryRejectsOversizedOutput() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fakeGit = root.appendingPathComponent("git")
        try installExecutableScript(
            at: fakeGit,
            contents: """
            #!/bin/sh
            /usr/bin/yes x | /usr/bin/head -c 4096
            """
        )
        let limit = 256
        let runner = MarketplaceGitProcessRunner(
            gitExecutableURL: fakeGit,
            workingDirectory: root,
            maximumRetainedBytesPerStream: limit
        )

        #expect(throws: PluginUpdaterError.outputTooLarge(limit)) {
            _ = try PluginUpdater.runGitTagQuery(
                sourceURL: URL(string: "https://example.test/plugin.git")!,
                processRunner: runner
            )
        }
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
            capabilities: [.environmentRead, .networkClient, .filesystemRead, .filesystemWrite]
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
        #expect(
            plan.environment["COCXY_PLUGIN_CAPABILITIES"]
                == "environment-read,filesystem-read,filesystem-write,network-client"
        )
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
        #expect(!profile.contains(#"(allow file-read* (subpath "/tmp"))"#))
        #expect(!profile.contains(#"(allow file-read* (subpath "/private/tmp"))"#))
    }

    @Test("sandbox withholds event data without environment read capability")
    func sandboxWithholdsEventDataWithoutEnvironmentRead() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginDirectory = root.appendingPathComponent("safe-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        let scriptURL = pluginDirectory.appendingPathComponent("on-rich-input-submit.sh")
        try "#!/bin/sh\nexit 0\n".write(to: scriptURL, atomically: true, encoding: .utf8)

        let plan = try PluginSandbox(kernelSandboxEnabled: false).makeExecutionPlan(
            scriptPath: scriptURL.path,
            environment: [
                "COCXY_EVENT": "rich-input-submit",
                "COCXY_RICH_INPUT_TEXT": "private prompt",
                "COCXY_RICH_INPUT_ATTACHMENT_COUNT": "1",
            ],
            pluginID: "safe-plugin",
            pluginDirectory: pluginDirectory.path,
            capabilities: [.networkClient]
        )

        #expect(plan.environment["COCXY_EVENT"] == "rich-input-submit")
        #expect(plan.environment["COCXY_RICH_INPUT_TEXT"] == nil)
        #expect(plan.environment["COCXY_RICH_INPUT_ATTACHMENT_COUNT"] == nil)
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

    @Test("production sandbox rejects stale authorization before process launch")
    func productionSandboxRejectsStaleAuthorization() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let pluginDirectory = pluginsDirectory.appendingPathComponent(
            "stale-plugin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: pluginDirectory,
            withIntermediateDirectories: true
        )
        let markerURL = root.appendingPathComponent("stale-marker.txt")
        let scriptURL = pluginDirectory.appendingPathComponent("on-session-start.sh")
        try "#!/bin/sh\nprintf launched > \"$MARKER_PATH\"\n".write(
            to: scriptURL,
            atomically: true,
            encoding: .utf8
        )
        let authorizationChecked = DispatchSemaphore(value: 0)
        let authorization = PluginExecutionAuthorization(
            pluginsDirectory: pluginsDirectory
        ) {
            authorizationChecked.signal()
            return false
        }

        PluginSandbox(timeoutSeconds: 2, kernelSandboxEnabled: false).execute(
            scriptPath: scriptURL.path,
            environment: ["MARKER_PATH": markerURL.path],
            pluginID: "stale-plugin",
            pluginDirectory: pluginDirectory.path,
            capabilities: [.environmentRead],
            authorization: authorization
        )

        #expect(authorizationChecked.wait(timeout: .now() + 2) == .success)
        #expect(!FileManager.default.fileExists(atPath: markerURL.path))
    }

    @Test("closing one shared registry lease preserves concurrent leases")
    func sharedRegistryLeasesReleaseIndependently() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let firstAcquired = DispatchSemaphore(value: 0)
        let secondAcquired = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let releaseSecond = DispatchSemaphore(value: 0)
        let firstFinished = DispatchSemaphore(value: 0)
        let secondFinished = DispatchSemaphore(value: 0)
        let errors = PluginRegistryLeaseErrorRecorder()
        var firstDidFinish = false
        var secondDidFinish = false

        DispatchQueue.global(qos: .userInitiated).async {
            defer { firstFinished.signal() }
            do {
                try PluginRegistrySynchronization.shared.withSharedFileLock(
                    pluginsDirectory: pluginsDirectory
                ) {
                    firstAcquired.signal()
                    _ = releaseFirst.wait(timeout: .now() + 2)
                }
            } catch {
                errors.record(error)
            }
        }
        #expect(firstAcquired.wait(timeout: .now() + 2) == .success)

        DispatchQueue.global(qos: .userInitiated).async {
            defer { secondFinished.signal() }
            do {
                try PluginRegistrySynchronization.shared.withSharedFileLock(
                    pluginsDirectory: pluginsDirectory
                ) {
                    secondAcquired.signal()
                    _ = releaseSecond.wait(timeout: .now() + 2)
                }
            } catch {
                errors.record(error)
            }
        }
        defer {
            releaseFirst.signal()
            releaseSecond.signal()
            if !firstDidFinish {
                _ = firstFinished.wait(timeout: .now() + 2)
            }
            if !secondDidFinish {
                _ = secondFinished.wait(timeout: .now() + 2)
            }
        }
        #expect(secondAcquired.wait(timeout: .now() + 2) == .success)

        releaseFirst.signal()
        let firstCompletion = firstFinished.wait(timeout: .now() + 2)
        firstDidFinish = firstCompletion == .success
        #expect(firstDidFinish)
        #expect(try PluginRegistrySynchronization.shared.withFileLockIfAvailable(
            pluginsDirectory: pluginsDirectory
        ) { true } == nil)

        releaseSecond.signal()
        let secondCompletion = secondFinished.wait(timeout: .now() + 2)
        secondDidFinish = secondCompletion == .success
        #expect(secondDidFinish)
        #expect(errors.messages.isEmpty)
        #expect(try PluginRegistrySynchronization.shared.withFileLockIfAvailable(
            pluginsDirectory: pluginsDirectory
        ) { true } == true)
    }

    @Test("running plugin keeps reads responsive and mutations fail fast")
    @MainActor
    func runningPluginUsesSharedRegistryLease() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("lease-source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try """
        id = "lease-plugin"
        name = "Lease Plugin"
        events = ["session-start"]
        capabilities = ["environment-read"]
        """.write(
            to: source.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try """
        #!/bin/sh
        printf started > "$MARKER_PATH"
        sleep 0.5
        printf finished > "$FINISHED_PATH"
        """.write(
            to: source.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )

        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        _ = try PluginInstaller(pluginsDirectory: pluginsDirectory).install(from: source)
        let manager = PluginManager(
            pluginsDirectory: pluginsDirectory.path,
            sandbox: PluginSandbox(timeoutSeconds: 2, kernelSandboxEnabled: false),
            grantedCapabilitiesProvider: { pluginID in
                pluginID == "lease-plugin" ? [.environmentRead] : []
            }
        )
        manager.scanPlugins()
        try manager.enablePlugin(id: "lease-plugin")

        let markerURL = root.appendingPathComponent("lease-started.txt")
        let finishedURL = root.appendingPathComponent("lease-finished.txt")
        manager.dispatchEvent(
            .sessionStart,
            environment: [
                "MARKER_PATH": markerURL.path,
                "FINISHED_PATH": finishedURL.path,
            ]
        )

        let startDeadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: markerURL.path),
              Date() < startDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(FileManager.default.fileExists(atPath: markerURL.path))

        let readStartedAt = Date()
        #expect(manager.enabledPlugins.map(\.id) == ["lease-plugin"])
        #expect(Date().timeIntervalSince(readStartedAt) < 0.2)

        let mutationStartedAt = Date()
        #expect(throws: PluginManagerError.registryBusy) {
            try manager.disablePlugin(id: "lease-plugin")
        }
        #expect(Date().timeIntervalSince(mutationStartedAt) < 0.2)

        let finishDeadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: finishedURL.path),
              Date() < finishDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(FileManager.default.fileExists(atPath: finishedURL.path))

        try manager.disablePlugin(id: "lease-plugin")
        #expect(manager.enabledPlugins.isEmpty)
    }

    private func writeSignedUpdateManifest(
        to pluginDirectory: URL,
        name: String,
        version: String,
        keyPair: SignatureKeyPair
    ) throws -> PluginManifest {
        try FileManager.default.createDirectory(
            at: pluginDirectory,
            withIntermediateDirectories: true
        )
        _ = try writeSignedPluginManifest(
            """
            name = "\(name)"
            version = "\(version)"
            author = "\(keyPair.author)"
            """,
            to: pluginDirectory,
            keyPair: keyPair,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        return try PluginRegistry.loadManifest(from: pluginDirectory)
    }

    private func trustedValidator(for keyPair: SignatureKeyPair) throws -> PluginValidator {
        var registry = TrustedAuthorRegistry()
        try registry.trust(displayName: keyPair.author, publicKey: keyPair.publicKey)
        return PluginValidator(trustedAuthors: registry)
    }

    private func writeSignedPluginManifest(
        _ unsignedManifest: String,
        to pluginDirectory: URL,
        keyPair: SignatureKeyPair,
        timestamp: Date
    ) throws -> SignedArtifact {
        let manifestURL = pluginDirectory.appendingPathComponent(
            PluginManifest.marketplaceManifestFileName
        )
        let normalized = unsignedManifest.trimmingCharacters(in: .newlines) + "\n"
        try normalized.write(to: manifestURL, atomically: true, encoding: .utf8)
        let payload = try PluginPackageSignaturePayload.payload(at: pluginDirectory)
        let artifact = try SignatureSigner().sign(
            payload: payload,
            author: keyPair.author,
            keyPair: keyPair,
            timestamp: timestamp
        )
        try signedManifestContent(normalized, artifact: artifact).write(
            to: manifestURL,
            atomically: true,
            encoding: .utf8
        )
        return artifact
    }

    private func signedManifestContent(
        _ unsignedManifest: String,
        artifact: SignedArtifact
    ) -> String {
        let normalized = unsignedManifest.trimmingCharacters(in: .newlines) + "\n"
        return normalized + """
        signature = "\(artifact.signature)"
        signature-algorithm = "\(artifact.algorithm.rawValue)"
        signature-key-id = "\(artifact.keyID)"
        signature-author = "\(artifact.author)"
        signature-timestamp = "\(ISO8601DateFormatter.cocxySignature.string(from: artifact.timestamp))"
        signature-payload-sha256 = "\(artifact.payloadSHA256)"
        """
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class PluginRemoteTagQueryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedURLs: [URL] = []

    var urls: [URL] {
        lock.withLock { recordedURLs }
    }

    func record(_ url: URL) {
        lock.withLock {
            recordedURLs.append(url)
        }
    }
}

private final class PluginRegistryLeaseErrorRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedMessages: [String] = []

    var messages: [String] {
        lock.withLock { recordedMessages }
    }

    func record(_ error: Error) {
        lock.withLock {
            recordedMessages.append(String(describing: error))
        }
    }
}

private final class PluginAuthorizationResetSnapshotRecorder: @unchecked Sendable {
    private let pluginID: String
    private let pluginsDirectoryPath: String
    private let stateURL: URL
    private let grantStore: PluginCapabilityGrantStore
    private let lock = NSLock()
    private var count = 0
    private var enabledAtNotification: Bool?
    private var grantsAtNotification: Bool?

    init(
        pluginID: String,
        pluginsDirectory: URL,
        stateURL: URL,
        grantStore: PluginCapabilityGrantStore
    ) {
        self.pluginID = pluginID
        self.pluginsDirectoryPath = PluginRegistrySynchronization
            .canonicalDirectoryURL(pluginsDirectory).path
        self.stateURL = stateURL
        self.grantStore = grantStore
    }

    var notificationCount: Int { lock.withLock { count } }
    var wasEnabledAtNotification: Bool? { lock.withLock { enabledAtNotification } }
    var hadGrantsAtNotification: Bool? { lock.withLock { grantsAtNotification } }

    func record(_ notification: Notification) {
        guard notification.userInfo?["pluginID"] as? String == pluginID,
              notification.userInfo?["pluginsDirectory"] as? String
                == pluginsDirectoryPath else {
            return
        }
        let enabledIDs = (
            try? JSONDecoder().decode([String].self, from: Data(contentsOf: stateURL))
        ) ?? []
        let hasGrants = !((try? grantStore.grants(for: pluginID)) ?? []).isEmpty
        lock.withLock {
            count += 1
            enabledAtNotification = enabledIDs.contains(pluginID)
            grantsAtNotification = hasGrants
        }
    }
}

private final class DeferredPluginSandbox: PluginSandboxing, @unchecked Sendable {
    private struct PendingExecution {
        let scriptPath: String
        let authorization: PluginExecutionAuthorization
    }

    private var pending: [PendingExecution] = []
    private(set) var executedScriptContents: [String] = []

    var pendingCount: Int { pending.count }

    func execute(
        scriptPath: String,
        environment: [String: String],
        pluginID: String,
        pluginDirectory: String,
        capabilities: Set<PluginCapability>,
        authorization: PluginExecutionAuthorization
    ) {
        _ = environment
        _ = pluginID
        _ = pluginDirectory
        _ = capabilities
        pending.append(PendingExecution(
            scriptPath: scriptPath,
            authorization: authorization
        ))
    }

    func runPendingExecutions() {
        let executions = pending
        pending.removeAll()
        for execution in executions where execution.authorization.isValid() {
            guard let contents = try? String(
                contentsOfFile: execution.scriptPath,
                encoding: .utf8
            ) else {
                continue
            }
            executedScriptContents.append(contents)
        }
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
        capabilities: Set<PluginCapability>,
        authorization: PluginExecutionAuthorization
    ) {
        guard authorization.isValid() else { return }
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
