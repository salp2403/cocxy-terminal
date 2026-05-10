// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CLIEnvironmentDiscovery.swift - Local discovery payloads for agents and scripts.

import Foundation

struct CLIIdentityPayload: Codable, Equatable {
    let schemaVersion: Int
    let name: String
    let displayName: String
    let version: String
    let bundleIdentifier: String
    let channel: String
    let devTag: String?
    let telemetry: String
    let backend: String
    let enabledFeatures: [String]
}

struct CLICapabilitiesPayload: Codable, Equatable {
    let schemaVersion: Int
    let application: String
    let version: String
    let bundleIdentifier: String
    let transports: [String]
    let capabilities: [CLIDiscoverableCapability]
}

struct CLIDiscoverableCapability: Codable, Equatable {
    let id: String
    let supported: Bool
    let enabledByDefault: Bool
    let summary: String
}

enum CLIEnvironmentDiscovery {
    static func identity(
        version: String = CLIArgumentParser.version,
        bundleIdentifier: String = CLIArgumentParser.bundleIdentifier
    ) -> CLIIdentityPayload {
        let channelInfo = channel(from: bundleIdentifier)
        return CLIIdentityPayload(
            schemaVersion: 1,
            name: "cocxy",
            displayName: "Cocxy Terminal",
            version: version,
            bundleIdentifier: bundleIdentifier,
            channel: channelInfo.channel,
            devTag: channelInfo.devTag,
            telemetry: "none",
            backend: "none",
            enabledFeatures: [
                "terminal",
                "tabs",
                "splits",
                "local-cli",
                "app-socket",
                "protocol-v2",
                "notebooks",
                "plugins",
                "command-signatures",
                "top-cli",
            ]
        )
    }

    static func capabilities(
        version: String = CLIArgumentParser.version,
        bundleIdentifier: String = CLIArgumentParser.bundleIdentifier
    ) -> CLICapabilitiesPayload {
        CLICapabilitiesPayload(
            schemaVersion: 2,
            application: "Cocxy Terminal",
            version: version,
            bundleIdentifier: bundleIdentifier,
            transports: [
                "local-cli",
                "app-socket",
                "terminal-protocol-v2",
            ],
            capabilities: [
                CLIDiscoverableCapability(
                    id: "terminal",
                    supported: true,
                    enabledByDefault: true,
                    summary: "Native terminal surfaces with tabs, panes, and CocxyCore rendering"
                ),
                CLIDiscoverableCapability(
                    id: "local-cli",
                    supported: true,
                    enabledByDefault: true,
                    summary: "Local CLI companion with JSON discovery commands"
                ),
                CLIDiscoverableCapability(
                    id: "app-socket",
                    supported: true,
                    enabledByDefault: true,
                    summary: "Local app socket for user-initiated automation"
                ),
                CLIDiscoverableCapability(
                    id: "protocol-v2",
                    supported: true,
                    enabledByDefault: true,
                    summary: "Structured terminal protocol diagnostics and messages"
                ),
                CLIDiscoverableCapability(
                    id: "mcp",
                    supported: true,
                    enabledByDefault: true,
                    summary: "Local MCP integration"
                ),
                CLIDiscoverableCapability(
                    id: "lsp",
                    supported: true,
                    enabledByDefault: false,
                    summary: "Native LSP client foundation"
                ),
                CLIDiscoverableCapability(
                    id: "voice",
                    supported: true,
                    enabledByDefault: false,
                    summary: "On-device speech input"
                ),
                CLIDiscoverableCapability(
                    id: "agent-mode",
                    supported: true,
                    enabledByDefault: false,
                    summary: "Local agent mode integration"
                ),
                CLIDiscoverableCapability(
                    id: "notebooks",
                    supported: true,
                    enabledByDefault: true,
                    summary: "Cocxy notebooks with Jupyter import and export"
                ),
                CLIDiscoverableCapability(
                    id: "plugins",
                    supported: true,
                    enabledByDefault: true,
                    summary: "Local plugin installation and signature verification"
                ),
                CLIDiscoverableCapability(
                    id: "command-signatures",
                    supported: true,
                    enabledByDefault: true,
                    summary: "Local signing and verification for trusted artifacts"
                ),
                CLIDiscoverableCapability(
                    id: "update-channels",
                    supported: true,
                    enabledByDefault: true,
                    summary: "Stable, preview, and nightly update channels"
                ),
                CLIDiscoverableCapability(
                    id: "worktrees",
                    supported: true,
                    enabledByDefault: false,
                    summary: "Managed git worktrees for local task isolation"
                ),
                CLIDiscoverableCapability(
                    id: "browser",
                    supported: true,
                    enabledByDefault: true,
                    summary: "Embedded browser automation through user-visible app surfaces"
                ),
                CLIDiscoverableCapability(
                    id: "image-paste",
                    supported: true,
                    enabledByDefault: true,
                    summary: "Terminal paste handoff for local image files"
                ),
                CLIDiscoverableCapability(
                    id: "high-fidelity-clipboard",
                    supported: true,
                    enabledByDefault: false,
                    summary: "Multi-type pasteboard capture and restore"
                ),
                CLIDiscoverableCapability(
                    id: "top-cli",
                    supported: true,
                    enabledByDefault: true,
                    summary: "Terminal top-style view for tabs, active process metrics, and agent state"
                ),
                CLIDiscoverableCapability(
                    id: "vault",
                    supported: false,
                    enabledByDefault: false,
                    summary: "External agent session vault is not complete yet"
                ),
            ]
        )
    }

    static func json<T: Encodable>(for payload: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    private static func channel(from bundleIdentifier: String) -> (channel: String, devTag: String?) {
        if bundleIdentifier.hasSuffix(".preview") {
            return ("preview", nil)
        }
        if bundleIdentifier.hasSuffix(".nightly") {
            return ("nightly", nil)
        }
        let marker = ".dev."
        if let range = bundleIdentifier.range(of: marker) {
            let tag = String(bundleIdentifier[range.upperBound...])
            return ("dev", tag.isEmpty ? nil : tag)
        }
        return ("stable", nil)
    }
}
