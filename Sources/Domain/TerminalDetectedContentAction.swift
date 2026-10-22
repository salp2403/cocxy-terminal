// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalDetectedContentAction.swift - Safe activation policy for detected terminal content.

import Foundation

enum TerminalDetectedContentAction: Equatable, Sendable {
    case openURL(URL)
    case openFile(URL, line: Int?, column: Int?)
    case copy(String)
}

enum TerminalDetectedContentActionResolver {
    static func resolve(
        _ content: TerminalDetectedContent,
        workingDirectory: URL?,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> TerminalDetectedContentAction? {
        let target = content.target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard target.isEmpty == false,
              target.utf8.count <= 4_096,
              target.rangeOfCharacter(from: .controlCharacters) == nil else {
            return nil
        }

        switch content.kind {
        case .url:
            return webURLAction(target)
        case .hyperlink:
            return explicitHyperlinkAction(
                target,
                line: content.line,
                column: content.column,
                workingDirectory: workingDirectory,
                fileExists: fileExists
            )
        case .filePath:
            return fileAction(
                target,
                line: content.line,
                column: content.column,
                workingDirectory: workingDirectory,
                fileExists: fileExists
            )
        case .ipAddress, .gitHash, .email:
            return .copy(target)
        }
    }

    private static func webURLAction(_ target: String) -> TerminalDetectedContentAction? {
        guard let components = URLComponents(string: target),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              let url = components.url else {
            return nil
        }
        return .openURL(url)
    }

    private static func explicitHyperlinkAction(
        _ target: String,
        line: Int?,
        column: Int?,
        workingDirectory: URL?,
        fileExists: (URL) -> Bool
    ) -> TerminalDetectedContentAction? {
        guard let components = URLComponents(string: target),
              let rawScheme = components.scheme else {
            return fileAction(
                target,
                line: line,
                column: column,
                workingDirectory: workingDirectory,
                fileExists: fileExists
            )
        }

        switch rawScheme.lowercased() {
        case "http", "https":
            return webURLAction(target)
        case "mailto":
            guard components.path.isEmpty == false, let url = components.url else { return nil }
            return .openURL(url)
        case "file":
            guard let url = components.url, url.isFileURL else { return nil }
            return existingFileAction(
                url.standardizedFileURL,
                line: line,
                column: column,
                fileExists: fileExists
            )
        default:
            return nil
        }
    }

    private static func fileAction(
        _ target: String,
        line: Int?,
        column: Int?,
        workingDirectory: URL?,
        fileExists: (URL) -> Bool
    ) -> TerminalDetectedContentAction? {
        let expanded = (target as NSString).expandingTildeInPath
        let url: URL
        if (expanded as NSString).isAbsolutePath {
            url = URL(fileURLWithPath: expanded).standardizedFileURL
        } else {
            guard let workingDirectory else { return nil }
            url = URL(
                fileURLWithPath: expanded,
                relativeTo: workingDirectory.standardizedFileURL
            ).standardizedFileURL
        }
        return existingFileAction(
            url,
            line: line,
            column: column,
            fileExists: fileExists
        )
    }

    private static func existingFileAction(
        _ url: URL,
        line: Int?,
        column: Int?,
        fileExists: (URL) -> Bool
    ) -> TerminalDetectedContentAction? {
        guard fileExists(url) else { return nil }
        return .openFile(
            url,
            line: line.flatMap { $0 > 0 ? $0 : nil },
            column: column.flatMap { $0 > 0 ? $0 : nil }
        )
    }
}
