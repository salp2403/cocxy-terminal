// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ThemeFileProviding.swift - Abstraction for theme file access.

import Foundation

// MARK: - Theme File Providing Protocol

/// Abstraction over filesystem access for custom theme files.
///
/// Allows injecting test doubles that hold theme content in memory
/// instead of reading from disk.
protocol ThemeFileProviding: AnyObject {
    /// Lists all custom theme files with their content.
    ///
    /// - Returns: Array of tuples containing the filename and raw TOML content.
    func listCustomThemeFiles() -> [(name: String, content: String)]
}

// MARK: - Disk Theme File Provider

/// Production implementation that reads theme files from `~/.config/cocxy/themes/`.
final class DiskThemeFileProvider: ThemeFileProviding {

    private let themesDirectoryPath: String

    init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        themesDirectoryPath = "\(homeDirectory)/.config/cocxy/themes"
    }

    func listCustomThemeFiles() -> [(name: String, content: String)] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: themesDirectoryPath) else {
            return []
        }

        guard let files = try? fileManager.contentsOfDirectory(atPath: themesDirectoryPath) else {
            return []
        }

        return files
            .filter { $0.hasSuffix(".toml") }
            .compactMap { filename in
                let filePath = "\(themesDirectoryPath)/\(filename)"
                guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                    return nil
                }
                return (name: filename, content: content)
            }
    }
}
