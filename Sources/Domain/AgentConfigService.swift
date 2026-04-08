// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentConfigService.swift - Loads, validates and caches agent detection config.

import Foundation
@preconcurrency import Combine

// MARK: - Agent Config File Providing Protocol

/// Abstraction over filesystem access for the agents.toml file.
///
/// Allows injecting test doubles that hold config content in memory
/// instead of reading from disk.
protocol AgentConfigFileProviding: AnyObject, Sendable {
    /// Reads the agents configuration file content.
    ///
    /// - Returns: The raw TOML string, or `nil` if the file does not exist.
    func readAgentConfigFile() -> String?

    /// Writes agents configuration content to the config file.
    ///
    /// Creates parent directories if needed.
    /// - Parameter content: The TOML string to write.
    /// - Throws: If the file cannot be written.
    func writeAgentConfigFile(_ content: String) throws
}

// MARK: - Disk Agent Config File Provider

/// Production implementation that reads/writes `~/.config/cocxy/agents.toml`.
final class DiskAgentConfigFileProvider: AgentConfigFileProviding {

    private let configDirectoryPath: String
    private let configFilePath: String

    init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        configDirectoryPath = "\(homeDirectory)/.config/cocxy"
        configFilePath = "\(configDirectoryPath)/agents.toml"
    }

    func readAgentConfigFile() -> String? {
        guard FileManager.default.fileExists(atPath: configFilePath) else {
            return nil
        }
        return try? String(contentsOfFile: configFilePath, encoding: .utf8)
    }

    func writeAgentConfigFile(_ content: String) throws {
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: configDirectoryPath) {
            try fileManager.createDirectory(
                atPath: configDirectoryPath,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        try content.write(
            toFile: configFilePath,
            atomically: true,
            encoding: .utf8
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configFilePath
        )
    }
}

// MARK: - Agent Config Service

/// Service that loads, validates and caches agent detection configuration.
///
/// Reads `~/.config/cocxy/agents.toml`, parses it using `TOMLParser`,
/// validates all regex patterns, and caches compiled `NSRegularExpression`
/// instances. If the file does not exist, creates a default with the
/// built-in agent definitions.
///
/// Publishes changes via Combine for hot-reload support.
///
/// - SeeAlso: ADR-004 (Agent detection strategy)
/// - SeeAlso: `AgentConfig`, `CompiledAgentConfig`
final class AgentConfigService {

    enum ReloadError: Error {
        case missingFile
        case invalidToml
    }

    // MARK: - Properties

    private let fileProvider: AgentConfigFileProviding
    private let parser: TOMLParser
    private let configSubject: CurrentValueSubject<[CompiledAgentConfig], Never>

    /// The current list of compiled agent configurations.
    var currentConfigs: [CompiledAgentConfig] {
        configSubject.value
    }

    /// Publisher that emits the new agent configs whenever they change.
    var configChangedPublisher: AnyPublisher<[CompiledAgentConfig], Never> {
        configSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    /// Creates an AgentConfigService with a custom file provider.
    ///
    /// - Parameter fileProvider: The source of agent config file content.
    ///   Defaults to `DiskAgentConfigFileProvider` for production use.
    init(fileProvider: AgentConfigFileProviding = DiskAgentConfigFileProvider()) {
        self.fileProvider = fileProvider
        self.parser = TOMLParser()
        self.configSubject = CurrentValueSubject([])
    }

    // MARK: - Loading

    /// Forces an immediate reload from disk.
    ///
    /// If the agents.toml file does not exist, writes a default file and
    /// uses the built-in agent definitions. If the file is malformed,
    /// falls back to defaults.
    ///
    /// - Throws: `ConfigError.writeFailed` if the default file cannot be written.
    func reload() throws {
        guard let rawContent = fileProvider.readAgentConfigFile() else {
            try createDefaultAgentConfigFile()
            let defaults = AgentConfigService.defaultAgentConfigs()
            let compiled = defaults.map { AgentConfigService.compile($0) }
            configSubject.send(compiled)
            return
        }

        let configs = parseAgentConfigs(rawContent)
        let compiled = configs.map { AgentConfigService.compile($0) }
        configSubject.send(compiled)
    }

    /// Reloads agent configs only when the on-disk file exists and parses cleanly.
    ///
    /// Used by hot-reload watchers so malformed edits do not silently replace the
    /// current runtime configuration with defaults. On failure, the existing
    /// compiled configs remain untouched and the caller can surface the reload
    /// error to the user.
    func reloadIfValid() throws {
        guard let rawContent = fileProvider.readAgentConfigFile() else {
            throw ReloadError.missingFile
        }

        let configs = try parseAgentConfigsOrThrow(rawContent)
        let compiled = configs.map { AgentConfigService.compile($0) }
        configSubject.send(compiled)
    }

    // MARK: - Public Queries

    /// Returns all agent configurations (non-compiled).
    func agentConfigs() -> [AgentConfig] {
        configSubject.value.map { $0.config }
    }

    /// Returns the configuration for a specific agent by name.
    ///
    /// - Parameter name: The agent identifier (e.g., "claude").
    /// - Returns: The agent config, or `nil` if not found.
    func agentConfig(named name: String) -> AgentConfig? {
        configSubject.value.first { $0.config.name == name }?.config
    }

    /// Returns the compiled configuration for a specific agent by name.
    ///
    /// - Parameter name: The agent identifier (e.g., "claude").
    /// - Returns: The compiled agent config, or `nil` if not found.
    func compiledAgentConfig(named name: String) -> CompiledAgentConfig? {
        configSubject.value.first { $0.config.name == name }
    }

    // MARK: - Default Config

    /// Returns the built-in default agent configurations.
    static func defaultAgentConfigs() -> [AgentConfig] {
        [
            AgentConfig(
                name: "claude",
                displayName: "Claude Code",
                launchPatterns: ["^claude\\b", "^claude-code\\b", "npx claude"],
                waitingPatterns: ["^\\? ", "\\(Y/n\\)", "\\(y/N\\)", "Do you want to", "Would you like"],
                errorPatterns: ["^Error:", "^error\\[", "APIError", "Rate limit"],
                finishedIndicators: ["^\\$\\s*$", "^❯\\s*$", "^>\\s*$"],
                oscSupported: true,
                idleTimeoutOverride: nil
            ),
            AgentConfig(
                name: "codex",
                displayName: "Codex CLI",
                launchPatterns: ["^codex\\b"],
                waitingPatterns: ["\\? ", "Enter to confirm"],
                errorPatterns: ["Error:", "Failed"],
                finishedIndicators: ["^\\$\\s*$"],
                oscSupported: false,
                idleTimeoutOverride: nil
            ),
            AgentConfig(
                name: "aider",
                displayName: "Aider",
                launchPatterns: ["^aider(?:\\s|$)", "^python.*aider"],
                waitingPatterns: ["^>\\s*$", "^aider>\\s*$"],
                errorPatterns: ["Error:", "Exception:", "Traceback"],
                finishedIndicators: ["^\\$\\s*$"],
                oscSupported: false,
                idleTimeoutOverride: 10  // Aider is slower
            ),
            AgentConfig(
                name: "gemini-cli",
                displayName: "Gemini CLI",
                launchPatterns: ["^gemini\\b"],
                waitingPatterns: ["^>\\s*$", "Enter your prompt"],
                errorPatterns: ["Error:", "Failed"],
                finishedIndicators: ["^\\$\\s*$"],
                oscSupported: false,
                idleTimeoutOverride: 8  // Gemini can be slow on first response
            ),
            AgentConfig(
                name: "kiro",
                displayName: "Kiro",
                launchPatterns: ["^kiro\\b"],
                waitingPatterns: ["\\? "],
                errorPatterns: ["Error:"],
                finishedIndicators: ["^\\$\\s*$"],
                oscSupported: false,
                idleTimeoutOverride: nil
            ),
            AgentConfig(
                name: "opencode",
                displayName: "OpenCode",
                launchPatterns: ["^opencode\\b"],
                waitingPatterns: ["^>\\s*$"],
                errorPatterns: ["Error:"],
                finishedIndicators: ["^\\$\\s*$"],
                oscSupported: false,
                idleTimeoutOverride: nil
            ),
        ]
    }

    /// Generates the default agents.toml content.
    ///
    /// Used both for creating the initial file and for tests.
    static func generateDefaultAgentsToml() -> String {
        let configs = defaultAgentConfigs()
        var lines: [String] = ["# Cocxy Terminal - Agent Detection Configuration", ""]

        for config in configs {
            lines.append("[\(config.name)]")
            lines.append("display-name = \"\(config.displayName)\"")
            lines.append("osc-supported = \(config.oscSupported)")
            lines.append("launch-patterns = [\(formatPatternArray(config.launchPatterns))]")
            lines.append("waiting-patterns = [\(formatPatternArray(config.waitingPatterns))]")
            lines.append("error-patterns = [\(formatPatternArray(config.errorPatterns))]")
            lines.append("finished-indicators = [\(formatPatternArray(config.finishedIndicators))]")
            if let timeout = config.idleTimeoutOverride {
                lines.append("idle-timeout-override = \(Int(timeout))")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    /// Creates the default agents.toml file via the file provider.
    private func createDefaultAgentConfigFile() throws {
        let defaultToml = AgentConfigService.generateDefaultAgentsToml()
        try fileProvider.writeAgentConfigFile(defaultToml)
    }

    /// Parses TOML content into a list of `AgentConfig` values.
    ///
    /// Each top-level table in the TOML becomes one agent config.
    /// Invalid or incomplete agent definitions are skipped.
    private func parseAgentConfigs(_ rawContent: String) -> [AgentConfig] {
        do {
            return try parseAgentConfigsOrThrow(rawContent)
        } catch {
            // Malformed TOML: fall back to defaults during cold load.
            return AgentConfigService.defaultAgentConfigs()
        }
    }

    private func parseAgentConfigsOrThrow(_ rawContent: String) throws -> [AgentConfig] {
        let parsed: [String: TOMLValue]
        do {
            parsed = try parser.parse(rawContent)
        } catch {
            throw ReloadError.invalidToml
        }

        return buildAgentConfigs(from: parsed)
    }

    private func buildAgentConfigs(from parsed: [String: TOMLValue]) -> [AgentConfig] {
        var configs: [AgentConfig] = []

        for (key, value) in parsed {
            guard case .table(let table) = value else {
                continue
            }

            let displayName = extractString(table["display-name"]) ?? key
            let oscSupported = extractBool(table["osc-supported"]) ?? false
            let launchPatterns = extractStringArray(table["launch-patterns"]) ?? []
            let waitingPatterns = extractStringArray(table["waiting-patterns"]) ?? []
            let errorPatterns = extractStringArray(table["error-patterns"]) ?? []
            let finishedIndicators = extractStringArray(table["finished-indicators"]) ?? []
            let idleTimeoutOverride = extractInt(table["idle-timeout-override"])
                .map { TimeInterval($0) }

            let config = AgentConfig(
                name: key,
                displayName: displayName,
                launchPatterns: launchPatterns,
                waitingPatterns: waitingPatterns,
                errorPatterns: errorPatterns,
                finishedIndicators: finishedIndicators,
                oscSupported: oscSupported,
                idleTimeoutOverride: idleTimeoutOverride
            )

            configs.append(config)
        }

        return configs.sorted { $0.name < $1.name }
    }

    /// Compiles an `AgentConfig` into a `CompiledAgentConfig` with cached regex.
    ///
    /// Invalid patterns are collected in `invalidPatterns` and excluded
    /// from the compiled arrays. This ensures one bad pattern does not
    /// prevent the rest from working.
    static func compile(_ config: AgentConfig) -> CompiledAgentConfig {
        var invalidPatterns: [String] = []

        let launch = compilePatterns(config.launchPatterns, invalid: &invalidPatterns)
        let waiting = compilePatterns(config.waitingPatterns, invalid: &invalidPatterns)
        let errors = compilePatterns(config.errorPatterns, invalid: &invalidPatterns)
        let finished = compilePatterns(config.finishedIndicators, invalid: &invalidPatterns)

        return CompiledAgentConfig(
            config: config,
            launchPatterns: launch.regexes,
            launchMatchers: launch.matchers,
            waitingPatterns: waiting.regexes,
            waitingMatchers: waiting.matchers,
            errorPatterns: errors.regexes,
            errorMatchers: errors.matchers,
            finishedIndicators: finished.regexes,
            finishedMatchers: finished.matchers,
            invalidPatterns: invalidPatterns
        )
    }

    /// Compiles an array of pattern strings into `NSRegularExpression` instances.
    ///
    /// Patterns that fail to compile are appended to `invalid` and excluded
    /// from the returned array.
    private static func compilePatterns(
        _ patterns: [String],
        invalid: inout [String]
    ) -> (regexes: [NSRegularExpression], matchers: [CompiledPatternMatcher]) {
        var compiled: [NSRegularExpression] = []
        var matchers: [CompiledPatternMatcher] = []

        for pattern in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                compiled.append(regex)
                matchers.append(makeMatcher(from: pattern, regex: regex))
            } catch {
                invalid.append(pattern)
            }
        }

        return (compiled, matchers)
    }

    private static func makeMatcher(
        from pattern: String,
        regex: NSRegularExpression
    ) -> CompiledPatternMatcher {
        if let literal = parseTrimmedEqualsPattern(pattern) {
            return .trimmedEquals(literal)
        }
        if let segments = parseAnchoredOrderedSegments(pattern, separator: ".*") {
            return .orderedContainsPrefix(segments)
        }
        if let segments = parseAnchoredOrderedSegments(pattern, separator: "\\s+") {
            return .whitespaceSeparatedPrefix(segments)
        }
        if let literal = parseAnchoredWordPrefix(pattern) {
            return .prefixWord(literal)
        }
        if let literal = parseAnchoredPrefix(pattern) {
            return .prefix(literal)
        }
        if let segments = parseOrderedSegments(pattern, separator: ".*") {
            return .orderedContains(segments)
        }
        if let segments = parseOrderedSegments(pattern, separator: "\\s+") {
            return .whitespaceSeparated(segments)
        }
        if let literal = parseLiteralPattern(pattern) {
            return .literal(literal)
        }
        return .regex(regex)
    }

    private static func parseTrimmedEqualsPattern(_ pattern: String) -> String? {
        guard pattern.hasPrefix("^"), pattern.hasSuffix("\\s*$") else { return nil }
        let start = pattern.index(after: pattern.startIndex)
        let end = pattern.index(pattern.endIndex, offsetBy: -4)
        return parseLiteralSegment(pattern[start..<end])
    }

    private static func parseAnchoredWordPrefix(_ pattern: String) -> String? {
        guard pattern.hasPrefix("^"), pattern.hasSuffix("\\b") else { return nil }
        let start = pattern.index(after: pattern.startIndex)
        let end = pattern.index(pattern.endIndex, offsetBy: -2)
        return parseLiteralSegment(pattern[start..<end])
    }

    private static func parseAnchoredPrefix(_ pattern: String) -> String? {
        guard pattern.hasPrefix("^") else { return nil }
        return parseLiteralSegment(pattern.dropFirst())
    }

    private static func parseLiteralPattern(_ pattern: String) -> String? {
        parseLiteralSegment(pattern[...])
    }

    private static func parseAnchoredOrderedSegments(
        _ pattern: String,
        separator: String
    ) -> [String]? {
        guard pattern.hasPrefix("^") else { return nil }
        return parseOrderedSegments(String(pattern.dropFirst()), separator: separator)
    }

    private static func parseOrderedSegments(
        _ pattern: String,
        separator: String
    ) -> [String]? {
        let segments = pattern.components(separatedBy: separator)
        guard segments.count >= 2 else { return nil }

        let parsed = segments.compactMap(parseLiteralSegment)
        guard parsed.count == segments.count, parsed.allSatisfy({ !$0.isEmpty }) else { return nil }
        return parsed
    }

    private static func parseLiteralSegment<S: StringProtocol>(_ segment: S) -> String? {
        let regexMetacharacters: Set<Character> = ["^", "$", "*", "+", "?", ".", "(", ")", "[", "]", "{", "}", "|"]
        var literal = ""
        var isEscaped = false

        for character in segment {
            if isEscaped {
                switch character {
                case "\\", "^", "$", "*", "+", "?", ".", "(", ")", "[", "]", "{", "}", "|":
                    literal.append(character)
                default:
                    return nil
                }
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            if regexMetacharacters.contains(character) {
                return nil
            }

            literal.append(character)
        }

        return isEscaped ? nil : literal
    }

    // MARK: - Value Extractors

    /// Extracts a string from a TOML value.
    private func extractString(_ value: TOMLValue?) -> String? {
        guard case .string(let content) = value else { return nil }
        return content
    }

    /// Extracts a boolean from a TOML value.
    private func extractBool(_ value: TOMLValue?) -> Bool? {
        guard case .boolean(let content) = value else { return nil }
        return content
    }

    /// Extracts an integer from a TOML value.
    private func extractInt(_ value: TOMLValue?) -> Int? {
        guard case .integer(let content) = value else { return nil }
        return content
    }

    /// Extracts an array of strings from a TOML value.
    ///
    /// Returns `nil` if the value is not an array. Non-string elements
    /// within the array are silently skipped.
    private func extractStringArray(_ value: TOMLValue?) -> [String]? {
        guard case .array(let elements) = value else { return nil }
        return elements.compactMap { element in
            guard case .string(let content) = element else { return nil }
            return content
        }
    }

    /// Formats an array of pattern strings for TOML output.
    ///
    /// Uses TOML literal strings (single-quoted) so backslashes in regex
    /// patterns like `\b` (word boundary) are preserved verbatim. This is
    /// forward-compatible with any TOML parser, including spec-compliant ones.
    private static func formatPatternArray(_ patterns: [String]) -> String {
        patterns.map { "'\($0)'" }.joined(separator: ", ")
    }
}
