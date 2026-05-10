// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
import Foundation
@testable import CocxyTerminal

@Suite("Update channel metadata")
struct ChannelKindSwiftTestingTests {

    @Test("channels expose bundle identifiers and appcast URLs")
    func channelsExposeBundleIdentifiersAndAppcastURLs() {
        #expect(ChannelKind.stable.bundleIdentifier == "dev.cocxy.terminal")
        #expect(ChannelKind.preview.bundleIdentifier == "dev.cocxy.terminal.preview")
        #expect(ChannelKind.nightly.bundleIdentifier == "dev.cocxy.terminal.nightly")

        #expect(ChannelKind.stable.feedURLString == "https://cocxy.dev/appcast.xml")
        #expect(ChannelKind.preview.feedURLString == "https://cocxy.dev/appcast-preview.xml")
        #expect(ChannelKind.nightly.feedURLString == "https://cocxy.dev/appcast-nightly.xml")
    }

    @Test("bundle identifier resolves the current channel")
    func bundleIdentifierResolvesCurrentChannel() {
        #expect(ChannelKind(bundleIdentifier: "dev.cocxy.terminal") == .stable)
        #expect(ChannelKind(bundleIdentifier: "dev.cocxy.terminal.preview") == .preview)
        #expect(ChannelKind(bundleIdentifier: "dev.cocxy.terminal.nightly") == .nightly)
        #expect(ChannelKind(bundleIdentifier: "dev.cocxy.terminal.unknown") == .stable)
    }

    @Test("Sparkle configuration uses Cocxy owned endpoints and shared public key")
    func sparkleConfigurationUsesCocxyOwnedEndpointsAndSharedPublicKey() {
        let preview = ChannelSparkleConfiguration(channel: .preview)
        let nightly = ChannelSparkleConfiguration(channel: .nightly)

        #expect(preview.feedURLString == "https://cocxy.dev/appcast-preview.xml")
        #expect(nightly.feedURLString == "https://cocxy.dev/appcast-nightly.xml")
        #expect(preview.publicEDKey == ChannelSparkleConfiguration.defaultPublicEDKey)
        #expect(nightly.publicEDKey == ChannelSparkleConfiguration.defaultPublicEDKey)
    }

    @Test("resolver can be injected for deterministic tests")
    func resolverCanBeInjectedForDeterministicTests() {
        let resolver = ChannelResolver(bundleIdentifierProvider: {
            "dev.cocxy.terminal.preview"
        })

        #expect(resolver.currentChannel() == .preview)
    }

    @Test("build and audit scripts know preview and nightly channels")
    func buildAndAuditScriptsKnowPreviewAndNightlyChannels() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let buildApp = try String(
            contentsOf: root.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )
        let verify = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-app-bundle.sh"),
            encoding: .utf8
        )
        let privacyAudit = try String(
            contentsOf: root.appendingPathComponent("scripts/run-privacy-audit.sh"),
            encoding: .utf8
        )

        #expect(buildApp.contains("--channel stable|preview|nightly"))
        #expect(buildApp.contains("dev.cocxy.terminal.preview"))
        #expect(buildApp.contains("https://cocxy.dev/appcast-preview.xml"))
        #expect(buildApp.contains("CocxyTerminalPreview"))
        #expect(buildApp.contains("dev.cocxy.terminal.nightly"))
        #expect(verify.contains("dev.cocxy.terminal.preview"))
        #expect(verify.contains("https://cocxy.dev/appcast-preview.xml"))
        #expect(privacyAudit.contains("dev.cocxy.terminal.preview"))
        #expect(privacyAudit.contains("https://cocxy.dev/appcast-preview.xml"))
    }
}
