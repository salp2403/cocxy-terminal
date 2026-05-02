// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MCPResourceBridge.swift - Converts MCP resources into local Agent context text.

import Foundation

enum MCPResourceBridge {
    static func context(from resource: MCPResource, contents: [MCPResourceContent]) -> String {
        var lines = [
            "MCP resource: \(resource.name)",
            "URI: \(resource.uri)",
        ]
        if let mimeType = resource.mimeType {
            lines.append("MIME type: \(mimeType)")
        }
        if let description = resource.description, !description.isEmpty {
            lines.append("Description: \(description)")
        }

        let textBodies = contents.compactMap(\.text)
        if !textBodies.isEmpty {
            lines.append("")
            lines.append(contentsOf: textBodies)
        }
        return lines.joined(separator: "\n")
    }
}
