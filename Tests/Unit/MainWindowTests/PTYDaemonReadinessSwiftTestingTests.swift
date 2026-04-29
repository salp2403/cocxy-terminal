// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonReadinessSwiftTestingTests.swift - Local PTY daemon fallback tests.

import Foundation
import Testing
@testable import CocxyTerminal
import CocxyShared

@Suite("PTYDaemonReadinessResolver")
struct PTYDaemonReadinessSwiftTestingTests {

    @Test("disabled config never probes helper")
    func disabledNeverProbesHelper() {
        var didProbe = false
        let resolver = PTYDaemonReadinessResolver(expectedHelperVersion: nil) { _ in
            didProbe = true
            return .success(PTYDaemonHello(version: "dev"))
        }

        let readiness = resolver.resolve(
            config: ExperimentalConfig(ptyDaemonEnabled: false),
            helperURL: URL(fileURLWithPath: "/tmp/cocxyd")
        )

        #expect(readiness == .disabled)
        #expect(didProbe == false)
        #expect(readiness.shouldUseInProcessEngine == true)
    }

    @Test("enabled config falls back when helper is missing")
    func enabledFallsBackWhenHelperMissing() {
        let resolver = PTYDaemonReadinessResolver()
        let readiness = resolver.resolve(
            config: ExperimentalConfig(ptyDaemonEnabled: true),
            helperURL: nil
        )

        #expect(readiness == .helperMissing)
        #expect(readiness.shouldUseInProcessEngine == true)
    }

    @Test("enabled config falls back when helper handshake fails")
    func enabledFallsBackWhenHandshakeFails() {
        let resolver = PTYDaemonReadinessResolver(expectedHelperVersion: nil) { _ in
            .failure(PTYDaemonHandshake.HandshakeError.timeout)
        }

        let readiness = resolver.resolve(
            config: ExperimentalConfig(ptyDaemonEnabled: true),
            helperURL: URL(fileURLWithPath: "/tmp/cocxyd")
        )

        if case .helperUnhealthy(let reason) = readiness {
            #expect(reason.contains("timeout"))
        } else {
            Issue.record("Expected helperUnhealthy, got \(readiness)")
        }
        #expect(readiness.shouldUseInProcessEngine == true)
    }

    @Test("healthy IPC-only helper is explicit fallback")
    func healthyIPCOnlyHelperFallsBack() {
        let hello = PTYDaemonHello(version: "dev", capabilities: [PTYDaemonProtocol.jsonLinesCapability])
        let resolver = PTYDaemonReadinessResolver(expectedHelperVersion: nil) { _ in .success(hello) }

        let readiness = resolver.resolve(
            config: ExperimentalConfig(ptyDaemonEnabled: true),
            helperURL: URL(fileURLWithPath: "/tmp/cocxyd")
        )

        #expect(readiness == .helperHealthyButSurfaceBridgeUnavailable(hello))
        #expect(readiness.shouldUseInProcessEngine == true)
    }

    @Test("terminal-surface-only helper still falls back")
    func terminalSurfaceOnlyHelperStillFallsBack() {
        let hello = PTYDaemonHello(
            version: "dev",
            capabilities: [
                PTYDaemonProtocol.jsonLinesCapability,
                PTYDaemonProtocol.terminalSurfaceCapability
            ]
        )
        let resolver = PTYDaemonReadinessResolver(expectedHelperVersion: nil) { _ in .success(hello) }

        let readiness = resolver.resolve(
            config: ExperimentalConfig(ptyDaemonEnabled: true),
            helperURL: URL(fileURLWithPath: "/tmp/cocxyd")
        )

        #expect(readiness == .helperHealthyButSurfaceBridgeUnavailable(hello))
        #expect(readiness.shouldUseInProcessEngine == true)
        #expect(readiness.diagnostic.contains("complete terminal engine"))
    }

    @Test("terminal-engine capable helper without host renderer still falls back")
    func terminalEngineHelperWithoutHostRendererStillFallsBack() {
        let hello = PTYDaemonHello(
            version: "dev",
            capabilities: [
                PTYDaemonProtocol.jsonLinesCapability,
                PTYDaemonProtocol.terminalSurfaceCapability,
                PTYDaemonProtocol.terminalEngineCapability
            ]
        )
        let resolver = PTYDaemonReadinessResolver(expectedHelperVersion: nil) { _ in .success(hello) }

        let readiness = resolver.resolve(
            config: ExperimentalConfig(ptyDaemonEnabled: true),
            helperURL: URL(fileURLWithPath: "/tmp/cocxyd")
        )

        #expect(readiness == .helperHealthyButSurfaceBridgeUnavailable(hello))
        #expect(readiness.shouldUseInProcessEngine == true)
        #expect(readiness.diagnostic.contains("host renderer"))
    }

    @Test("terminal-engine helper with host renderer selects the daemon adapter path")
    func terminalEngineHelperWithHostRendererSelectsDaemonAdapterPath() {
        let hello = PTYDaemonHello(
            version: "dev",
            capabilities: [
                PTYDaemonProtocol.jsonLinesCapability,
                PTYDaemonProtocol.terminalSurfaceCapability,
                PTYDaemonProtocol.terminalEngineCapability,
                PTYDaemonProtocol.terminalHostRendererCapability
            ]
        )
        let resolver = PTYDaemonReadinessResolver(expectedHelperVersion: nil) { _ in .success(hello) }

        let readiness = resolver.resolve(
            config: ExperimentalConfig(ptyDaemonEnabled: true),
            helperURL: URL(fileURLWithPath: "/tmp/cocxyd")
        )

        #expect(readiness == .terminalSurfaceBridgeAvailable(hello))
        #expect(readiness.shouldUseInProcessEngine == false)
        #expect(readiness.diagnostic.contains("PTYDaemonClient"))
    }

    @Test("helper version mismatch falls back before capability activation")
    func helperVersionMismatchFallsBack() {
        let hello = PTYDaemonHello(
            version: "0.1.90",
            capabilities: [
                PTYDaemonProtocol.jsonLinesCapability,
                PTYDaemonProtocol.terminalSurfaceCapability,
                PTYDaemonProtocol.terminalEngineCapability,
                PTYDaemonProtocol.terminalHostRendererCapability
            ]
        )
        let resolver = PTYDaemonReadinessResolver(expectedHelperVersion: "0.1.91") { _ in .success(hello) }

        let readiness = resolver.resolve(
            config: ExperimentalConfig(ptyDaemonEnabled: true),
            helperURL: URL(fileURLWithPath: "/tmp/cocxyd")
        )

        #expect(readiness == .helperVersionMismatch(actual: "0.1.90", expected: "0.1.91"))
        #expect(readiness.shouldUseInProcessEngine == true)
        #expect(readiness.diagnostic.contains("does not match app version"))
    }

    @Test("helper locator prefers embedded LaunchServices helper app over legacy Resources binary")
    func helperLocatorPrefersEmbeddedHelperApp() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-helper-locator-\(UUID().uuidString)", isDirectory: true)
        let app = root.appendingPathComponent("CocxyTerminal.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macos = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        let helperMacOS = contents
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchServices", isDirectory: true)
            .appendingPathComponent("cocxyd.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)

        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helperMacOS, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appExecutable = macos.appendingPathComponent("CocxyTerminal")
        let legacyHelper = resources.appendingPathComponent("cocxyd")
        let embeddedHelper = helperMacOS.appendingPathComponent("cocxyd")
        try writeExecutable("#!/bin/sh\nexit 0\n", to: appExecutable)
        try writeExecutable("#!/bin/sh\necho legacy\n", to: legacyHelper)
        try writeExecutable("#!/bin/sh\necho embedded\n", to: embeddedHelper)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key>
            <string>CocxyTerminal</string>
            <key>CFBundleIdentifier</key>
            <string>dev.cocxy.test</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
        </dict>
        </plist>
        """
        try plist.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        let bundle = try #require(Bundle(url: app))
        let locator = PTYDaemonHelperLocator(bundle: bundle)

        #expect(locator.executableURL()?.path == embeddedHelper.path)
    }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
