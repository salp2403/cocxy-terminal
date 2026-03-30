// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProxyExclusionList.swift - Domains and IPs that bypass the proxy.

import Foundation

// MARK: - Proxy Exclusion List

/// Manages a list of host patterns that should bypass the proxy.
///
/// Supports three wildcard formats:
/// - `*.domain.com` — matches any subdomain of domain.com
/// - `10.0.0.*` — matches any IP starting with the prefix
/// - `exact.host` — matches only the exact hostname
///
/// Default exclusions always include localhost variants and link-local addresses.
/// Custom exclusions are appended and persisted per profile.
struct ProxyExclusionList: Codable, Sendable, Equatable {

    /// Built-in exclusions that always apply regardless of configuration.
    static let defaultExclusions: [String] = [
        "localhost", "127.0.0.1", "::1", "*.local", "169.254.*"
    ]

    /// Combined list of default + custom exclusion patterns.
    let patterns: [String]

    /// Creates an exclusion list with optional custom patterns.
    ///
    /// - Parameter custom: Additional patterns beyond the defaults.
    init(custom: [String] = []) {
        self.patterns = Self.defaultExclusions + custom
    }

    // MARK: - Bypass Check

    /// Determines whether a host should bypass the proxy.
    ///
    /// Matching is case-insensitive. Supports wildcard prefix (`*.domain`)
    /// and wildcard suffix (`prefix.*`) patterns.
    ///
    /// - Parameter host: The hostname or IP address to check.
    /// - Returns: `true` if the host matches any exclusion pattern.
    func shouldBypass(_ host: String) -> Bool {
        let lowered = host.lowercased()
        return patterns.contains { pattern in
            matchWildcard(pattern: pattern.lowercased(), host: lowered)
        }
    }

    // MARK: - PAC File Generation

    /// Generates a PAC (Proxy Auto-Config) file content string.
    ///
    /// The generated JavaScript function routes excluded hosts directly
    /// and everything else through the SOCKS5 proxy.
    ///
    /// - Parameter socksPort: The local SOCKS5 proxy port.
    /// - Returns: A complete PAC file content string.
    func generatePACContent(socksPort: Int) -> String {
        let conditions = patterns.map { pattern -> String in
            if pattern.hasPrefix("*.") {
                let domain = String(pattern.dropFirst(2))
                return "    if (dnsDomainIs(host, \"\(domain)\")) return \"DIRECT\";"
            } else if pattern.contains("*") {
                return "    if (shExpMatch(host, \"\(pattern)\")) return \"DIRECT\";"
            } else {
                return "    if (host === \"\(pattern)\") return \"DIRECT\";"
            }
        }.joined(separator: "\n")

        return """
        function FindProxyForURL(url, host) {
        \(conditions)
            return "SOCKS5 127.0.0.1:\(socksPort); DIRECT";
        }
        """
    }

    // MARK: - Wildcard Matching

    /// Matches a host against a single wildcard pattern.
    ///
    /// - `*.domain` matches `sub.domain` but not `domain` alone.
    /// - `prefix.*` matches `prefix.123` and `prefix.` but not bare `prefix`.
    /// - Exact string matches are always checked first.
    private func matchWildcard(pattern: String, host: String) -> Bool {
        if pattern == host { return true }

        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(1)) // keeps the leading dot
            return host.hasSuffix(suffix)
        }

        if pattern.hasSuffix(".*") {
            let prefix = String(pattern.dropLast(2))
            return host.hasPrefix(prefix + ".")
        }

        return false
    }
}
