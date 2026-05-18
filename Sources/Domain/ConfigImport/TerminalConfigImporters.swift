// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalConfigImporters.swift - Dry-run importers for external terminal configs.

import Foundation

enum TerminalConfigImportSource: String, CaseIterable, Codable, Sendable, Equatable {
    case ghostty
    case iterm2
    case alacritty
    case kitty
    case wezterm
}

struct TerminalConfigImportChange: Codable, Sendable, Equatable {
    let keyPath: String
    let value: String
    let sourceKey: String
}

struct TerminalConfigImportPreview: Codable, Sendable, Equatable {
    let source: TerminalConfigImportSource
    let sourcePath: String
    let changes: [TerminalConfigImportChange]
    let warnings: [String]
    let requiresBackupBeforeApply: Bool
}

protocol TerminalConfigImporting: Sendable {
    var source: TerminalConfigImportSource { get }

    func preview(contents: String, sourceURL: URL) throws -> TerminalConfigImportPreview
}

struct TerminalConfigImporterRegistry: Sendable {
    let importers: [TerminalConfigImportSource: any TerminalConfigImporting]

    init(importers: [TerminalConfigImportSource: any TerminalConfigImporting] = [
        .ghostty: GenericTerminalConfigImporter(source: .ghostty),
        .iterm2: ITerm2ConfigImporter(),
        .alacritty: GenericTerminalConfigImporter(source: .alacritty),
        .kitty: GenericTerminalConfigImporter(source: .kitty),
        .wezterm: GenericTerminalConfigImporter(source: .wezterm),
    ]) {
        self.importers = importers
    }

    var sources: [TerminalConfigImportSource] {
        TerminalConfigImportSource.allCases.filter { importers[$0] != nil }
    }

    func importer(for source: TerminalConfigImportSource) -> (any TerminalConfigImporting)? {
        importers[source]
    }
}

struct GenericTerminalConfigImporter: TerminalConfigImporting {
    let source: TerminalConfigImportSource

    func preview(contents: String, sourceURL: URL) throws -> TerminalConfigImportPreview {
        var changes: [TerminalConfigImportChange] = []
        var seenKeyPaths = Set<String>()

        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let pair = Self.keyValuePair(from: String(line), source: source),
                  let keyPath = Self.keyPath(for: pair.key, source: source),
                  !seenKeyPaths.contains(keyPath) else {
                continue
            }
            seenKeyPaths.insert(keyPath)
            changes.append(TerminalConfigImportChange(
                keyPath: keyPath,
                value: pair.value,
                sourceKey: pair.key
            ))
        }

        return TerminalConfigImportPreview(
            source: source,
            sourcePath: sourceURL.path,
            changes: changes,
            warnings: [],
            requiresBackupBeforeApply: true
        )
    }

    private static func keyValuePair(
        from line: String,
        source: TerminalConfigImportSource
    ) -> (key: String, value: String)? {
        let stripped = stripComment(line)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }

        let rawKey: String
        let rawValue: String
        if let separator = stripped.firstIndex(of: "=") {
            rawKey = String(stripped[..<separator])
            rawValue = String(stripped[stripped.index(after: separator)...])
        } else if let separator = stripped.firstIndex(of: ":") {
            rawKey = String(stripped[..<separator])
            rawValue = String(stripped[stripped.index(after: separator)...])
        } else if let separator = stripped.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            rawKey = String(stripped[..<separator])
            rawValue = String(stripped[separator...])
        } else {
            return nil
        }

        let key = normalizeKey(rawKey, source: source)
        let value = normalizeValue(rawValue, source: source)
        guard !key.isEmpty, !value.isEmpty else { return nil }
        return (key, value)
    }

    private static func stripComment(_ line: String) -> String {
        guard let comment = line.firstIndex(of: "#") else { return line }
        return String(line[..<comment])
    }

    private static func normalizeKey(_ key: String, source: TerminalConfigImportSource) -> String {
        var normalized = key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "config.", with: "")
            .replacingOccurrences(of: "window.", with: "")
            .replacingOccurrences(of: "font.normal.", with: "")
            .replacingOccurrences(of: "font.", with: "")
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()

        if source == .wezterm, normalized == "font" {
            normalized = "font_family"
        }
        return normalized
    }

    private static func normalizeValue(_ value: String, source: TerminalConfigImportSource) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comma = normalized.last, comma == "," {
            normalized.removeLast()
        }
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)

        if source == .wezterm,
           normalized.hasPrefix("wezterm.font("),
           normalized.hasSuffix(")") {
            normalized = String(normalized.dropFirst("wezterm.font(".count).dropLast())
        }

        while normalized.first == "\"" || normalized.first == "'" {
            normalized.removeFirst()
        }
        while normalized.last == "\"" || normalized.last == "'" {
            normalized.removeLast()
        }
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func keyPath(for key: String, source: TerminalConfigImportSource) -> String? {
        switch key {
        case "font_family", "font-family", "family":
            return "appearance.font-family"
        case "font_size", "font-size", "size":
            return "appearance.font-size"
        case "theme", "color_scheme":
            return "appearance.theme"
        case "cursor_style", "cursor_shape":
            return "terminal.cursor-style"
        case "background_opacity", "background-opacity", "opacity", "window_background_opacity":
            return "appearance.background-opacity"
        default:
            return nil
        }
    }
}

struct ITerm2ConfigImporter: TerminalConfigImporting {
    let source: TerminalConfigImportSource = .iterm2

    func preview(contents: String, sourceURL: URL) throws -> TerminalConfigImportPreview {
        let data = Data(contents.utf8)
        let decodedPlist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        let plist = decodedPlist as? [String: Any]
        var changes: [TerminalConfigImportChange] = []

        if let font = plist?["Normal Font"] as? String {
            let parts = font.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2 {
                changes.append(TerminalConfigImportChange(
                    keyPath: "appearance.font-family",
                    value: parts.dropLast().joined(separator: " "),
                    sourceKey: "Normal Font"
                ))
                changes.append(TerminalConfigImportChange(
                    keyPath: "appearance.font-size",
                    value: String(parts.last ?? ""),
                    sourceKey: "Normal Font"
                ))
            } else {
                changes.append(TerminalConfigImportChange(
                    keyPath: "appearance.font-family",
                    value: font,
                    sourceKey: "Normal Font"
                ))
            }
        }
        if let preset = plist?["Color Preset Name"] as? String, !preset.isEmpty {
            changes.append(TerminalConfigImportChange(
                keyPath: "appearance.theme",
                value: preset,
                sourceKey: "Color Preset Name"
            ))
        }

        return TerminalConfigImportPreview(
            source: source,
            sourcePath: sourceURL.path,
            changes: changes,
            warnings: [],
            requiresBackupBeforeApply: true
        )
    }
}
