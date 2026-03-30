// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SystemProxyConfigurator.swift - macOS system proxy integration via networksetup.

import Foundation

// MARK: - System Network Configuring Protocol

/// Abstraction for macOS `networksetup` operations.
///
/// Production implementation uses `Process` with `osascript` for admin privilege
/// escalation. Test implementation records commands without execution.
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
/// Saves the previous proxy configuration before applying changes
/// so it can be cleanly restored when the proxy is deactivated.
///
/// ## Security
///
/// `networksetup` requires admin privileges on macOS 14+.
/// The production `SystemNetworkConfigurator` uses `osascript` with
/// `"do shell script ... with administrator privileges"` to trigger
/// the native macOS admin password prompt.
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

    // MARK: - Dependencies

    private let networkConfigurator: any SystemNetworkConfiguring
    private let pacWriter: any PACFileWriting

    // MARK: - State

    private var savedState: SavedState?

    // MARK: - Initialization

    init(
        networkConfigurator: any SystemNetworkConfiguring,
        pacWriter: any PACFileWriting
    ) {
        self.networkConfigurator = networkConfigurator
        self.pacWriter = pacWriter
    }

    // MARK: - Activate

    /// Configures the system-wide proxy for the given interface.
    ///
    /// 1. Reads and saves the current proxy state for later restoration.
    /// 2. Sets the SOCKS proxy via `networksetup -setsocksfirewallproxy`.
    /// 3. Optionally sets the HTTP proxy via `networksetup -setwebproxy`.
    /// 4. Writes a PAC file for applications that support auto-configuration.
    ///
    /// - Parameters:
    ///   - interface: The network service name (e.g., "Wi-Fi").
    ///   - socksPort: Local SOCKS5 proxy port.
    ///   - httpPort: Local HTTP CONNECT proxy port (nil to skip).
    ///   - exclusions: Domains/IPs that should bypass the proxy.
    func activateProxy(
        interface: String,
        socksPort: Int,
        httpPort: Int?,
        exclusions: ProxyExclusionList
    ) throws {
        // Save current state for clean restore.
        savedState = try networkConfigurator.readCurrentProxyState(interface: interface)

        // Enable SOCKS proxy.
        try networkConfigurator.executeNetworkSetup(arguments: [
            "-setsocksfirewallproxy", interface, "127.0.0.1", "\(socksPort)"
        ])
        try networkConfigurator.executeNetworkSetup(arguments: [
            "-setsocksfirewallproxystate", interface, "on"
        ])

        // Enable HTTP proxy if port is specified.
        if let httpPort {
            try networkConfigurator.executeNetworkSetup(arguments: [
                "-setwebproxy", interface, "127.0.0.1", "\(httpPort)"
            ])
            try networkConfigurator.executeNetworkSetup(arguments: [
                "-setwebproxystate", interface, "on"
            ])
        }

        // Write PAC file.
        let pacContent = exclusions.generatePACContent(socksPort: socksPort)
        try pacWriter.writePACFile(content: pacContent, to: Self.defaultPACPath)
    }

    // MARK: - Deactivate

    /// Restores the proxy configuration to the state saved before activation.
    ///
    /// If no state was saved (proxy was never activated), this is a safe no-op.
    ///
    /// - Parameter interface: The network service name to restore.
    func deactivateProxy(interface: String) throws {
        guard let saved = savedState else { return }

        // Restore SOCKS proxy state.
        if saved.socksEnabled, let host = saved.socksHost, let port = saved.socksPort {
            try networkConfigurator.executeNetworkSetup(arguments: [
                "-setsocksfirewallproxy", interface, host, "\(port)"
            ])
        } else {
            try networkConfigurator.executeNetworkSetup(arguments: [
                "-setsocksfirewallproxystate", interface, "off"
            ])
        }

        // Restore web proxy state.
        if saved.webProxyEnabled, let host = saved.webProxyHost, let port = saved.webProxyPort {
            try networkConfigurator.executeNetworkSetup(arguments: [
                "-setwebproxy", interface, host, "\(port)"
            ])
        } else {
            try networkConfigurator.executeNetworkSetup(arguments: [
                "-setwebproxystate", interface, "off"
            ])
        }

        // Remove PAC file.
        try? pacWriter.removePACFile(at: Self.defaultPACPath)

        savedState = nil
    }
}

// MARK: - Production Network Configurator

/// Production implementation that uses real `networksetup` commands
/// with `osascript` for admin privilege escalation.
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

    func executeNetworkSetup(arguments: [String]) throws {
        let escapedArgs = arguments.map { "\"\($0)\"" }.joined(separator: " ")
        let script = "do shell script \"/usr/sbin/networksetup \(escapedArgs)\" with administrator privileges"

        let result = try runProcess(
            command: "/usr/bin/osascript",
            arguments: ["-e", script]
        )

        if result.contains("error") {
            throw ProxyError.systemProxyFailed(result)
        }
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
