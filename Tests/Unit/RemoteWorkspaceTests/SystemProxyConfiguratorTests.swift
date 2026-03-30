// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SystemProxyConfiguratorTests.swift - Tests for macOS system proxy integration.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Mock Network Configurator

/// Records `networksetup` commands without executing them.
@MainActor
final class MockNetworkConfigurator: SystemNetworkConfiguring {

    var executedCommands: [(command: String, arguments: [String])] = []
    var interfaceToReturn: String? = "Wi-Fi"
    var currentProxyState: SystemProxyConfigurator.SavedState?
    var shouldThrow = false

    func detectActiveInterface() throws -> String {
        if shouldThrow { throw ProxyError.systemProxyFailed("Detection failed") }
        guard let iface = interfaceToReturn else {
            throw ProxyError.systemProxyFailed("No active interface")
        }
        return iface
    }

    func executeNetworkSetup(arguments: [String]) throws {
        if shouldThrow { throw ProxyError.systemProxyFailed("Execution failed") }
        executedCommands.append((command: "networksetup", arguments: arguments))
    }

    func readCurrentProxyState(interface: String) throws -> SystemProxyConfigurator.SavedState {
        if let state = currentProxyState { return state }
        return SystemProxyConfigurator.SavedState(
            interface: interface,
            socksEnabled: false,
            socksHost: nil,
            socksPort: nil,
            webProxyEnabled: false,
            webProxyHost: nil,
            webProxyPort: nil
        )
    }
}

// MARK: - Mock PAC File Writer

/// Records PAC file write calls without filesystem access.
@MainActor
final class MockPACFileWriter: PACFileWriting {

    var writtenContent: String?
    var writtenPath: String?

    func writePACFile(content: String, to path: String) throws {
        writtenContent = content
        writtenPath = path
    }

    func removePACFile(at path: String) throws {
        writtenContent = nil
        writtenPath = nil
    }
}

// MARK: - SystemProxyConfigurator Tests

@Suite("SystemProxyConfigurator")
struct SystemProxyConfiguratorTests {

    // MARK: - Interface Detection

    @Test("detectActiveInterface returns interface name")
    @MainActor func detectInterface() throws {
        let configurator = MockNetworkConfigurator()
        let result = try configurator.detectActiveInterface()
        #expect(result == "Wi-Fi")
    }

    @Test("detectActiveInterface throws when no interface")
    @MainActor func detectInterfaceFailure() {
        let configurator = MockNetworkConfigurator()
        configurator.interfaceToReturn = nil
        #expect(throws: ProxyError.self) {
            _ = try configurator.detectActiveInterface()
        }
    }

    // MARK: - Activate Proxy

    @Test("activateProxy generates correct networksetup commands")
    @MainActor func activateProxy() throws {
        let networkConfig = MockNetworkConfigurator()
        let pacWriter = MockPACFileWriter()
        let proxy = SystemProxyConfigurator(
            networkConfigurator: networkConfig,
            pacWriter: pacWriter
        )

        try proxy.activateProxy(
            interface: "Wi-Fi",
            socksPort: 1080,
            httpPort: 8888,
            exclusions: ProxyExclusionList()
        )

        // Should have saved state + set SOCKS + set web proxy = at least 2 setup commands.
        #expect(networkConfig.executedCommands.count >= 2)

        let socksCmd = networkConfig.executedCommands.first {
            $0.arguments.contains("-setsocksfirewallproxy")
        }
        #expect(socksCmd != nil)
        #expect(socksCmd?.arguments.contains("1080") == true)

        let webCmd = networkConfig.executedCommands.first {
            $0.arguments.contains("-setwebproxy")
        }
        #expect(webCmd != nil)
        #expect(webCmd?.arguments.contains("8888") == true)
    }

    @Test("activateProxy writes PAC file")
    @MainActor func activateWritesPAC() throws {
        let networkConfig = MockNetworkConfigurator()
        let pacWriter = MockPACFileWriter()
        let proxy = SystemProxyConfigurator(
            networkConfigurator: networkConfig,
            pacWriter: pacWriter
        )

        try proxy.activateProxy(
            interface: "Wi-Fi",
            socksPort: 1080,
            httpPort: nil,
            exclusions: ProxyExclusionList()
        )

        #expect(pacWriter.writtenContent != nil)
        #expect(pacWriter.writtenContent?.contains("FindProxyForURL") == true)
    }

    // MARK: - Deactivate Proxy

    @Test("deactivateProxy restores saved state")
    @MainActor func deactivateRestoresState() throws {
        let networkConfig = MockNetworkConfigurator()
        let pacWriter = MockPACFileWriter()
        let proxy = SystemProxyConfigurator(
            networkConfigurator: networkConfig,
            pacWriter: pacWriter
        )

        // Activate first to save state.
        try proxy.activateProxy(
            interface: "Wi-Fi",
            socksPort: 1080,
            httpPort: nil,
            exclusions: ProxyExclusionList()
        )

        let commandsBefore = networkConfig.executedCommands.count
        try proxy.deactivateProxy(interface: "Wi-Fi")

        // Should have executed restore commands.
        #expect(networkConfig.executedCommands.count > commandsBefore)
    }

    @Test("deactivateProxy removes PAC file")
    @MainActor func deactivateRemovesPAC() throws {
        let networkConfig = MockNetworkConfigurator()
        let pacWriter = MockPACFileWriter()
        let proxy = SystemProxyConfigurator(
            networkConfigurator: networkConfig,
            pacWriter: pacWriter
        )

        try proxy.activateProxy(
            interface: "Wi-Fi",
            socksPort: 1080,
            httpPort: nil,
            exclusions: ProxyExclusionList()
        )

        try proxy.deactivateProxy(interface: "Wi-Fi")
        #expect(pacWriter.writtenContent == nil)
    }

    // MARK: - Safe Restore

    @Test("deactivateProxy without prior activate is safe no-op")
    @MainActor func deactivateWithoutActivate() throws {
        let networkConfig = MockNetworkConfigurator()
        let pacWriter = MockPACFileWriter()
        let proxy = SystemProxyConfigurator(
            networkConfigurator: networkConfig,
            pacWriter: pacWriter
        )

        // Should not throw even though there's no saved state.
        try proxy.deactivateProxy(interface: "Wi-Fi")
        #expect(networkConfig.executedCommands.isEmpty)
    }

    // MARK: - Saved State

    @Test("SavedState is Equatable")
    func savedStateEquality() {
        let a = SystemProxyConfigurator.SavedState(
            interface: "Wi-Fi",
            socksEnabled: false,
            socksHost: nil,
            socksPort: nil,
            webProxyEnabled: false,
            webProxyHost: nil,
            webProxyPort: nil
        )
        let b = a
        #expect(a == b)
    }
}
