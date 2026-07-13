// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SystemProxyConfigurator.swift - macOS system proxy integration via networksetup.

import Foundation

// MARK: - System Network Configuring Protocol

/// Abstraction for macOS `networksetup` operations.
///
/// Production mutation is disabled until authenticated, transactional updates
/// are available. Test implementations can record attempted commands.
@MainActor
protocol SystemNetworkConfiguring: AnyObject {

    /// Detects the currently active network interface (e.g., "Wi-Fi", "Ethernet").
    func detectActiveInterface() throws -> String

    /// Executes a `networksetup` command with the given arguments.
    func executeNetworkSetup(arguments: [String]) throws

    /// Reads the current proxy configuration for the given interface.
    func readCurrentProxyState(interface: String) throws -> SystemProxyConfigurator.SavedState
}

// MARK: - PAC File Writing Protocol

/// Abstraction for PAC file I/O. Enables testing without filesystem access.
@MainActor
protocol PACFileWriting: AnyObject {
    func writePACFile(content: String, to path: String) throws
    func removePACFile(at path: String) throws
}

// MARK: - System Proxy Configurator

/// Manages macOS system-wide proxy settings.
///
/// ## Security
///
/// Activation is intentionally unavailable until authenticated sessions can
/// provide credentials over standard input and restore all changes as one
/// transaction. Failing before any state read or command prevents partial
/// system proxy configuration and interactive privilege escalation.
@MainActor
final class SystemProxyConfigurator {

    // MARK: - Saved State

    /// Captures the proxy configuration before Cocxy modifies it.
    struct SavedState: Equatable, Sendable {
        let interface: String
        let socksEnabled: Bool
        let socksHost: String?
        let socksPort: Int?
        let webProxyEnabled: Bool
        let webProxyHost: String?
        let webProxyPort: Int?
    }

    // MARK: - Constants

    /// Default path for the generated PAC file.
    static let defaultPACPath: String = {
        let home = NSHomeDirectory()
        return "\(home)/.config/cocxy/proxy.pac"
    }()

    static let activationUnavailableReason =
        "System proxy activation is unavailable until authenticated, transactional configuration is supported"

    // MARK: - Dependencies

    private let networkConfigurator: any SystemNetworkConfiguring
    private let pacWriter: any PACFileWriting

    // MARK: - Initialization

    init(
        networkConfigurator: any SystemNetworkConfiguring,
        pacWriter: any PACFileWriting
    ) {
        self.networkConfigurator = networkConfigurator
        self.pacWriter = pacWriter
    }

    // MARK: - Activate

    /// Rejects system-wide proxy activation without performing side effects.
    ///
    /// - Parameters:
    ///   - interface: The network service name (e.g., "Wi-Fi").
    ///   - socksPort: Local SOCKS5 proxy port.
    ///   - httpPort: Local HTTP CONNECT proxy port (nil to skip).
    ///   - exclusions: Domains/IPs that should bypass the proxy.
    func activateProxy(
        interface _: String,
        socksPort _: Int,
        httpPort _: Int?,
        exclusions _: ProxyExclusionList
    ) throws {
        throw ProxyError.systemProxyFailed(Self.activationUnavailableReason)
    }

    // MARK: - Deactivate

    /// Removes a legacy Cocxy PAC file without changing system network settings.
    ///
    /// - Parameter interface: Retained for API compatibility; no command is run.
    func deactivateProxy(interface _: String) throws {
        try pacWriter.removePACFile(at: Self.defaultPACPath)
    }
}

// MARK: - Production Network Configurator

/// Production implementation for read-only `networksetup` inspection.
/// Mutating commands fail before any process is launched.
@MainActor
final class SystemNetworkConfigurator: SystemNetworkConfiguring {

    func detectActiveInterface() throws -> String {
        let result = try runProcess(
            command: "/usr/sbin/networksetup",
            arguments: ["-listnetworkserviceorder"]
        )
        // Parse output to find the active interface.
        // The first non-disabled, non-asterisk service is typically active.
        let lines = result.split(separator: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("(") && !trimmed.contains("*") {
                // Extract service name between the index and closing paren content.
                if let nameStart = trimmed.firstIndex(of: ")") {
                    let name = trimmed[trimmed.index(after: nameStart)...]
                        .trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { return name }
                }
            }
        }
        throw ProxyError.systemProxyFailed("No active network interface found")
    }

    func executeNetworkSetup(arguments _: [String]) throws {
        throw ProxyError.systemProxyFailed(SystemProxyConfigurator.activationUnavailableReason)
    }

    func readCurrentProxyState(interface: String) throws -> SystemProxyConfigurator.SavedState {
        let socksOutput = try runProcess(
            command: "/usr/sbin/networksetup",
            arguments: ["-getsocksfirewallproxy", interface]
        )
        let webOutput = try runProcess(
            command: "/usr/sbin/networksetup",
            arguments: ["-getwebproxy", interface]
        )

        return SystemProxyConfigurator.SavedState(
            interface: interface,
            socksEnabled: socksOutput.contains("Yes"),
            socksHost: parseField("Server", from: socksOutput),
            socksPort: parseField("Port", from: socksOutput).flatMap(Int.init),
            webProxyEnabled: webOutput.contains("Yes"),
            webProxyHost: parseField("Server", from: webOutput),
            webProxyPort: parseField("Port", from: webOutput).flatMap(Int.init)
        )
    }

    // MARK: - Helpers

    private func runProcess(command: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parseField(_ field: String, from output: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(field + ":") {
                let value = trimmed.dropFirst(field.count + 1).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}

// MARK: - Production PAC File Writer

/// Production implementation that writes PAC files to disk.
@MainActor
final class DiskPACFileWriter: PACFileWriting {

    func writePACFile(content: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func removePACFile(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
