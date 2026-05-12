// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ThemeImporter.swift - Local terminal theme import into Cocxy TOML.

import Foundation

struct ThemeImportResult: Sendable {
    let theme: Theme
    let fileURL: URL
}

struct ThemeImporter: Sendable {
    let destinationDirectory: URL

    init(destinationDirectory: URL = Self.defaultDestinationDirectory()) {
        self.destinationDirectory = destinationDirectory
    }

    func importExternalTheme(from sourceURL: URL) throws -> ThemeImportResult {
        let content = try String(contentsOf: sourceURL, encoding: .utf8)
        let displayName = ExternalTerminalThemeParser.displayName(
            in: content,
            fallback: Self.displayName(from: sourceURL)
        )
        let parsed = try ExternalTerminalThemeParser.parse(
            content,
            displayName: displayName,
            author: "Imported"
        )

        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        let fileURL = uniqueDestinationURL(for: parsed.metadata.name)
        let persistedTheme = Theme(
            metadata: ThemeMetadata(
                name: parsed.metadata.name,
                variant: parsed.metadata.variant,
                author: parsed.metadata.author,
                source: .custom(fileURL)
            ),
            palette: parsed.palette
        )
        try ThemeTomlWriter.render(persistedTheme).write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )

        return ThemeImportResult(theme: persistedTheme, fileURL: fileURL)
    }

    private func uniqueDestinationURL(for name: String) -> URL {
        let base = Self.slug(for: name)
        var candidate = destinationDirectory.appendingPathComponent("\(base).toml")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = destinationDirectory.appendingPathComponent("\(base)-\(index).toml")
            index += 1
        }
        return candidate
    }

    static func defaultDestinationDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/themes", isDirectory: true)
    }

    static func displayName(from url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .split(separator: "-")
            .map { token in
                token.prefix(1).uppercased() + token.dropFirst()
            }
            .joined(separator: " ")
    }

    static func slug(for name: String) -> String {
        var scalars: [Character] = []
        var previousWasSeparator = false
        for character in name.lowercased() {
            if character.isLetter || character.isNumber {
                scalars.append(character)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                scalars.append("-")
                previousWasSeparator = true
            }
        }
        let slug = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "theme" : slug
    }
}

enum ExternalTerminalThemeParser {
    static func parse(
        _ content: String,
        displayName: String,
        author: String?
    ) throws -> Theme {
        let values = parseKeyValues(content)

        let background = try requiredColor("background", values: values)
        let foreground = try requiredColor("foreground", values: values)
        let cursor = colorValue("cursor-color", values: values)
            ?? colorValue("cursor", values: values)
            ?? foreground
        let selectionBackground = colorValue("selection-background", values: values)
            ?? colorValue("selection", values: values)
            ?? background
        let selectionForeground = colorValue("selection-foreground", values: values)
            ?? foreground
        let ansi = try ansiColors(values: values)
        let variant: ThemeVariant = isDark(background) ? .dark : .light

        return Theme(
            metadata: ThemeMetadata(
                name: displayName,
                variant: variant,
                author: author,
                source: .legacyImport
            ),
            palette: ThemePalette(
                background: background,
                foreground: foreground,
                cursor: cursor,
                selectionBackground: selectionBackground,
                selectionForeground: selectionForeground,
                tabActiveBackground: background,
                tabActiveForeground: foreground,
                tabInactiveBackground: background,
                tabInactiveForeground: foreground,
                badgeAttention: ansi[3],
                badgeCompleted: ansi[2],
                badgeError: ansi[1],
                badgeWorking: ansi[4],
                ansiColors: ansi
            )
        )
    }

    static func displayName(in content: String, fallback: String) -> String {
        let values = parseKeyValues(content)
        if let name = values["name"]?.last, !name.isEmpty {
            return name
        }
        return fallback
    }

    private static func parseKeyValues(_ content: String) -> [String: [String]] {
        var values: [String: [String]] = [:]
        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            values[key, default: []].append(String(value))
        }
        return values
    }

    private static func requiredColor(
        _ key: String,
        values: [String: [String]]
    ) throws -> String {
        guard let color = colorValue(key, values: values) else {
            throw ThemeError.parseFailed(path: "<external>", reason: "Missing \(key)")
        }
        return color
    }

    private static func colorValue(
        _ key: String,
        values: [String: [String]]
    ) -> String? {
        values[key]?.last.flatMap(normalizedHex)
    }

    private static func ansiColors(values: [String: [String]]) throws -> [String] {
        var colors = Array(repeating: "", count: 16)
        for entry in values["palette"] ?? [] {
            let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let index = Int(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                  colors.indices.contains(index),
                  let color = normalizedHex(parts[1]) else {
                continue
            }
            colors[index] = color
        }
        guard colors.allSatisfy({ !$0.isEmpty }) else {
            throw ThemeError.parseFailed(path: "<external>", reason: "Missing palette entries 0-15")
        }
        return colors
    }

    private static func normalizedHex(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard raw.count == 6,
              raw.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return "#\(raw.lowercased())"
    }

    private static func isDark(_ hex: String) -> Bool {
        let raw = String(hex.dropFirst())
        guard raw.count == 6,
              let value = Int(raw, radix: 16) else {
            return true
        }
        let red = Double((value >> 16) & 0xff) / 255.0
        let green = Double((value >> 8) & 0xff) / 255.0
        let blue = Double(value & 0xff) / 255.0
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance < 0.5
    }
}

enum ThemeTomlWriter {
    static func render(_ theme: Theme) -> String {
        let ansi = paddedAnsi(theme.palette.ansiColors)
        return """
        [metadata]
        name = "\(escaped(theme.metadata.name))"
        author = "\(escaped(theme.metadata.author ?? "Imported"))"
        variant = "\(theme.metadata.variant.rawValue)"

        [colors]
        foreground = "\(theme.palette.foreground)"
        background = "\(theme.palette.background)"
        cursor = "\(theme.palette.cursor)"
        selection = "\(theme.palette.selectionBackground)"

        [colors.normal]
        black = "\(ansi[0])"
        red = "\(ansi[1])"
        green = "\(ansi[2])"
        yellow = "\(ansi[3])"
        blue = "\(ansi[4])"
        magenta = "\(ansi[5])"
        cyan = "\(ansi[6])"
        white = "\(ansi[7])"

        [colors.bright]
        black = "\(ansi[8])"
        red = "\(ansi[9])"
        green = "\(ansi[10])"
        yellow = "\(ansi[11])"
        blue = "\(ansi[12])"
        magenta = "\(ansi[13])"
        cyan = "\(ansi[14])"
        white = "\(ansi[15])"

        [ui]
        tab-active-background = "\(theme.palette.tabActiveBackground)"
        tab-inactive-background = "\(theme.palette.tabInactiveBackground)"
        tab-inactive-foreground = "\(theme.palette.tabInactiveForeground)"
        badge-attention = "\(theme.palette.badgeAttention)"
        badge-completed = "\(theme.palette.badgeCompleted)"
        badge-error = "\(theme.palette.badgeError)"
        badge-working = "\(theme.palette.badgeWorking)"
        """
    }

    private static func paddedAnsi(_ colors: [String]) -> [String] {
        if colors.count >= 16 {
            return Array(colors.prefix(16))
        }
        return colors + Array(repeating: "#000000", count: 16 - colors.count)
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
