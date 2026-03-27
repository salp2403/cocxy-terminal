// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteConnectionProfile.swift - Domain model for saved SSH connection profiles.

import Foundation

// MARK: - Remote Connection Profile

/// A saved SSH connection profile with all parameters needed to establish
/// and maintain a remote session.
///
/// Profiles are persisted as individual JSON files in `~/.config/cocxy/remotes/`
/// and can be organized into groups for logical grouping (e.g., "production",
/// "staging").
struct RemoteConnectionProfile: Identifiable, Codable, Equatable, Sendable {

    /// Unique identifier for this profile.
    let id: UUID

    /// Human-readable name for this profile (e.g., "prod-web-01").
    let name: String

    /// Remote host to connect to (hostname or IP address).
    let host: String

    /// SSH user name. When nil, SSH uses the current local user.
    let user: String?

    /// SSH port. When nil, defaults to 22.
    let port: Int?

    /// Path to the SSH identity file (private key).
    let identityFile: String?

    /// Ordered list of jump hosts for ProxyJump (-J flag).
    let jumpHosts: [String]

    /// Port forwarding rules to apply on connection.
    let portForwards: [PortForward]

    /// Logical group for organizing profiles (e.g., "production", "staging").
    let group: String?

    /// Environment variables to send to the remote host.
    let envVars: [String: String]

    /// Interval in seconds for SSH keep-alive packets.
    let keepAliveInterval: Int

    /// Whether to automatically reconnect on connection loss.
    let autoReconnect: Bool

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        user: String? = nil,
        port: Int? = nil,
        identityFile: String? = nil,
        jumpHosts: [String] = [],
        portForwards: [PortForward] = [],
        group: String? = nil,
        envVars: [String: String] = [:],
        keepAliveInterval: Int = 60,
        autoReconnect: Bool = true
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.jumpHosts = jumpHosts
        self.portForwards = portForwards
        self.group = group
        self.envVars = envVars
        self.keepAliveInterval = keepAliveInterval
        self.autoReconnect = autoReconnect
    }
}

// MARK: - Port Forward

extension RemoteConnectionProfile {

    /// Defines a port forwarding rule for an SSH connection.
    enum PortForward: Codable, Equatable, Sendable {

        /// Local port forward: binds a local port to a remote host:port.
        /// Equivalent to `ssh -L localPort:remoteHost:remotePort`.
        case local(localPort: Int, remotePort: Int, remoteHost: String = "localhost")

        /// Remote port forward: binds a remote port to a local host:port.
        /// Equivalent to `ssh -R remotePort:localHost:localPort`.
        case remote(remotePort: Int, localPort: Int, localHost: String = "localhost")

        /// Dynamic SOCKS proxy on the given local port.
        /// Equivalent to `ssh -D localPort`.
        case dynamic(localPort: Int)

        /// The SSH command-line flag for this port forward.
        var sshFlag: String {
            switch self {
            case let .local(localPort, remotePort, remoteHost):
                return "-L \(localPort):\(remoteHost):\(remotePort)"
            case let .remote(remotePort, localPort, localHost):
                return "-R \(remotePort):\(localHost):\(localPort)"
            case let .dynamic(localPort):
                return "-D \(localPort)"
            }
        }

        /// The local port number bound by this forward (for conflict detection).
        var boundLocalPort: Int? {
            switch self {
            case let .local(localPort, _, _):
                return localPort
            case .remote:
                return nil
            case let .dynamic(localPort):
                return localPort
            }
        }
    }
}

// MARK: - Display Helpers

extension RemoteConnectionProfile {

    /// Display string for the profile: "user@host:port" format.
    ///
    /// Omits the user when nil and the port when nil or 22 (default).
    var displayTitle: String {
        var result = ""
        if let user {
            result += "\(user)@"
        }
        result += host
        if let port, port != 22 {
            result += ":\(port)"
        }
        return result
    }

    /// Unique socket path for SSH ControlMaster multiplexing.
    ///
    /// Returns an absolute path by expanding the home directory.
    /// SSH ControlMaster requires a fully resolved path for socket files.
    var controlPath: String {
        let effectivePort = port ?? 22
        let home = NSHomeDirectory()
        if let user {
            return "\(home)/.config/cocxy/sockets/\(user)@\(host):\(effectivePort)"
        }
        return "\(home)/.config/cocxy/sockets/\(host):\(effectivePort)"
    }
}

// MARK: - SSH Command Generation

extension RemoteConnectionProfile {

    /// Builds a human-readable SSH command string with all configured flags.
    ///
    /// **Display only** -- not safe for direct shell execution.
    /// For actual connections, `SSHMultiplexer` constructs a properly-escaped
    /// argument array that handles paths with spaces and special characters.
    var sshCommand: String {
        var parts: [String] = ["ssh"]

        // Port.
        if let port {
            parts.append("-p \(port)")
        }

        // Identity file.
        if let identityFile {
            parts.append("-i \(identityFile)")
        }

        // Jump hosts.
        if !jumpHosts.isEmpty {
            parts.append("-J \(jumpHosts.joined(separator: ","))")
        }

        // Port forwards.
        for forward in portForwards {
            parts.append(forward.sshFlag)
        }

        // Keep-alive.
        parts.append("-o ServerAliveInterval=\(keepAliveInterval)")

        // Environment variables.
        for key in envVars.keys.sorted() {
            parts.append("-o SendEnv=\(key)")
        }

        // Destination (must be last).
        if let user {
            parts.append("\(user)@\(host)")
        } else {
            parts.append(host)
        }

        return parts.joined(separator: " ")
    }
}
