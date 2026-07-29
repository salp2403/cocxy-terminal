// Copyright (c) 2026 Said Arturo Lopez. MIT License.

/// Bounded root-level paths watched by Claude Code's `FileChanged` hook.
///
/// Watching the session directory itself causes Claude Code to recursively
/// traverse dependency trees before showing its prompt. Cocxy uses a native
/// workspace monitor for source files, while this matcher keeps a small hook
/// fallback for common manifests and repository configuration files.
public enum ClaudeFileChangedMatcher {
    public static let watchedRootFiles = [
        "package.json",
        "package-lock.json",
        "pnpm-lock.yaml",
        "yarn.lock",
        "bun.lock",
        "bun.lockb",
        "Package.swift",
        "Package.resolved",
        "Cargo.toml",
        "Cargo.lock",
        "go.mod",
        "go.sum",
        "pyproject.toml",
        "requirements.txt",
        "Pipfile",
        "Pipfile.lock",
        "poetry.lock",
        "Gemfile",
        "Gemfile.lock",
        "composer.json",
        "composer.lock",
        "build.zig",
        "build.zig.zon",
        "CMakeLists.txt",
        "Makefile",
        ".env",
        ".envrc",
        ".gitignore",
    ]

    public static let value = watchedRootFiles.joined(separator: "|")
}
