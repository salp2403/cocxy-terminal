// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHSessionDetector.swift - Detects active SSH sessions in terminal output.

import Foundation

// MARK: - SSH Session Info

/// Information about a detected SSH connection.
struct SSHSessionInfo: Equatable, Codable, Sendable {
    /// The remote user name (e.g., "root", "deploy").
    let user: String?

    /// The remote host (e.g., "server.example.com", "192.168.1.50").
    let host: String

    /// The port number (nil means default 22).
    let port: Int?

    /// Whether a custom identity file was specified.
    let hasIdentityFile: Bool

    /// Additional SSH flags detected (e.g., "-A" for agent forwarding).
    let flags: [String]

    /// Display string for the tab title (e.g., "root@server.example.com").
    var displayTitle: String {
        if let user {
            return "\(user)@\(host)"
        }
        return host
    }

    /// Display string with port info (e.g., "root@server:2222").
    var displayTitleWithPort: String {
        guard let port, port != 22 else { return displayTitle }
        if let user {
            return "\(user)@\(host):\(port)"
        }
        return "\(host):\(port)"
    }
}

// MARK: - SSH Session Detector

/// Parses SSH commands from terminal process lists to detect remote sessions.
///
/// ## Detection Method
///
/// Monitors the foreground process name for the active terminal tab. When
/// the process is `ssh`, parses the command arguments to extract connection
/// details (user, host, port, flags).
///
/// ## Supported Formats
///
/// - `ssh host`
/// - `ssh user@host`
/// - `ssh -p 2222 host`
/// - `ssh user@host -p 2222`
/// - `ssh -i ~/.ssh/id_rsa user@host`
/// - `ssh -A -L 8080:localhost:80 user@host`
///
/// ## Port Forwarding Detection
///
/// Detects `-L` (local), `-R` (remote), and `-D` (dynamic) port forwarding
/// flags and includes them in the session info.
///
/// - SeeAlso: `Tab.processName` for the source of SSH detection triggers.
enum SSHSessionDetector {

    // MARK: - Detection

    /// Attempts to parse SSH session info from a command string.
    ///
    /// - Parameter command: The full SSH command (e.g., "ssh -p 22 user@host").
    /// - Returns: Parsed session info, or nil if the command is not an SSH invocation.
    static func detect(from command: String) -> SSHSessionInfo? {
        let tokens = tokenize(command)
        guard !tokens.isEmpty else { return nil }

        // First token must be "ssh" (possibly with path).
        let binary = tokens[0]
        guard binary == "ssh" || binary.hasSuffix("/ssh") else { return nil }

        var user: String?
        var host: String?
        var port: Int?
        var hasIdentityFile = false
        var flags: [String] = []

        var i = 1
        while i < tokens.count {
            let token = tokens[i]

            if token.hasPrefix("-") {
                switch token {
                case "-p":
                    // Port: -p <port>
                    if i + 1 < tokens.count, let p = Int(tokens[i + 1]) {
                        port = p
                        i += 1
                    }
                case "-i":
                    // Identity file: -i <path>
                    hasIdentityFile = true
                    i += 1 // Skip the path.
                case "-l":
                    // Login name: -l <user>
                    if i + 1 < tokens.count {
                        user = tokens[i + 1]
                        i += 1
                    }
                case "-L", "-R", "-D":
                    // Port forwarding flags.
                    flags.append(token)
                    if i + 1 < tokens.count, !tokens[i + 1].hasPrefix("-") {
                        i += 1 // Skip the forwarding spec.
                    }
                case "-o":
                    // Option: -o <key=value>
                    i += 1 // Skip the option value.
                default:
                    // Other flags (e.g., -A, -X, -v).
                    if token.count > 1 {
                        flags.append(token)
                    }
                }
            } else if host == nil {
                // This is the hostname (possibly user@host).
                let parsed = parseUserHost(token)
                user = user ?? parsed.user
                host = parsed.host
            }
            // Ignore remote command arguments after the host.

            i += 1
        }

        guard let detectedHost = host, !detectedHost.isEmpty else { return nil }

        return SSHSessionInfo(
            user: user,
            host: detectedHost,
            port: port,
            hasIdentityFile: hasIdentityFile,
            flags: flags
        )
    }

    /// Attempts to detect SSH from the process name only (no arguments).
    ///
    /// - Parameter processName: The foreground process name (e.g., "ssh").
    /// - Returns: `true` if the process appears to be an SSH client.
    static func isSSHProcess(_ processName: String) -> Bool {
        let name = processName.lowercased()
        return name == "ssh" || name == "sshpass" || name.hasSuffix("/ssh")
    }

    // MARK: - Parsing Helpers

    /// Splits a command into tokens, respecting quoted strings.
    private static func tokenize(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote: Character?

        for char in command {
            if let quote = inQuote {
                if char == quote {
                    inQuote = nil
                } else {
                    current.append(char)
                }
            } else if char == "\"" || char == "'" {
                inQuote = char
            } else if char == " " || char == "\t" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    /// Parses a "user@host" string into separate user and host components.
    private static func parseUserHost(_ token: String) -> (user: String?, host: String) {
        if let atIndex = token.firstIndex(of: "@") {
            let user = String(token[token.startIndex..<atIndex])
            let host = String(token[token.index(after: atIndex)...])
            return (user.isEmpty ? nil : user, host)
        }
        return (nil, token)
    }
}
