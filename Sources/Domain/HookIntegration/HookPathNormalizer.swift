// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

/// Canonical path normalization shared by hook-driven routing.
///
/// Both CWD and file-path comparisons must use the same normalization so
/// strict equality remains safe across macOS path spellings such as
/// `/tmp` vs `/private/tmp`, `file://` URLs, trailing slashes, and
/// incidental surrounding whitespace.
enum HookPathNormalizer {

    static func normalize(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = URL(string: trimmed), parsed.isFileURL {
            return normalize(parsed)
        }
        return normalize(URL(fileURLWithPath: trimmed))
    }

    static func normalize(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
