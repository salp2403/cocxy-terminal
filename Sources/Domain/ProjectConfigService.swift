// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectConfigService.swift - Per-project config loading from .cocxy.toml.

import Foundation

// MARK: - Project Config

/// Partial configuration override loaded from a `.cocxy.toml` file.
///
/// All fields are optional. Only non-nil values override the global
/// `CocxyConfig`. This struct represents the v1 scope: UI-level
/// overrides that do not require recreating the terminal engine.
///
/// Supported overrides:
/// - Appearance: font-size, padding, opacity, blur
/// - Agent detection: extra launch patterns
/// - Keybindings: per-project shortcut overrides
///
/// Engine-level settings (theme, shell, cursor-style) are planned
/// for v2 and intentionally excluded here.
struct ProjectConfig: Codable, Equatable, Sendable {

    // MARK: - Appearance Overrides

    /// Font size override. Valid range: [6.0, 72.0].
    let fontSize: Double?

    /// Window padding override. Must be >= 0.
    let windowPadding: Double?

    /// Horizontal padding override. Overrides windowPadding for X axis.
    let windowPaddingX: Double?

    /// Vertical padding override. Overrides windowPadding for Y axis.
    let windowPaddingY: Double?

    /// Background opacity override. Valid range: [0.1, 1.0].
    let backgroundOpacity: Double?

    /// Background blur radius override. Valid range: [0, 100].
    let backgroundBlurRadius: Double?

    // MARK: - Agent Detection Overrides

    /// Additional launch patterns for agent detection.
    /// These are ADDED to the global patterns, not replacing them.
    let agentDetectionExtraPatterns: [String]?

    // MARK: - Keybinding Overrides

    /// Per-project keybinding overrides. Keys are TOML key names
    /// (e.g., "new-tab"), values are shortcut strings (e.g., "cmd+shift+t").
    /// Only specified keys override; unspecified keys keep global values.
    let keybindingOverrides: [String: String]?

    // MARK: - Worktree Overrides
    //
    // Introduced in v0.1.81 per feedback ajuste #1: a `.cocxy.toml` must
    // be able to control the per-agent worktree feature on a repo basis.
    // `basePath` and `idLength` stay global-only on purpose — the former
    // is a filesystem layout concern, the latter a collision/safety knob.

    /// Per-project override for the master `enabled` toggle. When set,
    /// wins over `WorktreeConfig.enabled` for tabs inside this project.
    let worktreeEnabled: Bool?

    /// Per-project override for `base-ref` (branch to check out from).
    let worktreeBaseRef: String?

    /// Per-project override for `branch-template`.
    let worktreeBranchTemplate: String?

    /// Per-project override for `on-close` behaviour.
    let worktreeOnClose: WorktreeOnClose?

    /// Per-project override for `open-in-new-tab`.
    let worktreeOpenInNewTab: Bool?

    /// Per-project override for `inherit-project-config` (whether to
    /// walk the origin repo as a fallback when resolving `.cocxy.toml`
    /// from inside a worktree).
    let worktreeInheritProjectConfig: Bool?

    /// Per-project override for `show-badge`.
    let worktreeShowBadge: Bool?

    // MARK: - GitHub Overrides (v0.1.84)
    //
    // Per-project controls for the GitHub pane. Only the toggles that
    // make sense per-repo are exposed — `autoRefreshInterval` and
    // `maxItems` stay global to avoid surprise swings when the user
    // changes projects.

    /// Per-project override for `[github].enabled`. Lets a repo opt
    /// out of the pane (e.g. monorepos without a GitHub remote).
    let githubEnabled: Bool?

    /// Per-project override for `[github].include-drafts`.
    let githubIncludeDrafts: Bool?

    /// Per-project override for `[github].default-state`. Validated
    /// against `GitHubConfig.allowedDefaultStates`; invalid values are
    /// ignored so the global setting wins.
    let githubDefaultState: String?

    /// Whether all fields are nil (no overrides).
    var isEmpty: Bool {
        fontSize == nil && windowPadding == nil && windowPaddingX == nil
            && windowPaddingY == nil && backgroundOpacity == nil
            && backgroundBlurRadius == nil && agentDetectionExtraPatterns == nil
            && keybindingOverrides == nil
            && worktreeEnabled == nil && worktreeBaseRef == nil
            && worktreeBranchTemplate == nil && worktreeOnClose == nil
            && worktreeOpenInNewTab == nil && worktreeInheritProjectConfig == nil
            && worktreeShowBadge == nil
            && githubEnabled == nil && githubIncludeDrafts == nil
            && githubDefaultState == nil
    }

    // MARK: - Initialization

    init(
        fontSize: Double? = nil,
        windowPadding: Double? = nil,
        windowPaddingX: Double? = nil,
        windowPaddingY: Double? = nil,
        backgroundOpacity: Double? = nil,
        backgroundBlurRadius: Double? = nil,
        agentDetectionExtraPatterns: [String]? = nil,
        keybindingOverrides: [String: String]? = nil,
        worktreeEnabled: Bool? = nil,
        worktreeBaseRef: String? = nil,
        worktreeBranchTemplate: String? = nil,
        worktreeOnClose: WorktreeOnClose? = nil,
        worktreeOpenInNewTab: Bool? = nil,
        worktreeInheritProjectConfig: Bool? = nil,
        worktreeShowBadge: Bool? = nil,
        githubEnabled: Bool? = nil,
        githubIncludeDrafts: Bool? = nil,
        githubDefaultState: String? = nil
    ) {
        self.fontSize = fontSize
        self.windowPadding = windowPadding
        self.windowPaddingX = windowPaddingX
        self.windowPaddingY = windowPaddingY
        self.backgroundOpacity = backgroundOpacity
        self.backgroundBlurRadius = backgroundBlurRadius
        self.agentDetectionExtraPatterns = agentDetectionExtraPatterns
        self.keybindingOverrides = keybindingOverrides
        self.worktreeEnabled = worktreeEnabled
        self.worktreeBaseRef = worktreeBaseRef
        self.worktreeBranchTemplate = worktreeBranchTemplate
        self.worktreeOnClose = worktreeOnClose
        self.worktreeOpenInNewTab = worktreeOpenInNewTab
        self.worktreeInheritProjectConfig = worktreeInheritProjectConfig
        self.worktreeShowBadge = worktreeShowBadge
        self.githubEnabled = githubEnabled
        self.githubIncludeDrafts = githubIncludeDrafts
        self.githubDefaultState = githubDefaultState
    }
}

// MARK: - Project Config Service

/// Finds and parses `.cocxy.toml` files for per-project configuration.
///
/// Walks up from a directory to find the nearest `.cocxy.toml`,
/// stopping at the user's home directory. Parses the file using
/// `TOMLParser` and returns a `ProjectConfig` with validated values.
final class ProjectConfigService {

    private let parser = TOMLParser()

    // MARK: - Public API

    /// Parses TOML content into a ProjectConfig.
    ///
    /// Returns nil if the content is empty, whitespace-only, malformed,
    /// or produces a config with all fields nil (nothing to override).
    func parse(_ tomlContent: String) -> ProjectConfig? {
        let trimmed = tomlContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parsed: [String: TOMLValue]
        do {
            parsed = try parser.parse(tomlContent)
        } catch {
            return nil
        }

        // Extract root-level appearance overrides
        let fontSize = doubleValue(parsed["font-size"]).map { clamp($0, min: 6.0, max: 72.0) }
        let windowPadding = doubleValue(parsed["window-padding"]).map { max(0.0, $0) }
        let windowPaddingX = doubleValue(parsed["window-padding-x"]).map { max(0.0, $0) }
        let windowPaddingY = doubleValue(parsed["window-padding-y"]).map { max(0.0, $0) }
        let backgroundOpacity = doubleValue(parsed["background-opacity"]).map { clamp($0, min: 0.1, max: 1.0) }
        let backgroundBlurRadius = doubleValue(parsed["background-blur-radius"]).map { clamp($0, min: 0.0, max: 100.0) }

        // Extract [agent-detection] table
        let agentTable = extractTable("agent-detection", from: parsed)
        let extraPatterns = extractStringArray(agentTable["extra-launch-patterns"])

        // Extract [keybindings] table
        let keybindingsTable = extractTable("keybindings", from: parsed)
        let keybindingOverrides: [String: String]? = keybindingsTable.isEmpty ? nil : {
            var result: [String: String] = [:]
            for (key, value) in keybindingsTable {
                if let str = stringValue(value) {
                    result[key] = str
                }
            }
            return result.isEmpty ? nil : result
        }()

        // Extract [worktree] table. Every field is optional on purpose —
        // a missing key means "inherit the global value", never "reset
        // to default". Unknown on-close values return nil so the global
        // value wins (never silently falling back to a hardcoded
        // destructive default at the project layer).
        let worktreeTable = extractTable("worktree", from: parsed)
        let worktreeEnabled = boolValue(worktreeTable["enabled"])
        let worktreeBaseRef = stringValue(worktreeTable["base-ref"])
        let worktreeBranchTemplate = stringValue(worktreeTable["branch-template"])
        let worktreeOnClose = stringValue(worktreeTable["on-close"])
            .flatMap(WorktreeOnClose.init(rawValue:))
        let worktreeOpenInNewTab = boolValue(worktreeTable["open-in-new-tab"])
        let worktreeInheritProjectConfig = boolValue(worktreeTable["inherit-project-config"])
        let worktreeShowBadge = boolValue(worktreeTable["show-badge"])

        // Extract [github] table. Mirrors the worktree pattern —
        // missing keys mean "inherit the global", unknown enum values
        // decode to nil so the global setting wins without surfacing
        // invalid user input as a silent override.
        let githubTable = extractTable("github", from: parsed)
        let githubEnabled = boolValue(githubTable["enabled"])
        let githubIncludeDrafts = boolValue(githubTable["include-drafts"])
        let githubDefaultState = stringValue(githubTable["default-state"])
            .map { $0.lowercased() }
            .flatMap { GitHubConfig.allowedDefaultStates.contains($0) ? $0 : nil }

        // Return nil if every field is nil (nothing to override)
        let config = ProjectConfig(
            fontSize: fontSize,
            windowPadding: windowPadding,
            windowPaddingX: windowPaddingX,
            windowPaddingY: windowPaddingY,
            backgroundOpacity: backgroundOpacity,
            backgroundBlurRadius: backgroundBlurRadius,
            agentDetectionExtraPatterns: extraPatterns,
            keybindingOverrides: keybindingOverrides,
            worktreeEnabled: worktreeEnabled,
            worktreeBaseRef: worktreeBaseRef,
            worktreeBranchTemplate: worktreeBranchTemplate,
            worktreeOnClose: worktreeOnClose,
            worktreeOpenInNewTab: worktreeOpenInNewTab,
            worktreeInheritProjectConfig: worktreeInheritProjectConfig,
            worktreeShowBadge: worktreeShowBadge,
            githubEnabled: githubEnabled,
            githubIncludeDrafts: githubIncludeDrafts,
            githubDefaultState: githubDefaultState
        )

        if config.isEmpty {
            return nil
        }

        return config
    }

    /// Extracts a boolean from a TOML value, returning `nil` for
    /// non-boolean values.
    private func boolValue(_ value: TOMLValue?) -> Bool? {
        guard case .boolean(let boolContent) = value else { return nil }
        return boolContent
    }

    /// Finds and loads a `.cocxy.toml` from the given directory or its parents.
    ///
    /// When `originRepo` is supplied and the direct walk from `directory`
    /// finds nothing, the walk is retried starting from `originRepo`.
    /// This lets a tab running inside a cocxy-managed git worktree
    /// (stored at e.g. `~/.cocxy/worktrees/<hash>/<id>/`) inherit the
    /// `.cocxy.toml` that lives inside the source repository. The caller
    /// is responsible for gating this fallback via
    /// `CocxyConfig.worktree.inheritProjectConfig` — passing `nil` for
    /// `originRepo` disables the fallback regardless of the user setting.
    ///
    /// Stops searching at the user's home directory on either branch.
    ///
    /// - Parameters:
    ///   - directory: Primary directory to walk (typically the tab's
    ///     working directory or worktree root).
    ///   - originRepo: Optional fallback directory walked only when the
    ///     primary walk returns nil. Defaults to `nil` for backwards
    ///     compatibility with existing call sites that do not have a
    ///     worktree origin concept.
    /// - Returns: The merged-ready overrides, or `nil` when neither walk
    ///   found a `.cocxy.toml`.
    func loadConfig(for directory: URL, originRepo: URL? = nil) -> ProjectConfig? {
        if let direct = loadConfigWalking(from: directory) {
            return direct
        }
        guard let originRepo,
              originRepo.standardizedFileURL != directory.standardizedFileURL else {
            return nil
        }
        return loadConfigWalking(from: originRepo)
    }

    /// Returns the path to the nearest `.cocxy.toml`, or nil if not found.
    ///
    /// Mirrors the fallback behaviour of `loadConfig(for:originRepo:)` so
    /// the `ProjectConfigWatcher` attached to the tab can observe the
    /// file that actually drives the tab's merged config — whether that
    /// file lives inside the worktree, inside the origin repo, or not
    /// at all. Callers must gate the fallback behind
    /// `config.worktree.inheritProjectConfig` exactly like they do for
    /// `loadConfig`.
    ///
    /// - Parameters:
    ///   - directory: Primary directory to walk.
    ///   - originRepo: Optional fallback directory (usually
    ///     `tab.worktreeOriginRepo`).
    /// - Returns: The path to the nearest `.cocxy.toml`, or `nil`.
    func findConfigPath(for directory: URL, originRepo: URL? = nil) -> String? {
        if let direct = findConfigPathWalking(from: directory) {
            return direct
        }
        guard let originRepo,
              originRepo.standardizedFileURL != directory.standardizedFileURL else {
            return nil
        }
        return findConfigPathWalking(from: originRepo)
    }

    /// Walks upward from `start` looking for a `.cocxy.toml`. Stops at
    /// the user's home directory or the filesystem root.
    private func loadConfigWalking(from start: URL) -> ProjectConfig? {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        var current = start.standardizedFileURL

        while true {
            let configFile = current.appendingPathComponent(".cocxy.toml")

            if fileManager.fileExists(atPath: configFile.path) {
                guard let content = try? String(contentsOf: configFile, encoding: .utf8) else {
                    return nil
                }
                return parse(content)
            }

            if current.path == homeDir.path { return nil }

            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    /// Walks upward from `start` looking for the path to the nearest
    /// `.cocxy.toml`. Returns the path without reading the file.
    private func findConfigPathWalking(from start: URL) -> String? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        var current = start.standardizedFileURL

        while true {
            let configPath = current.appendingPathComponent(".cocxy.toml")
            if fileManager.fileExists(atPath: configPath.path) {
                return configPath.path
            }

            if current.path == home.path { break }

            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    // MARK: - Value Extractors

    /// Extracts a string from a TOML value, returning nil for non-string values.
    private func stringValue(_ value: TOMLValue?) -> String? {
        guard case .string(let content) = value else { return nil }
        return content
    }

    /// Extracts a double from a TOML value.
    ///
    /// Accepts both `.float` and `.integer` TOML values, converting integers
    /// to doubles transparently.
    private func doubleValue(_ value: TOMLValue?) -> Double? {
        switch value {
        case .float(let content):
            return content
        case .integer(let content):
            return Double(content)
        default:
            return nil
        }
    }

    /// Extracts a table from the parsed TOML by section name.
    private func extractTable(
        _ sectionName: String,
        from parsed: [String: TOMLValue]
    ) -> [String: TOMLValue] {
        guard case .table(let table) = parsed[sectionName] else { return [:] }
        return table
    }

    /// Extracts an array of strings from a TOML value.
    ///
    /// Returns nil if the value is not an array or contains non-string elements.
    private func extractStringArray(_ value: TOMLValue?) -> [String]? {
        guard case .array(let items) = value else { return nil }
        var result: [String] = []
        for item in items {
            guard case .string(let str) = item else { return nil }
            result.append(str)
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - Validation Helpers

    /// Clamps a comparable value to a range.
    private func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        Swift.min(Swift.max(value, min), max)
    }
}
