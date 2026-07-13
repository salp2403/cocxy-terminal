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
    private(set) var readStateCallCount = 0

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
        readStateCallCount += 1
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
    private(set) var writeCallCount = 0
    private(set) var removeCallCount = 0

    func writePACFile(content: String, to path: String) throws {
        writeCallCount += 1
        writtenContent = content
        writtenPath = path
    }

    func removePACFile(at path: String) throws {
        removeCallCount += 1
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

    @Test("production configurator rejects mutations before launching networksetup")
    @MainActor func productionConfiguratorRejectsMutations() {
        let configurator = SystemNetworkConfigurator()

        #expect(throws: ProxyError.self) {
            try configurator.executeNetworkSetup(arguments: [
                "-setsocksfirewallproxystate", "Wi-Fi", "on",
            ])
        }
    }

    @Test("activateProxy fails closed without commands or PAC side effects")
    @MainActor func activateProxyFailsClosed() {
        let networkConfig = MockNetworkConfigurator()
        let pacWriter = MockPACFileWriter()
        let proxy = SystemProxyConfigurator(
            networkConfigurator: networkConfig,
            pacWriter: pacWriter
        )

        for httpPort in [nil, 8_888] as [Int?] {
            #expect(throws: ProxyError.self) {
                try proxy.activateProxy(
                    interface: "Wi-Fi",
                    socksPort: 1_080,
                    httpPort: httpPort,
                    exclusions: ProxyExclusionList()
                )
            }
        }

        #expect(networkConfig.readStateCallCount == 0)
        #expect(networkConfig.executedCommands.isEmpty)
        #expect(pacWriter.writeCallCount == 0)
        #expect(pacWriter.removeCallCount == 0)
        #expect(pacWriter.writtenContent == nil)
    }

    // MARK: - Deactivate Proxy

    @Test("deactivateProxy removes legacy PAC without networksetup")
    @MainActor func deactivateRemovesPACWithoutCommands() throws {
        let networkConfig = MockNetworkConfigurator()
        let pacWriter = MockPACFileWriter()
        let proxy = SystemProxyConfigurator(
            networkConfigurator: networkConfig,
            pacWriter: pacWriter
        )

        try pacWriter.writePACFile(content: "legacy", to: SystemProxyConfigurator.defaultPACPath)

        try proxy.deactivateProxy(interface: "Wi-Fi")
        #expect(pacWriter.writtenContent == nil)
        #expect(pacWriter.removeCallCount == 1)
        #expect(networkConfig.readStateCallCount == 0)
        #expect(networkConfig.executedCommands.isEmpty)
    }

    // MARK: - Safe Restore

    @Test("deactivateProxy without prior activate is safe cleanup")
    @MainActor func deactivateWithoutActivate() throws {
        let networkConfig = MockNetworkConfigurator()
        let pacWriter = MockPACFileWriter()
        let proxy = SystemProxyConfigurator(
            networkConfigurator: networkConfig,
            pacWriter: pacWriter
        )

        try proxy.deactivateProxy(interface: "Wi-Fi")
        #expect(networkConfig.executedCommands.isEmpty)
        #expect(pacWriter.removeCallCount == 1)
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
