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
        let resolver = PTYDaemonReadinessResolver { _ in
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
        let resolver = PTYDaemonReadinessResolver { _ in
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
        let resolver = PTYDaemonReadinessResolver { _ in .success(hello) }

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
        let resolver = PTYDaemonReadinessResolver { _ in .success(hello) }

        let readiness = resolver.resolve(
            config: ExperimentalConfig(ptyDaemonEnabled: true),
            helperURL: URL(fileURLWithPath: "/tmp/cocxyd")
        )

        #expect(readiness == .helperHealthyButSurfaceBridgeUnavailable(hello))
        #expect(readiness.shouldUseInProcessEngine == true)
        #expect(readiness.diagnostic.contains("complete terminal engine capability"))
    }

    @Test("terminal-engine capable helper selects the daemon adapter path")
    func terminalEngineHelperSelectsDaemonAdapterPath() {
        let hello = PTYDaemonHello(
            version: "dev",
            capabilities: [
                PTYDaemonProtocol.jsonLinesCapability,
                PTYDaemonProtocol.terminalSurfaceCapability,
                PTYDaemonProtocol.terminalEngineCapability
            ]
        )
        let resolver = PTYDaemonReadinessResolver { _ in .success(hello) }

        let readiness = resolver.resolve(
            config: ExperimentalConfig(ptyDaemonEnabled: true),
            helperURL: URL(fileURLWithPath: "/tmp/cocxyd")
        )

        #expect(readiness == .terminalSurfaceBridgeAvailable(hello))
        #expect(readiness.shouldUseInProcessEngine == false)
        #expect(readiness.diagnostic.contains("PTYDaemonClient"))
    }
}
