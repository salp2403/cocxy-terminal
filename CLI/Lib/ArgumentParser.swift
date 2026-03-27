// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ArgumentParser.swift - Manual CLI argument parsing (zero dependencies).

import Foundation

// MARK: - Parsed Command

/// The result of parsing CLI arguments into a concrete command and its parameters.
///
/// This type decouples argument parsing from socket communication,
/// making both independently testable.
public enum ParsedCommand: Equatable {

    // MARK: - Original commands (v1)

    /// `cocxy notify <message>`
    case notify(message: String)

    /// `cocxy new-tab [--dir <path>]`
    case newTab(directory: String?)

    /// `cocxy list-tabs`
    case listTabs

    /// `cocxy focus-tab <id>`
    case focusTab(id: String)

    /// `cocxy close-tab <id>`
    case closeTab(id: String)

    /// `cocxy split [--dir h|v]`
    case split(direction: SplitDirection?)

    /// `cocxy status`
    case status

    /// `cocxy hooks install`
    case hooksInstall

    /// `cocxy hooks uninstall`
    case hooksUninstall

    /// `cocxy hooks status`
    case hooksStatus

    /// `cocxy hook-handler` (reads JSON from stdin)
    case hookHandler

    /// `cocxy --help` or `cocxy help`
    case help

    /// `cocxy --version`
    case version

    // MARK: - Tab extended (v2)

    /// `cocxy tab rename <id> <name>`
    case tabRename(id: String, name: String)

    /// `cocxy tab move <id> <position>`
    case tabMove(id: String, position: String)

    // MARK: - Split extended (v2)

    /// `cocxy split list`
    case splitList

    /// `cocxy split focus <direction>`
    case splitFocus(direction: String)

    /// `cocxy split close`
    case splitClose

    /// `cocxy split resize <direction> <px>`
    case splitResize(direction: String, pixels: String)

    // MARK: - Dashboard (v2)

    /// `cocxy dashboard show`
    case dashboardShow

    /// `cocxy dashboard hide`
    case dashboardHide

    /// `cocxy dashboard toggle`
    case dashboardToggle

    /// `cocxy dashboard status`
    case dashboardStatus

    // MARK: - Timeline (v2)

    /// `cocxy timeline show <tab-id>`
    case timelineShow(tabID: String)

    /// `cocxy timeline export <tab-id> [--format json|md]`
    case timelineExport(tabID: String, format: String)

    // MARK: - Search (v2)

    /// `cocxy search <query> [--regex] [--case-sensitive] [--tab <id>]`
    case search(query: String, regex: Bool, caseSensitive: Bool, tabID: String?)

    // MARK: - Config (v2)

    /// `cocxy config get <key>`
    case configGet(key: String)

    /// `cocxy config set <key> <value>`
    case configSet(key: String, value: String)

    /// `cocxy config path`
    case configPath

    // MARK: - Theme (v2)

    /// `cocxy theme list`
    case themeList

    /// `cocxy theme set <name>`
    case themeSet(name: String)

    // MARK: - System (v2)

    /// `cocxy send <text>`
    case send(text: String)

    /// `cocxy send-key <key>`
    case sendKey(key: String)
}

// MARK: - Split Direction

/// The direction for a split pane command.
public enum SplitDirection: String, Equatable {
    case horizontal = "h"
    case vertical = "v"
}

// MARK: - Argument Parser

/// Parses `CommandLine.arguments` into a `ParsedCommand`.
///
/// Zero external dependencies. Handles all known subcommands,
/// flags, and error cases manually.
public enum CLIArgumentParser {

    /// The current CLI version string.
    public static let version = "0.1.0-alpha"

    /// Parses command-line arguments into a `ParsedCommand`.
    ///
    /// - Parameter arguments: The arguments array (excluding the program name).
    ///   Typically `Array(CommandLine.arguments.dropFirst())`.
    /// - Returns: A parsed command.
    /// - Throws: `CLIError` if the arguments are invalid.
    public static func parse(_ arguments: [String]) throws -> ParsedCommand {
        guard let firstArg = arguments.first else {
            return .help
        }

        switch firstArg {
        case "--help", "help", "-h":
            return .help

        case "--version", "-v":
            return .version

        case "notify":
            return try parseNotify(arguments: Array(arguments.dropFirst()))

        case "new-tab":
            return try parseNewTab(arguments: Array(arguments.dropFirst()))

        case "list-tabs":
            return .listTabs

        case "focus-tab":
            return try parseFocusTab(arguments: Array(arguments.dropFirst()))

        case "close-tab":
            return try parseCloseTab(arguments: Array(arguments.dropFirst()))

        case "split":
            return try parseSplit(arguments: Array(arguments.dropFirst()))

        case "status":
            return .status

        case "hooks":
            return try parseHooks(arguments: Array(arguments.dropFirst()))

        case "hook-handler":
            return .hookHandler

        // MARK: v2 compound commands

        case "tab":
            return try parseTab(arguments: Array(arguments.dropFirst()))

        case "dashboard":
            return try parseDashboard(arguments: Array(arguments.dropFirst()))

        case "timeline":
            return try parseTimeline(arguments: Array(arguments.dropFirst()))

        case "search":
            return try parseSearch(arguments: Array(arguments.dropFirst()))

        case "config":
            return try parseConfig(arguments: Array(arguments.dropFirst()))

        case "theme":
            return try parseTheme(arguments: Array(arguments.dropFirst()))

        case "send":
            return try parseSend(arguments: Array(arguments.dropFirst()))

        case "send-key":
            return try parseSendKey(arguments: Array(arguments.dropFirst()))

        default:
            throw CLIError.unknownCommand(firstArg)
        }
    }

    // MARK: - Private: Original Subcommand Parsers

    /// Parses `cocxy notify <message>`.
    private static func parseNotify(arguments: [String]) throws -> ParsedCommand {
        guard let message = arguments.first, !message.isEmpty else {
            throw CLIError.missingArgument(command: "notify", argument: "message")
        }
        // Join all remaining arguments as the message (allows multi-word messages).
        let fullMessage = arguments.joined(separator: " ")
        return .notify(message: fullMessage)
    }

    /// Parses `cocxy new-tab [--dir <path>]`.
    private static func parseNewTab(arguments: [String]) throws -> ParsedCommand {
        var directory: String?

        var index = 0
        while index < arguments.count {
            if arguments[index] == "--dir" {
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "new-tab", argument: "path")
                }
                directory = arguments[index + 1]
                index += 2
            } else {
                throw CLIError.invalidArgument(
                    command: "new-tab",
                    argument: arguments[index],
                    reason: "Unknown flag. Use --dir <path>."
                )
            }
        }

        return .newTab(directory: directory)
    }

    /// Parses `cocxy focus-tab <id>`.
    private static func parseFocusTab(arguments: [String]) throws -> ParsedCommand {
        guard let id = arguments.first, !id.isEmpty else {
            throw CLIError.missingArgument(command: "focus-tab", argument: "id")
        }
        return .focusTab(id: id)
    }

    /// Parses `cocxy close-tab <id>`.
    private static func parseCloseTab(arguments: [String]) throws -> ParsedCommand {
        guard let id = arguments.first, !id.isEmpty else {
            throw CLIError.missingArgument(command: "close-tab", argument: "id")
        }
        return .closeTab(id: id)
    }

    /// Parses `cocxy split [--dir h|v]` or extended split subcommands.
    ///
    /// This handles both the v1 `split [--dir h|v]` and v2 subcommands:
    /// `split list`, `split focus`, `split close`, `split resize`.
    private static func parseSplit(arguments: [String]) throws -> ParsedCommand {
        // Check if this is a v2 subcommand
        if let subcommand = arguments.first {
            switch subcommand {
            case "list":
                return .splitList
            case "focus":
                return try parseSplitFocus(arguments: Array(arguments.dropFirst()))
            case "close":
                return .splitClose
            case "resize":
                return try parseSplitResize(arguments: Array(arguments.dropFirst()))
            default:
                break // Fall through to v1 parsing
            }
        }

        // v1 parsing: split [--dir h|v]
        var direction: SplitDirection?

        var index = 0
        while index < arguments.count {
            if arguments[index] == "--dir" {
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "split", argument: "direction (h|v)")
                }
                let dirString = arguments[index + 1]
                guard let dir = SplitDirection(rawValue: dirString) else {
                    throw CLIError.invalidArgument(
                        command: "split",
                        argument: dirString,
                        reason: "Must be 'h' (horizontal) or 'v' (vertical)."
                    )
                }
                direction = dir
                index += 2
            } else {
                throw CLIError.invalidArgument(
                    command: "split",
                    argument: arguments[index],
                    reason: "Unknown flag. Use --dir h|v."
                )
            }
        }

        return .split(direction: direction)
    }

    /// Parses `cocxy hooks <subcommand>`.
    private static func parseHooks(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            // No subcommand defaults to status
            return .hooksStatus
        }

        switch subcommand {
        case "install":
            return .hooksInstall
        case "uninstall":
            return .hooksUninstall
        case "status":
            return .hooksStatus
        default:
            throw CLIError.invalidArgument(
                command: "hooks",
                argument: subcommand,
                reason: "Unknown subcommand. Use install, uninstall, or status."
            )
        }
    }

    // MARK: - Private: v2 Subcommand Parsers

    /// Parses `cocxy tab <subcommand> ...`.
    private static func parseTab(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "tab", argument: "subcommand")
        }

        switch subcommand {
        case "rename":
            return try parseTabRename(arguments: Array(arguments.dropFirst()))
        case "move":
            return try parseTabMove(arguments: Array(arguments.dropFirst()))
        default:
            throw CLIError.invalidArgument(
                command: "tab",
                argument: subcommand,
                reason: "Unknown subcommand. Use rename or move."
            )
        }
    }

    /// Parses `cocxy tab rename <id> <name>`.
    private static func parseTabRename(arguments: [String]) throws -> ParsedCommand {
        guard arguments.count >= 2 else {
            if arguments.isEmpty {
                throw CLIError.missingArgument(command: "tab rename", argument: "id")
            }
            throw CLIError.missingArgument(command: "tab rename", argument: "name")
        }
        let id = arguments[0]
        let name = arguments[1...].joined(separator: " ")
        return .tabRename(id: id, name: name)
    }

    /// Parses `cocxy tab move <id> <position>`.
    private static func parseTabMove(arguments: [String]) throws -> ParsedCommand {
        guard arguments.count >= 2 else {
            if arguments.isEmpty {
                throw CLIError.missingArgument(command: "tab move", argument: "id")
            }
            throw CLIError.missingArgument(command: "tab move", argument: "position")
        }
        return .tabMove(id: arguments[0], position: arguments[1])
    }

    /// Parses `cocxy split focus <direction>`.
    private static func parseSplitFocus(arguments: [String]) throws -> ParsedCommand {
        guard let direction = arguments.first, !direction.isEmpty else {
            throw CLIError.missingArgument(command: "split focus", argument: "direction")
        }
        return .splitFocus(direction: direction)
    }

    /// Parses `cocxy split resize <direction> <px>`.
    private static func parseSplitResize(arguments: [String]) throws -> ParsedCommand {
        guard arguments.count >= 2 else {
            if arguments.isEmpty {
                throw CLIError.missingArgument(command: "split resize", argument: "direction")
            }
            throw CLIError.missingArgument(command: "split resize", argument: "pixels")
        }
        return .splitResize(direction: arguments[0], pixels: arguments[1])
    }

    /// Parses `cocxy dashboard <subcommand>`.
    private static func parseDashboard(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "dashboard", argument: "subcommand")
        }

        switch subcommand {
        case "show":
            return .dashboardShow
        case "hide":
            return .dashboardHide
        case "toggle":
            return .dashboardToggle
        case "status":
            return .dashboardStatus
        default:
            throw CLIError.invalidArgument(
                command: "dashboard",
                argument: subcommand,
                reason: "Unknown subcommand. Use show, hide, toggle, or status."
            )
        }
    }

    /// Parses `cocxy timeline <subcommand> ...`.
    private static func parseTimeline(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "timeline", argument: "subcommand")
        }

        switch subcommand {
        case "show":
            return try parseTimelineShow(arguments: Array(arguments.dropFirst()))
        case "export":
            return try parseTimelineExport(arguments: Array(arguments.dropFirst()))
        default:
            throw CLIError.invalidArgument(
                command: "timeline",
                argument: subcommand,
                reason: "Unknown subcommand. Use show or export."
            )
        }
    }

    /// Parses `cocxy timeline show <tab-id>`.
    private static func parseTimelineShow(arguments: [String]) throws -> ParsedCommand {
        guard let tabID = arguments.first, !tabID.isEmpty else {
            throw CLIError.missingArgument(command: "timeline show", argument: "tab-id")
        }
        return .timelineShow(tabID: tabID)
    }

    /// Parses `cocxy timeline export <tab-id> [--format json|md]`.
    private static func parseTimelineExport(arguments: [String]) throws -> ParsedCommand {
        guard let tabID = arguments.first, !tabID.isEmpty else {
            throw CLIError.missingArgument(command: "timeline export", argument: "tab-id")
        }

        var format = "json" // default format
        let remaining = Array(arguments.dropFirst())

        var index = 0
        while index < remaining.count {
            if remaining[index] == "--format" {
                guard index + 1 < remaining.count else {
                    throw CLIError.missingArgument(command: "timeline export", argument: "format")
                }
                format = remaining[index + 1]
                index += 2
            } else {
                index += 1
            }
        }

        return .timelineExport(tabID: tabID, format: format)
    }

    /// Parses `cocxy search <query> [--regex] [--case-sensitive] [--tab <id>]`.
    private static func parseSearch(arguments: [String]) throws -> ParsedCommand {
        var query: String?
        var regex = false
        var caseSensitive = false
        var tabID: String?

        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--regex":
                regex = true
                index += 1
            case "--case-sensitive":
                caseSensitive = true
                index += 1
            case "--tab":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "search", argument: "tab-id")
                }
                tabID = arguments[index + 1]
                index += 2
            default:
                if query == nil {
                    query = arguments[index]
                }
                index += 1
            }
        }

        guard let resolvedQuery = query else {
            throw CLIError.missingArgument(command: "search", argument: "query")
        }

        return .search(
            query: resolvedQuery,
            regex: regex,
            caseSensitive: caseSensitive,
            tabID: tabID
        )
    }

    /// Parses `cocxy config <subcommand> ...`.
    private static func parseConfig(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "config", argument: "subcommand")
        }

        switch subcommand {
        case "get":
            let rest = Array(arguments.dropFirst())
            guard let key = rest.first, !key.isEmpty else {
                throw CLIError.missingArgument(command: "config get", argument: "key")
            }
            return .configGet(key: key)

        case "set":
            let rest = Array(arguments.dropFirst())
            guard rest.count >= 2 else {
                if rest.isEmpty {
                    throw CLIError.missingArgument(command: "config set", argument: "key")
                }
                throw CLIError.missingArgument(command: "config set", argument: "value")
            }
            return .configSet(key: rest[0], value: rest[1])

        case "path":
            return .configPath

        default:
            throw CLIError.invalidArgument(
                command: "config",
                argument: subcommand,
                reason: "Unknown subcommand. Use get, set, or path."
            )
        }
    }

    /// Parses `cocxy theme <subcommand> ...`.
    private static func parseTheme(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "theme", argument: "subcommand")
        }

        switch subcommand {
        case "list":
            return .themeList
        case "set":
            let rest = Array(arguments.dropFirst())
            guard let name = rest.first, !name.isEmpty else {
                throw CLIError.missingArgument(command: "theme set", argument: "name")
            }
            return .themeSet(name: name)
        default:
            throw CLIError.invalidArgument(
                command: "theme",
                argument: subcommand,
                reason: "Unknown subcommand. Use list or set."
            )
        }
    }

    /// Parses `cocxy send <text>`.
    private static func parseSend(arguments: [String]) throws -> ParsedCommand {
        guard !arguments.isEmpty else {
            throw CLIError.missingArgument(command: "send", argument: "text")
        }
        let text = arguments.joined(separator: " ")
        return .send(text: text)
    }

    /// Parses `cocxy send-key <key>`.
    private static func parseSendKey(arguments: [String]) throws -> ParsedCommand {
        guard let key = arguments.first, !key.isEmpty else {
            throw CLIError.missingArgument(command: "send-key", argument: "key")
        }
        return .sendKey(key: key)
    }

    // MARK: - Help Text

    /// Generates the complete --help output.
    public static func helpText() -> String {
        var lines: [String] = []
        lines.append("cocxy - CLI companion for Cocxy Terminal")
        lines.append("")
        lines.append("USAGE:")
        lines.append("  cocxy <command> [options]")
        lines.append("")
        lines.append("COMMANDS:")
        for command in CLICommand.allCases {
            let padding = String(
                repeating: " ",
                count: max(1, 52 - command.usageExample.count)
            )
            lines.append("  \(command.usageExample)\(padding)\(command.helpDescription)")
        }
        lines.append("")
        lines.append("OPTIONS:")
        lines.append("  --help, -h              Show this help message")
        lines.append("  --version, -v           Show version")
        lines.append("")
        lines.append("EXAMPLES:")
        lines.append("  cocxy notify \"Build complete\"")
        lines.append("  cocxy new-tab --dir ~/projects")
        lines.append("  cocxy split --dir h")
        lines.append("  cocxy list-tabs | jq '.'")
        lines.append("  cocxy tab rename <id> \"My Tab\"")
        lines.append("  cocxy dashboard toggle")
        lines.append("  cocxy search \"error\" --regex")
        lines.append("  cocxy config get font.size")
        lines.append("  cocxy theme set dracula")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Generates the version output.
    public static func versionText() -> String {
        return "cocxy \(version)"
    }
}
