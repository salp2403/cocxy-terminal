// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ArgumentParser.swift - Manual CLI argument parsing (zero dependencies).

import Foundation
import CocxyShared

// MARK: - Parsed Command

/// The result of parsing CLI arguments into a concrete command and its parameters.
///
/// This type decouples argument parsing from socket communication,
/// making both independently testable.
public enum ParsedCommand: Equatable {

    // MARK: - Original commands (v1)

    /// `cocxy notify <message>`
    case notify(message: String)

    /// `cocxy new-tab [--dir <path>] [--engine system|in-process|daemon]`
    case newTab(directory: String?, engine: String?)

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

    /// `cocxy setup-hooks [--agent claude|codex|gemini|kiro|all] [--remove]`
    case setupHooks(agent: SetupHooksTarget?, remove: Bool)

    /// `cocxy review`
    case review

    /// `cocxy review refresh`
    case reviewRefresh

    /// `cocxy review submit`
    case reviewSubmit

    /// `cocxy review status`
    case reviewStats

    /// `cocxy review approve [--pr <n>] [--body <text>|--stdin]`
    case reviewApprove(prNumber: Int?, body: String?, readBodyFromStdin: Bool)

    /// `cocxy review request-changes [--pr <n>] [--body <text>|--stdin]`
    case reviewRequestChanges(prNumber: Int?, body: String?, readBodyFromStdin: Bool)

    /// `cocxy open <path> [--editor <id>] [--line <n>] [--column <n>]`
    case editorOpen(path: String, editor: String?, line: Int?, column: Int?)

    /// `cocxy --help` or `cocxy help`
    case help

    /// `cocxy --version`
    case version

    // MARK: - Tab extended (v2)

    /// `cocxy tab rename <id> <name>`
    case tabRename(id: String, name: String)

    /// `cocxy tab move <id> <position>`
    case tabMove(id: String, position: String)

    /// `cocxy tab config save <name> [--command <cmd>] [--theme <theme>] [--env KEY=VALUE]`
    case tabConfigSave(
        name: String,
        command: String?,
        theme: String?,
        environment: [String: String]
    )

    /// `cocxy tab config open <name>`
    case tabConfigOpen(name: String)

    /// `cocxy tab config list`
    case tabConfigList

    /// `cocxy tab config path <name>`
    case tabConfigPath(name: String)

    /// `cocxy tab config export <name> --output <path> [--force]`
    case tabConfigExport(name: String, output: String, force: Bool)

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

    /// `cocxy classify <input>`
    case classify(input: String)

    /// `cocxy identify`
    case identify

    /// `cocxy capabilities`
    case capabilities

    /// `cocxy top [--once|--json] [--interval <seconds>]`
    case top(mode: CLITopMode)

    /// `cocxy keys generate --author <name>`
    case keysGenerate(author: String)

    /// `cocxy keys list`
    case keysList

    /// `cocxy keys export-public <key-id> [--output <path>]`
    case keysExportPublic(keyID: String, outputPath: String?)

    /// `cocxy keys import <path>`
    case keysImport(path: String)

    /// `cocxy sign <template|macro|plugin|notebook|file> <path> [--key <id>] [--author <name>]`
    case signArtifact(kind: String, path: String, keyID: String?, author: String?)

    /// `cocxy verify <template|macro|plugin|notebook|file> <path> [--public-key <path>]`
    case verifyArtifact(kind: String, path: String, publicKeyPath: String?)

    // MARK: - Window Management (v3)

    /// `cocxy window new [--engine system|in-process|daemon]`
    case windowNew(engine: String?)

    /// `cocxy window list`
    case windowList

    /// `cocxy window focus <index>`
    case windowFocus(index: String)

    /// `cocxy window close [<index>]`
    case windowClose(index: String?)

    /// `cocxy window fullscreen`
    case windowFullscreen

    // MARK: - Session Management (v3)

    /// `cocxy session save [<name>]`
    case sessionSave(name: String?)

    /// `cocxy session restore <name>`
    case sessionRestore(name: String)

    /// `cocxy session list`
    case sessionList

    /// `cocxy session delete <name>`
    case sessionDelete(name: String)

    // MARK: - Tab extended (v3)

    /// `cocxy tab duplicate [<id>]`
    case tabDuplicate(id: String?)

    /// `cocxy tab pin [<id>]`
    case tabPin(id: String?)

    // MARK: - Config extended (v3)

    /// `cocxy config list [--filter <prefix>]`
    case configList(filter: String?)

    /// `cocxy config reload`
    case configReload

    /// `cocxy config-project`
    case configProject

    // MARK: - Split extended (v3)

    /// `cocxy split swap <direction>`
    case splitSwap(direction: String)

    /// `cocxy split zoom`
    case splitZoom

    // MARK: - Output (v3)

    /// `cocxy capture-pane [--start <line>] [--end <line>]`
    case capturePane(start: Int?, end: Int?)

    // MARK: - Notification CLI (v3)

    /// `cocxy notification list [--limit <n>]`
    case notificationList(limit: Int?)

    /// `cocxy notification clear`
    case notificationClear

    // MARK: - Remote Workspace (exposed v3)

    /// `cocxy remote list`
    case remoteList

    /// `cocxy remote connect <name>`
    case remoteConnect(name: String)

    /// `cocxy remote disconnect <name>`
    case remoteDisconnect(name: String)

    /// `cocxy remote status [<name>]`
    case remoteStatus(name: String?)

    /// `cocxy remote tunnels [--profile <name>]`
    case remoteTunnels(profile: String?)

    // MARK: - Plugin Management (exposed v3)

    /// `cocxy plugin list`
    case pluginList

    /// `cocxy plugin enable <id>`
    case pluginEnable(id: String)

    /// `cocxy plugin disable <id>`
    case pluginDisable(id: String)

    /// `cocxy plugin source list`
    case pluginSourceList

    /// `cocxy plugin source add <url> [--name <display-name>]`
    case pluginSourceAdd(url: String, displayName: String?)

    /// `cocxy plugin install <url-or-path> [--replace]`
    case pluginInstall(url: String, replaceExisting: Bool)

    /// `cocxy plugin uninstall <id>`
    case pluginUninstall(id: String)

    // MARK: - Browser (exposed v3)

    /// `cocxy browser navigate <url>`
    case browserNavigate(url: String)

    /// `cocxy browser back`
    case browserBack

    /// `cocxy browser forward`
    case browserForward

    /// `cocxy browser reload`
    case browserReload

    /// `cocxy browser state`
    case browserGetState

    /// `cocxy browser eval <script>`
    case browserEval(script: String)

    /// `cocxy browser text`
    case browserGetText

    /// `cocxy browser tabs`
    case browserListTabs

    // MARK: - SSH (v4)

    /// `cocxy ssh user@host [-p port] [-i identity]`
    case ssh(destination: String, port: Int?, identityFile: String?)

    // MARK: - Web Terminal (v5)

    /// `cocxy web start [--bind <address>] [--port <port>] [--token <token>] [--fps <n>]`
    case webStart(bindAddress: String?, port: Int?, token: String?, fps: Int?)

    /// `cocxy web stop`
    case webStop

    /// `cocxy web status`
    case webStatus

    // MARK: - CocxyCore Streams / Protocol / Images (v5)

    /// `cocxy stream list`
    case streamList

    /// `cocxy stream current <id>`
    case streamCurrent(id: Int)

    /// `cocxy protocol capabilities`
    case protocolCapabilities

    /// `cocxy protocol viewport [--request-id <id>]`
    case protocolViewport(requestID: String?)

    /// `cocxy protocol send --type <type> --json <json>`
    case protocolSend(type: String, json: String)

    /// `cocxy core reset`
    case coreReset

    /// `cocxy core signal <signal>`
    case coreSignal(signal: String)

    /// `cocxy core process`
    case coreProcess

    /// `cocxy core modes`
    case coreModes

    /// `cocxy core search`
    case coreSearch

    /// `cocxy core ligatures`
    case coreLigatures

    /// `cocxy core protocol`
    case coreProtocol

    /// `cocxy core selection`
    case coreSelection

    /// `cocxy core font`
    case coreFontMetrics

    /// `cocxy core preedit`
    case corePreedit

    /// `cocxy core semantic [--limit <n>]`
    case coreSemantic(limit: Int?)

    /// `cocxy block list [--limit <n>]`
    case blockList(limit: Int?)

    /// `cocxy block outputs [--limit <n>]`
    case blockOutputs(limit: Int?)

    /// `cocxy block copy <id> [--field command|output|both]`
    case blockCopy(id: UInt64, field: String)

    /// `cocxy block rerun <id>`
    case blockRerun(id: UInt64)

    /// `cocxy image list`
    case imageList

    /// `cocxy image delete <id>`
    case imageDelete(id: Int)

    /// `cocxy image clear`
    case imageClear

    /// `cocxy notebook import <input.ipynb> --output <output.cocxynb> [--force]`
    case notebookImport(inputPath: String, outputPath: String, force: Bool)

    /// `cocxy notebook export <input.cocxynb> --output <output.ipynb> [--force]`
    case notebookExport(inputPath: String, outputPath: String, force: Bool)

    /// `cocxy notebook export-html <input.cocxynb> --output <output.html> [--force]`
    case notebookExportHTML(inputPath: String, outputPath: String, force: Bool)

    /// `cocxy notebook template list`
    case notebookTemplateList

    /// `cocxy notebook template create <template-id> --output <output.cocxynb> [--force]`
    case notebookTemplateCreate(templateID: String, outputPath: String, force: Bool)

    /// `cocxy notebook run <input.cocxynb> [--output <output.cocxynb>] [--cwd <dir>] [--sandbox workspace|none]`
    case notebookRun(
        inputPath: String,
        outputPath: String?,
        workingDirectory: String?,
        timeoutSeconds: Double?,
        sandbox: String,
        continueOnFailure: Bool
    )

    /// `cocxy workflow run <input.toml> [--cwd <dir>]`
    case workflowRun(inputPath: String, workingDirectory: String?)

    /// `cocxy skill list`
    case skillList

    /// `cocxy skill source list`
    case skillSourceList

    /// `cocxy skill source add <url> [--name <display-name>]`
    case skillSourceAdd(url: String, displayName: String?)

    /// `cocxy skill install <url-or-path> [--replace]`
    case skillInstall(url: String, replaceExisting: Bool)

    /// `cocxy skill uninstall <id>`
    case skillUninstall(id: String)

    /// `cocxy worktree add [--agent <name>] [--branch <template>] [--base-ref <ref>]`
    case worktreeAdd(agent: String?, branch: String?, baseRef: String?)

    /// `cocxy worktree list`
    case worktreeList

    /// `cocxy worktree remove <id> [--force]`
    case worktreeRemove(id: String, force: Bool)

    /// `cocxy worktree focus <id>`
    case worktreeFocus(id: String)

    /// `cocxy worktree prune`
    case worktreePrune

    /// `cocxy worktree cleanup-merged [--base-ref <ref>] [--force] [--dry-run]`
    case worktreeCleanupMerged(baseRef: String?, force: Bool, dryRun: Bool)

    /// `cocxy github status` — auth + repository summary JSON.
    case githubStatus

    /// `cocxy github prs [--state open|closed|merged|all] [--limit N]`
    /// — list pull requests for the active tab's repository.
    case githubPRs(state: String?, limit: Int?)

    /// `cocxy github issues [--state open|closed|all] [--limit N]`
    /// — list issues for the active tab's repository.
    case githubIssues(state: String?, limit: Int?)

    /// `cocxy github open` — toggle the GitHub pane overlay.
    case githubOpen

    /// `cocxy github refresh` — refresh the GitHub pane data.
    case githubRefresh

    /// `cocxy github pr-merge --squash|--merge|--rebase
    /// [--pr <n>] [--no-delete-branch] [--subject <s>] [--body <b>]`
    /// — merges a pull request via gh.
    case githubPRMerge(
        method: GitHubMergeMethodCLI,
        prNumber: Int?,
        deleteBranch: Bool,
        subject: String?,
        body: String?
    )
}

/// Mirror of `GitHubMergeMethod` exposed at the CLI client. Lives in
/// the parser layer so the client target does not have to import the
/// CocxyTerminal target where the typed enum lives.
public enum GitHubMergeMethodCLI: String, Equatable, Sendable {
    case squash
    case merge
    case rebase
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
    ///
    /// Resolved dynamically when the CLI runs from inside the
    /// `Cocxy Terminal.app` bundle by reading
    /// `CFBundleShortVersionString` from `Contents/Info.plist`. This keeps
    /// the CLI's `--version` in sync with the GUI version shipped in the
    /// same release without manual bumping.
    ///
    /// Falls back to `Resources/Info.plist` for standalone SwiftPM dev
    /// builds, then to `fallbackVersion` when no release metadata is
    /// reachable.
    public static let version: String = resolveVersion()

    /// The bundle identifier for the app that owns this CLI.
    public static let bundleIdentifier: String = resolveBundleIdentifier()

    /// Last-resort fallback. It mirrors `Resources/Info.plist` and is only
    /// used when neither the enclosing `.app` nor a SwiftPM checkout can be
    /// resolved.
    internal static let fallbackVersion = "1.0.5"
    internal static let fallbackBundleIdentifier = "dev.cocxy.terminal"

    /// Resolves the CLI version by preferring the enclosing app bundle's
    /// `Info.plist`, then the checkout's `Resources/Info.plist`, with a
    /// hardcoded fallback for fully standalone execution.
    ///
    /// Expected bundled layout:
    /// `Cocxy Terminal.app/Contents/Resources/cocxy` →
    /// `Cocxy Terminal.app/Contents/Info.plist` (two levels up).
    ///
    /// `Bundle.main.executablePath` does not resolve symlinks. When the
    /// CLI is invoked through a PATH symlink (for example Homebrew's
    /// `/opt/homebrew/bin/cocxy` pointing at the app-bundled binary),
    /// that path would otherwise walk up from the symlink's directory
    /// and miss the enclosing `.app`. We resolve the symlink first so
    /// the walk lands on the real `Contents/Info.plist`.
    ///
    /// - Returns: the bundled or checkout version when reachable, or
    ///   `fallbackVersion` for unresolvable standalone layouts.
    internal static func resolveVersion(executablePath: String? = nil) -> String {
        resolveMetadataValue(
            key: "CFBundleShortVersionString",
            executablePath: executablePath,
            fallback: fallbackVersion
        )
    }

    /// Resolves the owning app bundle identifier using the same search
    /// order as `resolveVersion`.
    internal static func resolveBundleIdentifier(executablePath: String? = nil) -> String {
        resolveMetadataValue(
            key: "CFBundleIdentifier",
            executablePath: executablePath,
            fallback: fallbackBundleIdentifier
        )
    }

    private static func resolveMetadataValue(
        key: String,
        executablePath: String?,
        fallback: String
    ) -> String {
        let rawPath = executablePath ?? Bundle.main.executablePath
        guard let exePath = rawPath else {
            return fallback
        }
        // Resolve any symlinks so `/opt/homebrew/bin/cocxy` → the real
        // `Cocxy Terminal.app/Contents/Resources/cocxy`. `standardizedFileURL`
        // resolves symlinks, collapses `..`/`.`, and returns the canonical
        // path that walk-up logic can rely on.
        let realPath = URL(fileURLWithPath: exePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let resourcesDir = (realPath as NSString).deletingLastPathComponent
        let contentsDir = (resourcesDir as NSString).deletingLastPathComponent
        let plistPath = (contentsDir as NSString).appendingPathComponent("Info.plist")

        if let bundledValue = metadataValue(inInfoPlistAt: plistPath, key: key) {
            return bundledValue
        }
        if let checkoutValue = resolveDevelopmentMetadataValue(startingAt: realPath, key: key) {
            return checkoutValue
        }
        return fallback
    }

    private static func resolveDevelopmentMetadataValue(startingAt path: String, key: String) -> String? {
        var candidate = URL(fileURLWithPath: path).deletingLastPathComponent()
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        while true {
            let plistPath = candidate
                .appendingPathComponent("Resources")
                .appendingPathComponent("Info.plist")
                .path
            if let value = metadataValue(inInfoPlistAt: plistPath, key: key) {
                return value
            }
            if candidate == root {
                return nil
            }
            candidate.deleteLastPathComponent()
        }
    }

    private static func metadataValue(inInfoPlistAt plistPath: String, key: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any],
              let value = plist[key] as? String
        else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

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

        case "setup-hooks":
            return try parseSetupHooks(arguments: Array(arguments.dropFirst()))

        case "review":
            return try parseReview(arguments: Array(arguments.dropFirst()))

        case "open":
            return try parseEditorOpen(arguments: Array(arguments.dropFirst()))

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

        case "classify":
            return try parseClassify(arguments: Array(arguments.dropFirst()))

        case "identify":
            return .identify

        case "capabilities":
            return .capabilities

        case "top":
            return try parseTop(arguments: Array(arguments.dropFirst()))

        case "keys":
            return try parseKeys(arguments: Array(arguments.dropFirst()))

        case "sign":
            return try parseSign(arguments: Array(arguments.dropFirst()))

        case "verify":
            return try parseVerify(arguments: Array(arguments.dropFirst()))

        // MARK: v3 compound commands

        case "window":
            return try parseWindow(arguments: Array(arguments.dropFirst()))

        case "session":
            return try parseSession(arguments: Array(arguments.dropFirst()))

        case "capture-pane":
            return try parseCapturePane(arguments: Array(arguments.dropFirst()))

        case "config-project":
            return .configProject

        case "notification":
            return try parseNotification(arguments: Array(arguments.dropFirst()))

        case "remote":
            return try parseRemote(arguments: Array(arguments.dropFirst()))

        case "ssh":
            return try parseSSH(arguments: Array(arguments.dropFirst()))

        case "plugin":
            return try parsePlugin(arguments: Array(arguments.dropFirst()))
        case "plugin-list":
            return try parsePlugin(arguments: ["list"] + Array(arguments.dropFirst()))
        case "plugin-enable":
            return try parsePlugin(arguments: ["enable"] + Array(arguments.dropFirst()))
        case "plugin-disable":
            return try parsePlugin(arguments: ["disable"] + Array(arguments.dropFirst()))
        case "plugin-source-list":
            return try parsePlugin(arguments: ["source", "list"] + Array(arguments.dropFirst()))
        case "plugin-source-add":
            return try parsePlugin(arguments: ["source", "add"] + Array(arguments.dropFirst()))
        case "plugin-install":
            return try parsePlugin(arguments: ["install"] + Array(arguments.dropFirst()))
        case "plugin-uninstall":
            return try parsePlugin(arguments: ["uninstall"] + Array(arguments.dropFirst()))

        case "browser":
            return try parseBrowser(arguments: Array(arguments.dropFirst()))

        case "web":
            return try parseWeb(arguments: Array(arguments.dropFirst()))

        case "stream":
            return try parseStream(arguments: Array(arguments.dropFirst()))

        case "protocol":
            return try parseProtocol(arguments: Array(arguments.dropFirst()))

        case "core":
            return try parseCore(arguments: Array(arguments.dropFirst()))

        case "block", "blocks":
            return try parseBlock(arguments: Array(arguments.dropFirst()))

        case "image":
            return try parseImage(arguments: Array(arguments.dropFirst()))

        case "notebook":
            return try parseNotebook(arguments: Array(arguments.dropFirst()))

        case "workflow", "workflows":
            return try parseWorkflow(arguments: Array(arguments.dropFirst()))

        case "skill", "skills":
            return try parseSkill(arguments: Array(arguments.dropFirst()))
        case "skill-source-list":
            return try parseSkill(arguments: ["source", "list"] + Array(arguments.dropFirst()))
        case "skill-source-add":
            return try parseSkill(arguments: ["source", "add"] + Array(arguments.dropFirst()))
        case "skill-install":
            return try parseSkill(arguments: ["install"] + Array(arguments.dropFirst()))
        case "skill-uninstall":
            return try parseSkill(arguments: ["uninstall"] + Array(arguments.dropFirst()))

        case "worktree":
            return try parseWorktree(arguments: Array(arguments.dropFirst()))

        case "github":
            return try parseGitHub(arguments: Array(arguments.dropFirst()))

        default:
            throw CLIError.unknownCommand(firstArg)
        }
    }

    private static func isHelpToken(_ token: String) -> Bool {
        token == "--help" || token == "-h" || token == "help"
    }

    private static func isOnlyHelpRequest(_ arguments: [String]) -> Bool {
        arguments.count == 1 && isHelpToken(arguments[0])
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

    /// Parses `cocxy new-tab [--dir <path>] [--engine system|in-process|daemon]`.
    private static func parseNewTab(arguments: [String]) throws -> ParsedCommand {
        var directory: String?
        var engine: String?

        var index = 0
        while index < arguments.count {
            if arguments[index] == "--dir" {
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "new-tab", argument: "path")
                }
                directory = arguments[index + 1]
                index += 2
            } else if arguments[index] == "--engine" {
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "new-tab", argument: "engine")
                }
                let value = arguments[index + 1]
                guard TerminalEnginePreference(cliValue: value) != nil else {
                    throw CLIError.invalidArgument(
                        command: "new-tab",
                        argument: value,
                        reason: "Engine must be system, in-process, or daemon"
                    )
                }
                engine = value
                index += 2
            } else {
                throw CLIError.invalidArgument(
                    command: "new-tab",
                    argument: arguments[index],
                    reason: "Unknown flag. Use --dir <path> or --engine system|in-process|daemon."
                )
            }
        }

        return .newTab(directory: directory, engine: engine)
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
            case "swap":
                let rest = Array(arguments.dropFirst())
                guard let direction = rest.first, !direction.isEmpty else {
                    throw CLIError.missingArgument(command: "split swap", argument: "direction")
                }
                return .splitSwap(direction: direction)
            case "zoom":
                return .splitZoom
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

    /// Parses `cocxy setup-hooks [--agent <name>] [--remove]`.
    private static func parseSetupHooks(arguments: [String]) throws -> ParsedCommand {
        var selectedAgent: SetupHooksTarget?
        var remove = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--remove":
                remove = true
                index += 1

            case "--agent":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "setup-hooks", argument: "agent")
                }

                let rawAgent = arguments[index + 1].lowercased()
                guard let parsedAgent = SetupHooksTarget(rawValue: rawAgent) else {
                    throw CLIError.invalidArgument(
                        command: "setup-hooks",
                        argument: rawAgent,
                        reason: "Must be claude, codex, gemini, kiro, or all."
                    )
                }

                selectedAgent = parsedAgent
                index += 2

            default:
                throw CLIError.invalidArgument(
                    command: "setup-hooks",
                    argument: arguments[index],
                    reason: "Unknown flag. Use --agent <name> and/or --remove."
                )
            }
        }

        return .setupHooks(agent: selectedAgent, remove: remove)
    }

    private static func parseReview(arguments: [String]) throws -> ParsedCommand {
        guard !arguments.isEmpty else { return .review }
        if isOnlyHelpRequest(arguments) {
            return .help
        }

        if arguments.count == 1 {
            switch arguments[0] {
            case "refresh":
                return .reviewRefresh
            case "submit":
                return .reviewSubmit
            case "status", "stats":
                return .reviewStats
            case "approve":
                return .reviewApprove(prNumber: nil, body: nil, readBodyFromStdin: false)
            case "request-changes":
                return .reviewRequestChanges(prNumber: nil, body: nil, readBodyFromStdin: false)
            default:
                break
            }
        }

        if let action = arguments.first, action == "approve" || action == "request-changes" {
            let rest = Array(arguments.dropFirst())
            if isOnlyHelpRequest(rest) {
                return .help
            }
            let parsed = try parseReviewPRReview(
                command: "review \(action)",
                arguments: rest
            )
            if action == "approve" {
                return .reviewApprove(
                    prNumber: parsed.prNumber,
                    body: parsed.body,
                    readBodyFromStdin: parsed.readBodyFromStdin
                )
            }
            return .reviewRequestChanges(
                prNumber: parsed.prNumber,
                body: parsed.body,
                readBodyFromStdin: parsed.readBodyFromStdin
            )
        }

        let flags = Set(arguments)
        let supported = Set(["--refresh", "--submit", "--stats"])
        let unsupported = flags.subtracting(supported)
        if let invalid = unsupported.first {
            throw CLIError.invalidArgument(
                command: "review",
                argument: invalid,
                reason: "Unknown action. Use refresh, submit, status, --refresh, --submit, or --stats."
            )
        }

        if flags.count > 1 {
            throw CLIError.invalidArgument(
                command: "review",
                argument: arguments.joined(separator: " "),
                reason: "Only one review action can be requested at a time."
            )
        }

        if flags.contains("--refresh") {
            return .reviewRefresh
        }
        if flags.contains("--submit") {
            return .reviewSubmit
        }
        if flags.contains("--stats") {
            return .reviewStats
        }

        return .review
    }

    private static func parseReviewPRReview(
        command: String,
        arguments: [String]
    ) throws -> (prNumber: Int?, body: String?, readBodyFromStdin: Bool) {
        var prNumber: Int?
        var body: String?
        var readBodyFromStdin = false
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--pr":
                guard index + 1 < arguments.count,
                      let parsed = Int(arguments[index + 1]),
                      parsed > 0 else {
                    throw CLIError.invalidArgument(
                        command: command,
                        argument: token,
                        reason: "--pr expects a positive pull request number."
                    )
                }
                prNumber = parsed
                index += 2
            case "--body":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: command, argument: "value for --body")
                }
                let value = arguments[index + 1]
                if value == "-" {
                    readBodyFromStdin = true
                } else {
                    body = value
                }
                index += 2
            case "--body-file":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: command, argument: "value for --body-file")
                }
                guard arguments[index + 1] == "-" else {
                    throw CLIError.invalidArgument(
                        command: command,
                        argument: arguments[index + 1],
                        reason: "Only --body-file - is supported; pass file contents on stdin."
                    )
                }
                readBodyFromStdin = true
                index += 2
            case "--stdin":
                readBodyFromStdin = true
                index += 1
            default:
                throw CLIError.invalidArgument(
                    command: command,
                    argument: token,
                    reason: "Unknown option. Valid flags: --pr, --body, --body-file -, --stdin."
                )
            }
        }

        return (prNumber, body, readBodyFromStdin)
    }

    /// Parses `cocxy open <path> [--editor <id>] [--line <n>] [--column <n>]`.
    private static func parseEditorOpen(arguments: [String]) throws -> ParsedCommand {
        if isOnlyHelpRequest(arguments) {
            return .help
        }

        var path: String?
        var editor: String?
        var line: Int?
        var column: Int?
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--editor", "-e":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "open", argument: "value for --editor")
                }
                editor = arguments[index + 1]
                index += 2
            case "--line":
                guard index + 1 < arguments.count, let parsed = Int(arguments[index + 1]), parsed > 0 else {
                    throw CLIError.invalidArgument(
                        command: "open",
                        argument: token,
                        reason: "--line expects a positive integer."
                    )
                }
                line = parsed
                index += 2
            case "--column":
                guard index + 1 < arguments.count, let parsed = Int(arguments[index + 1]), parsed > 0 else {
                    throw CLIError.invalidArgument(
                        command: "open",
                        argument: token,
                        reason: "--column expects a positive integer."
                    )
                }
                column = parsed
                index += 2
            default:
                if token.hasPrefix("-") {
                    throw CLIError.invalidArgument(
                        command: "open",
                        argument: token,
                        reason: "Unknown option. Valid flags: --editor, --line, --column."
                    )
                }
                guard path == nil else {
                    throw CLIError.invalidArgument(
                        command: "open",
                        argument: token,
                        reason: "`open` accepts exactly one path."
                    )
                }
                path = token
                index += 1
            }
        }

        guard let path, path.isEmpty == false else {
            throw CLIError.missingArgument(command: "open", argument: "path")
        }

        if let editor, EditorRegistry.launcher(matching: editor) == nil {
            throw CLIError.invalidArgument(
                command: "open",
                argument: editor,
                reason: "Unknown editor. Valid editors: \(EditorRegistry.builtIn.map(\.id).joined(separator: ", ")), system."
            )
        }

        return .editorOpen(path: path, editor: editor, line: line, column: column)
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
        case "config":
            return try parseTabConfig(arguments: Array(arguments.dropFirst()))
        case "duplicate":
            return .tabDuplicate(id: arguments.dropFirst().first)
        case "pin":
            return .tabPin(id: arguments.dropFirst().first)
        default:
            throw CLIError.invalidArgument(
                command: "tab",
                argument: subcommand,
                reason: "Unknown subcommand. Use rename, move, config, duplicate, or pin."
            )
        }
    }

    /// Parses `cocxy tab config <save|open|list|path>`.
    private static func parseTabConfig(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "tab config", argument: "subcommand")
        }

        switch subcommand {
        case "save":
            return try parseTabConfigSave(arguments: Array(arguments.dropFirst()))
        case "open":
            let rest = Array(arguments.dropFirst())
            guard let name = rest.first, !name.isEmpty else {
                throw CLIError.missingArgument(command: "tab config open", argument: "name")
            }
            return .tabConfigOpen(name: name)
        case "list":
            return .tabConfigList
        case "path":
            let rest = Array(arguments.dropFirst())
            guard let name = rest.first, !name.isEmpty else {
                throw CLIError.missingArgument(command: "tab config path", argument: "name")
            }
            return .tabConfigPath(name: name)
        case "export":
            return try parseTabConfigExport(arguments: Array(arguments.dropFirst()))
        default:
            throw CLIError.invalidArgument(
                command: "tab config",
                argument: subcommand,
                reason: "Unknown subcommand. Use save, open, list, path, or export."
            )
        }
    }

    private static func parseTabConfigSave(arguments: [String]) throws -> ParsedCommand {
        guard let name = arguments.first, !name.isEmpty else {
            throw CLIError.missingArgument(command: "tab config save", argument: "name")
        }

        var command: String?
        var theme: String?
        var environment: [String: String] = [:]
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--command":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "tab config save", argument: "command")
                }
                command = arguments[index + 1]
                index += 2
            case "--theme":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "tab config save", argument: "theme")
                }
                theme = arguments[index + 1]
                index += 2
            case "--env":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "tab config save", argument: "KEY=VALUE")
                }
                let pair = arguments[index + 1]
                guard let equals = pair.firstIndex(of: "="),
                      equals != pair.startIndex else {
                    throw CLIError.invalidArgument(
                        command: "tab config save",
                        argument: pair,
                        reason: "Environment overrides must use KEY=VALUE."
                    )
                }
                let key = String(pair[..<equals])
                let value = String(pair[pair.index(after: equals)...])
                environment[key] = value
                index += 2
            default:
                throw CLIError.invalidArgument(
                    command: "tab config save",
                    argument: arguments[index],
                    reason: "Unknown flag. Use --command, --theme, or --env KEY=VALUE."
                )
            }
        }

        return .tabConfigSave(
            name: name,
            command: command,
            theme: theme,
            environment: environment
        )
    }

    private static func parseTabConfigExport(arguments: [String]) throws -> ParsedCommand {
        guard let name = arguments.first, !name.isEmpty else {
            throw CLIError.missingArgument(command: "tab config export", argument: "name")
        }

        var output: String?
        var force = false
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--output", "-o":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "tab config export", argument: "output")
                }
                output = arguments[index + 1]
                index += 2
            case "--force":
                force = true
                index += 1
            default:
                throw CLIError.invalidArgument(
                    command: "tab config export",
                    argument: arguments[index],
                    reason: "Unknown flag. Use --output <path> and optional --force."
                )
            }
        }

        guard let output, !output.isEmpty else {
            throw CLIError.missingArgument(command: "tab config export", argument: "output")
        }
        return .tabConfigExport(name: name, output: output, force: force)
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
        var queryParts: [String] = []
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
                queryParts.append(arguments[index])
                index += 1
            }
        }

        let resolvedQuery = queryParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedQuery.isEmpty else {
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
            // Join remaining args to support multi-word values like "JetBrains Mono".
            let value = rest.dropFirst().joined(separator: " ")
            return .configSet(key: rest[0], value: value)

        case "path":
            return .configPath

        case "list":
            let rest = Array(arguments.dropFirst())
            var filter: String?
            var idx = 0
            while idx < rest.count {
                if rest[idx] == "--filter", idx + 1 < rest.count {
                    filter = rest[idx + 1]
                    idx += 2
                } else {
                    idx += 1
                }
            }
            return .configList(filter: filter)

        case "reload":
            return .configReload

        case "project":
            return .configProject

        default:
            throw CLIError.invalidArgument(
                command: "config",
                argument: subcommand,
                reason: "Unknown subcommand. Use get, set, path, list, reload, or project."
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
        if arguments == ["--stdin"] || arguments == ["-"] {
            let text = String(
                decoding: FileHandle.standardInput.readDataToEndOfFile(),
                as: UTF8.self
            )
            guard !text.isEmpty else {
                throw CLIError.missingArgument(command: "send --stdin", argument: "stdin")
            }
            return .send(text: text)
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

    /// Parses `cocxy classify <input>`.
    private static func parseClassify(arguments: [String]) throws -> ParsedCommand {
        guard !arguments.isEmpty else {
            throw CLIError.missingArgument(command: "classify", argument: "input")
        }
        return .classify(input: arguments.joined(separator: " "))
    }

    private static func parseTop(arguments: [String]) throws -> ParsedCommand {
        var mode: CLITopMode = .interactive(intervalSeconds: 1.0)
        var sawOutputMode = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--once":
                guard !sawOutputMode else {
                    throw CLIError.invalidArgument(
                        command: "top",
                        argument: "--once",
                        reason: "Use only one of --once or --json."
                    )
                }
                mode = .once
                sawOutputMode = true
                index += 1
            case "--json":
                guard !sawOutputMode else {
                    throw CLIError.invalidArgument(
                        command: "top",
                        argument: "--json",
                        reason: "Use only one of --once or --json."
                    )
                }
                mode = .json
                sawOutputMode = true
                index += 1
            case "--interval":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "top", argument: "seconds")
                }
                let rawValue = arguments[index + 1]
                guard let interval = TimeInterval(rawValue), interval >= 0.2 else {
                    throw CLIError.invalidArgument(
                        command: "top",
                        argument: rawValue,
                        reason: "Interval must be a number >= 0.2 seconds."
                    )
                }
                if case .interactive = mode {
                    mode = .interactive(intervalSeconds: interval)
                }
                index += 2
            default:
                throw CLIError.invalidArgument(
                    command: "top",
                    argument: arguments[index],
                    reason: "Unknown flag. Use --once, --json, or --interval <seconds>."
                )
            }
        }

        return .top(mode: mode)
    }

    /// Parses `cocxy keys <subcommand>`.
    private static func parseKeys(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "keys", argument: "subcommand")
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "generate":
            var author: String?
            var index = 0
            while index < rest.count {
                switch rest[index] {
                case "--author":
                    guard index + 1 < rest.count else {
                        throw CLIError.missingArgument(command: "keys generate", argument: "author")
                    }
                    author = rest[index + 1]
                    index += 2
                default:
                    throw CLIError.invalidArgument(
                        command: "keys generate",
                        argument: rest[index],
                        reason: "Use --author <name>"
                    )
                }
            }
            guard let author, !author.isEmpty else {
                throw CLIError.missingArgument(command: "keys generate", argument: "author")
            }
            return .keysGenerate(author: author)
        case "list":
            guard rest.isEmpty else {
                throw CLIError.invalidArgument(command: "keys list", argument: rest[0], reason: "No arguments expected")
            }
            return .keysList
        case "export-public":
            guard let keyID = rest.first else {
                throw CLIError.missingArgument(command: "keys export-public", argument: "key-id")
            }
            var outputPath: String?
            var index = 1
            while index < rest.count {
                switch rest[index] {
                case "--output":
                    guard index + 1 < rest.count else {
                        throw CLIError.missingArgument(command: "keys export-public", argument: "output")
                    }
                    outputPath = rest[index + 1]
                    index += 2
                default:
                    throw CLIError.invalidArgument(
                        command: "keys export-public",
                        argument: rest[index],
                        reason: "Use --output <path>"
                    )
                }
            }
            return .keysExportPublic(keyID: keyID, outputPath: outputPath)
        case "import":
            guard rest.count == 1 else {
                throw CLIError.missingArgument(command: "keys import", argument: "path")
            }
            return .keysImport(path: rest[0])
        default:
            throw CLIError.invalidArgument(
                command: "keys",
                argument: subcommand,
                reason: "Use generate, list, export-public, or import"
            )
        }
    }

    /// Parses `cocxy sign <kind> <path>`.
    private static func parseSign(arguments: [String]) throws -> ParsedCommand {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument(command: "sign", argument: "kind path")
        }
        let kind = arguments[0]
        let path = arguments[1]
        var keyID: String?
        var author: String?
        var index = 2
        while index < arguments.count {
            switch arguments[index] {
            case "--key":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "sign", argument: "key")
                }
                keyID = arguments[index + 1]
                index += 2
            case "--author":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "sign", argument: "author")
                }
                author = arguments[index + 1]
                index += 2
            default:
                throw CLIError.invalidArgument(command: "sign", argument: arguments[index], reason: "Use --key or --author")
            }
        }
        return .signArtifact(kind: kind, path: path, keyID: keyID, author: author)
    }

    /// Parses `cocxy verify <kind> <path>`.
    private static func parseVerify(arguments: [String]) throws -> ParsedCommand {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument(command: "verify", argument: "kind path")
        }
        let kind = arguments[0]
        let path = arguments[1]
        var publicKeyPath: String?
        var index = 2
        while index < arguments.count {
            switch arguments[index] {
            case "--public-key":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "verify", argument: "public-key")
                }
                publicKeyPath = arguments[index + 1]
                index += 2
            default:
                throw CLIError.invalidArgument(command: "verify", argument: arguments[index], reason: "Use --public-key <path>")
            }
        }
        return .verifyArtifact(kind: kind, path: path, publicKeyPath: publicKeyPath)
    }

    // MARK: - Private: v3 Subcommand Parsers

    /// Parses `cocxy window <subcommand>`.
    private static func parseWindow(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "window", argument: "subcommand")
        }

        switch subcommand {
        case "new":
            return try parseWindowNew(arguments: Array(arguments.dropFirst()))
        case "list":
            return .windowList
        case "focus":
            let rest = Array(arguments.dropFirst())
            guard let index = rest.first, !index.isEmpty else {
                throw CLIError.missingArgument(command: "window focus", argument: "index")
            }
            return .windowFocus(index: index)
        case "close":
            return .windowClose(index: arguments.dropFirst().first)
        case "fullscreen":
            return .windowFullscreen
        default:
            throw CLIError.invalidArgument(
                command: "window",
                argument: subcommand,
                reason: "Unknown subcommand. Use new, list, focus, close, or fullscreen."
            )
        }
    }

    /// Parses `cocxy window new [--engine system|in-process|daemon]`.
    private static func parseWindowNew(arguments: [String]) throws -> ParsedCommand {
        var engine: String?
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--engine" {
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "window new", argument: "engine")
                }
                let value = arguments[index + 1]
                guard TerminalEnginePreference(cliValue: value) != nil else {
                    throw CLIError.invalidArgument(
                        command: "window new",
                        argument: value,
                        reason: "Engine must be system, in-process, or daemon"
                    )
                }
                engine = value
                index += 2
            } else {
                throw CLIError.invalidArgument(
                    command: "window new",
                    argument: arguments[index],
                    reason: "Unknown flag. Use --engine system|in-process|daemon."
                )
            }
        }
        return .windowNew(engine: engine)
    }

    /// Parses `cocxy session <subcommand>`.
    private static func parseSession(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "session", argument: "subcommand")
        }

        switch subcommand {
        case "save":
            return .sessionSave(name: arguments.dropFirst().first)
        case "restore":
            let rest = Array(arguments.dropFirst())
            guard let name = rest.first, !name.isEmpty else {
                throw CLIError.missingArgument(command: "session restore", argument: "name")
            }
            return .sessionRestore(name: name)
        case "list":
            return .sessionList
        case "delete":
            let rest = Array(arguments.dropFirst())
            guard let name = rest.first, !name.isEmpty else {
                throw CLIError.missingArgument(command: "session delete", argument: "name")
            }
            return .sessionDelete(name: name)
        default:
            throw CLIError.invalidArgument(
                command: "session",
                argument: subcommand,
                reason: "Unknown subcommand. Use save, restore, list, or delete."
            )
        }
    }

    /// Parses `cocxy capture-pane [--start <line>] [--end <line>]`.
    private static func parseCapturePane(arguments: [String]) throws -> ParsedCommand {
        var start: Int?
        var end: Int?

        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--start":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "capture-pane", argument: "start line")
                }
                start = Int(arguments[index + 1])
                index += 2
            case "--end":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "capture-pane", argument: "end line")
                }
                end = Int(arguments[index + 1])
                index += 2
            default:
                index += 1
            }
        }

        return .capturePane(start: start, end: end)
    }

    /// Parses `cocxy notification <subcommand>`.
    private static func parseNotification(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "notification", argument: "subcommand")
        }

        switch subcommand {
        case "list":
            let rest = Array(arguments.dropFirst())
            var limit: Int?
            var idx = 0
            while idx < rest.count {
                if rest[idx] == "--limit", idx + 1 < rest.count {
                    limit = Int(rest[idx + 1])
                    idx += 2
                } else {
                    idx += 1
                }
            }
            return .notificationList(limit: limit)
        case "clear":
            return .notificationClear
        default:
            throw CLIError.invalidArgument(
                command: "notification",
                argument: subcommand,
                reason: "Unknown subcommand. Use list or clear."
            )
        }
    }

    /// Parses `cocxy remote <subcommand>`.
    private static func parseRemote(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "remote", argument: "subcommand")
        }

        switch subcommand {
        case "list":
            return .remoteList
        case "connect":
            let rest = Array(arguments.dropFirst())
            guard let name = rest.first, !name.isEmpty else {
                throw CLIError.missingArgument(command: "remote connect", argument: "name")
            }
            return .remoteConnect(name: name)
        case "disconnect":
            let rest = Array(arguments.dropFirst())
            guard let name = rest.first, !name.isEmpty else {
                throw CLIError.missingArgument(command: "remote disconnect", argument: "name")
            }
            return .remoteDisconnect(name: name)
        case "status":
            return .remoteStatus(name: arguments.dropFirst().first)
        case "tunnels":
            let rest = Array(arguments.dropFirst())
            var profile: String?
            var idx = 0
            while idx < rest.count {
                if rest[idx] == "--profile", idx + 1 < rest.count {
                    profile = rest[idx + 1]
                    idx += 2
                } else {
                    idx += 1
                }
            }
            return .remoteTunnels(profile: profile)
        default:
            throw CLIError.invalidArgument(
                command: "remote",
                argument: subcommand,
                reason: "Unknown subcommand. Use list, connect, disconnect, status, or tunnels."
            )
        }
    }

    /// Parses `cocxy plugin <subcommand>`.
    private static func parsePlugin(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "plugin", argument: "subcommand")
        }

        switch subcommand {
        case "list":
            return .pluginList
        case "enable":
            let rest = Array(arguments.dropFirst())
            guard let id = rest.first, !id.isEmpty else {
                throw CLIError.missingArgument(command: "plugin enable", argument: "id")
            }
            return .pluginEnable(id: id)
        case "disable":
            let rest = Array(arguments.dropFirst())
            guard let id = rest.first, !id.isEmpty else {
                throw CLIError.missingArgument(command: "plugin disable", argument: "id")
            }
            return .pluginDisable(id: id)
        case "source":
            return try parsePluginSource(arguments: Array(arguments.dropFirst()))
        case "install":
            let rest = Array(arguments.dropFirst())
            guard let url = rest.first, !url.isEmpty else {
                throw CLIError.missingArgument(command: "plugin install", argument: "url")
            }
            let flags = rest.dropFirst()
            let replace = flags.contains("--replace")
            let unknown = flags.first { $0 != "--replace" }
            if let unknown {
                throw CLIError.invalidArgument(
                    command: "plugin install",
                    argument: unknown,
                    reason: "Unknown option. Use --replace to reinstall an existing plugin."
                )
            }
            return .pluginInstall(url: url, replaceExisting: replace)
        case "uninstall":
            let rest = Array(arguments.dropFirst())
            guard let id = rest.first, !id.isEmpty else {
                throw CLIError.missingArgument(command: "plugin uninstall", argument: "id")
            }
            return .pluginUninstall(id: id)
        default:
            throw CLIError.invalidArgument(
                command: "plugin",
                argument: subcommand,
                reason: "Unknown subcommand. Use list, enable, disable, source, install, or uninstall."
            )
        }
    }

    /// Parses `cocxy plugin source <subcommand>`.
    private static func parsePluginSource(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "plugin source", argument: "subcommand")
        }

        switch subcommand {
        case "list":
            return .pluginSourceList
        case "add":
            let rest = Array(arguments.dropFirst())
            guard let url = rest.first, !url.isEmpty else {
                throw CLIError.missingArgument(command: "plugin source add", argument: "url")
            }
            var displayName: String?
            var index = 1
            while index < rest.count {
                let argument = rest[index]
                switch argument {
                case "--name":
                    guard index + 1 < rest.count else {
                        throw CLIError.missingArgument(command: "plugin source add", argument: "name")
                    }
                    displayName = rest[index + 1]
                    index += 2
                default:
                    throw CLIError.invalidArgument(
                        command: "plugin source add",
                        argument: argument,
                        reason: "Unknown option. Use --name <display-name>."
                    )
                }
            }
            return .pluginSourceAdd(url: url, displayName: displayName)
        default:
            throw CLIError.invalidArgument(
                command: "plugin source",
                argument: subcommand,
                reason: "Unknown subcommand. Use list or add."
            )
        }
    }

    /// Parses `cocxy browser <subcommand>`.
    private static func parseBrowser(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "browser", argument: "subcommand")
        }

        switch subcommand {
        case "navigate":
            let rest = Array(arguments.dropFirst())
            guard let url = rest.first, !url.isEmpty else {
                throw CLIError.missingArgument(command: "browser navigate", argument: "url")
            }
            return .browserNavigate(url: url)
        case "back":
            return .browserBack
        case "forward":
            return .browserForward
        case "reload":
            return .browserReload
        case "state":
            return .browserGetState
        case "eval":
            let rest = Array(arguments.dropFirst())
            guard !rest.isEmpty else {
                throw CLIError.missingArgument(command: "browser eval", argument: "script")
            }
            return .browserEval(script: rest.joined(separator: " "))
        case "text":
            return .browserGetText
        case "tabs":
            return .browserListTabs
        default:
            throw CLIError.invalidArgument(
                command: "browser",
                argument: subcommand,
                reason: "Unknown subcommand. Use navigate, back, forward, reload, state, eval, text, or tabs."
            )
        }
    }

    // MARK: - SSH Parser

    /// Parses `cocxy ssh user@host [-p port] [-i identity]`.
    ///
    /// The destination can be `user@host`, `host`, or `user@host:port`.
    private static func parseSSH(arguments: [String]) throws -> ParsedCommand {
        guard let destination = arguments.first, !destination.isEmpty, !destination.hasPrefix("-") else {
            throw CLIError.missingArgument(command: "ssh", argument: "destination (user@host)")
        }

        let rest = Array(arguments.dropFirst())
        var port: Int?
        var identityFile: String?
        var idx = 0
        while idx < rest.count {
            switch rest[idx] {
            case "-p" where idx + 1 < rest.count:
                port = Int(rest[idx + 1])
                idx += 2
            case "-i" where idx + 1 < rest.count:
                identityFile = rest[idx + 1]
                idx += 2
            default:
                idx += 1
            }
        }

        return .ssh(destination: destination, port: port, identityFile: identityFile)
    }

    // MARK: - Web Terminal Parser

    private static func parseWeb(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "web", argument: "start|stop|status")
        }

        switch subcommand {
        case "start":
            let rest = Array(arguments.dropFirst())
            var bindAddress: String?
            var port: Int?
            var token: String?
            var fps: Int?
            var index = 0
            while index < rest.count {
                switch rest[index] {
                case "--bind" where index + 1 < rest.count:
                    bindAddress = rest[index + 1]
                    index += 2
                case "--port" where index + 1 < rest.count:
                    guard let parsed = Int(rest[index + 1]) else {
                        throw CLIError.invalidArgument(command: "web start", argument: rest[index + 1], reason: "port must be an integer")
                    }
                    port = parsed
                    index += 2
                case "--token" where index + 1 < rest.count:
                    token = rest[index + 1]
                    index += 2
                case "--fps" where index + 1 < rest.count:
                    guard let parsed = Int(rest[index + 1]) else {
                        throw CLIError.invalidArgument(command: "web start", argument: rest[index + 1], reason: "fps must be an integer")
                    }
                    fps = parsed
                    index += 2
                default:
                    throw CLIError.invalidArgument(command: "web start", argument: rest[index], reason: "unknown option")
                }
            }
            return .webStart(bindAddress: bindAddress, port: port, token: token, fps: fps)

        case "stop":
            return .webStop

        case "status":
            return .webStatus

        default:
            throw CLIError.invalidArgument(command: "web", argument: subcommand, reason: "Unknown subcommand. Use start, stop, or status.")
        }
    }

    // MARK: - Stream Parser

    private static func parseStream(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "stream", argument: "list|current")
        }

        switch subcommand {
        case "list":
            return .streamList
        case "current":
            guard arguments.count >= 2, let streamID = Int(arguments[1]) else {
                throw CLIError.missingArgument(command: "stream current", argument: "id")
            }
            return .streamCurrent(id: streamID)
        default:
            throw CLIError.invalidArgument(
                command: "stream",
                argument: subcommand,
                reason: "Unknown subcommand. Use list or current."
            )
        }
    }

    // MARK: - Protocol Parser

    private static func parseProtocol(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "protocol", argument: "capabilities|viewport|send")
        }

        switch subcommand {
        case "capabilities":
            return .protocolCapabilities
        case "viewport":
            let rest = Array(arguments.dropFirst())
            var requestID: String?
            var index = 0
            while index < rest.count {
                switch rest[index] {
                case "--request-id" where index + 1 < rest.count:
                    requestID = rest[index + 1]
                    index += 2
                default:
                    throw CLIError.invalidArgument(
                        command: "protocol viewport",
                        argument: rest[index],
                        reason: "unknown option"
                    )
                }
            }
            return .protocolViewport(requestID: requestID)
        case "send":
            let rest = Array(arguments.dropFirst())
            var type: String?
            var json: String?
            var index = 0
            while index < rest.count {
                switch rest[index] {
                case "--type" where index + 1 < rest.count:
                    type = rest[index + 1]
                    index += 2
                case "--json" where index + 1 < rest.count:
                    json = rest[index + 1]
                    index += 2
                default:
                    throw CLIError.invalidArgument(
                        command: "protocol send",
                        argument: rest[index],
                        reason: "unknown option"
                    )
                }
            }
            guard let type, !type.isEmpty else {
                throw CLIError.missingArgument(command: "protocol send", argument: "--type")
            }
            guard let json, !json.isEmpty else {
                throw CLIError.missingArgument(command: "protocol send", argument: "--json")
            }
            return .protocolSend(type: type, json: json)
        default:
            throw CLIError.invalidArgument(
                command: "protocol",
                argument: subcommand,
                reason: "Unknown subcommand. Use capabilities, viewport, or send."
            )
        }
    }

    // MARK: - Core Parser

    private static func parseCore(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(
                command: "core",
                argument: "reset|signal|process|modes|search|ligatures|protocol|selection|font|preedit|semantic"
            )
        }

        switch subcommand {
        case "reset":
            return .coreReset
        case "signal":
            guard arguments.count >= 2 else {
                throw CLIError.missingArgument(command: "core signal", argument: "signal")
            }
            return .coreSignal(signal: arguments[1])
        case "process":
            return .coreProcess
        case "modes", "mode":
            return .coreModes
        case "search":
            return .coreSearch
        case "ligatures", "ligature":
            return .coreLigatures
        case "protocol":
            return .coreProtocol
        case "selection":
            return .coreSelection
        case "font", "font-metrics":
            return .coreFontMetrics
        case "preedit":
            return .corePreedit
        case "semantic":
            let rest = Array(arguments.dropFirst())
            var limit: Int?
            var index = 0
            while index < rest.count {
                switch rest[index] {
                case "--limit" where index + 1 < rest.count:
                    guard let parsed = Int(rest[index + 1]), parsed > 0 else {
                        throw CLIError.invalidArgument(
                            command: "core semantic",
                            argument: rest[index + 1],
                            reason: "limit must be a positive integer"
                        )
                    }
                    limit = parsed
                    index += 2
                default:
                    throw CLIError.invalidArgument(
                        command: "core semantic",
                        argument: rest[index],
                        reason: "unknown option"
                    )
                }
            }
            return .coreSemantic(limit: limit)
        default:
            throw CLIError.invalidArgument(
                command: "core",
                argument: subcommand,
                reason: "Unknown subcommand. Use reset, signal, process, modes, search, ligatures, protocol, selection, font, preedit, or semantic."
            )
        }
    }

    // MARK: - Block Parser

    private static func parseBlock(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "block", argument: "list|outputs|copy|rerun")
        }

        switch subcommand {
        case "list":
            let rest = Array(arguments.dropFirst())
            var limit: Int?
            var index = 0
            while index < rest.count {
                switch rest[index] {
                case "--limit" where index + 1 < rest.count:
                    guard let parsed = Int(rest[index + 1]), parsed > 0 else {
                        throw CLIError.invalidArgument(
                            command: "block list",
                            argument: rest[index + 1],
                            reason: "limit must be a positive integer"
                        )
                    }
                    limit = parsed
                    index += 2
                default:
                    throw CLIError.invalidArgument(
                        command: "block list",
                        argument: rest[index],
                        reason: "unknown option"
                    )
                }
            }
            return .blockList(limit: limit)

        case "outputs":
            let rest = Array(arguments.dropFirst())
            var limit: Int?
            var index = 0
            while index < rest.count {
                switch rest[index] {
                case "--limit" where index + 1 < rest.count:
                    guard let parsed = Int(rest[index + 1]), parsed > 0 else {
                        throw CLIError.invalidArgument(
                            command: "block outputs",
                            argument: rest[index + 1],
                            reason: "limit must be a positive integer"
                        )
                    }
                    limit = parsed
                    index += 2
                default:
                    throw CLIError.invalidArgument(
                        command: "block outputs",
                        argument: rest[index],
                        reason: "unknown option"
                    )
                }
            }
            return .blockOutputs(limit: limit)

        case "copy":
            guard arguments.count >= 2, let blockID = UInt64(arguments[1]), blockID > 0 else {
                throw CLIError.missingArgument(command: "block copy", argument: "id")
            }
            let rest = Array(arguments.dropFirst(2))
            var field = "output"
            var index = 0
            while index < rest.count {
                switch rest[index] {
                case "--field" where index + 1 < rest.count:
                    let parsedField = rest[index + 1].lowercased()
                    guard parsedField == "command"
                        || parsedField == "output"
                        || parsedField == "both" else {
                        throw CLIError.invalidArgument(
                            command: "block copy",
                            argument: parsedField,
                            reason: "field must be command, output, or both"
                        )
                    }
                    field = parsedField
                    index += 2
                default:
                    throw CLIError.invalidArgument(
                        command: "block copy",
                        argument: rest[index],
                        reason: "unknown option"
                    )
                }
            }
            return .blockCopy(id: blockID, field: field)

        case "rerun":
            guard arguments.count >= 2, let blockID = UInt64(arguments[1]), blockID > 0 else {
                throw CLIError.missingArgument(command: "block rerun", argument: "id")
            }
            if arguments.count > 2 {
                throw CLIError.invalidArgument(
                    command: "block rerun",
                    argument: arguments.dropFirst(2).joined(separator: " "),
                    reason: "unknown option"
                )
            }
            return .blockRerun(id: blockID)

        default:
            throw CLIError.invalidArgument(
                command: "block",
                argument: subcommand,
                reason: "Unknown subcommand. Use list, outputs, copy, or rerun."
            )
        }
    }

    // MARK: - Image Parser

    private static func parseImage(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "image", argument: "list|delete|clear")
        }

        switch subcommand {
        case "list":
            return .imageList
        case "delete":
            guard arguments.count >= 2, let imageID = Int(arguments[1]) else {
                throw CLIError.missingArgument(command: "image delete", argument: "id")
            }
            return .imageDelete(id: imageID)
        case "clear":
            return .imageClear
        default:
            throw CLIError.invalidArgument(
                command: "image",
                argument: subcommand,
                reason: "Unknown subcommand. Use list, delete, or clear."
            )
        }
    }

    // MARK: - Notebook Parser

    private static func parseNotebook(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "notebook", argument: "import|export|run")
        }

        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "import":
            let options = try parseNotebookConversionOptions(
                command: "notebook import",
                arguments: rest
            )
            return .notebookImport(
                inputPath: options.input,
                outputPath: options.output,
                force: options.force
            )
        case "export":
            let options = try parseNotebookConversionOptions(
                command: "notebook export",
                arguments: rest
            )
            return .notebookExport(
                inputPath: options.input,
                outputPath: options.output,
                force: options.force
            )
        case "export-html":
            let options = try parseNotebookConversionOptions(
                command: "notebook export-html",
                arguments: rest
            )
            return .notebookExportHTML(
                inputPath: options.input,
                outputPath: options.output,
                force: options.force
            )
        case "template":
            return try parseNotebookTemplate(arguments: rest)
        case "run":
            let options = try parseNotebookRunOptions(arguments: rest)
            return .notebookRun(
                inputPath: options.input,
                outputPath: options.output,
                workingDirectory: options.workingDirectory,
                timeoutSeconds: options.timeoutSeconds,
                sandbox: options.sandbox,
                continueOnFailure: options.continueOnFailure
            )
        default:
            throw CLIError.invalidArgument(
                command: "notebook",
                argument: subcommand,
                reason: "Unknown subcommand. Use import, export, export-html, template, or run."
            )
        }
    }

    private static func parseNotebookTemplate(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "notebook template", argument: "list|create")
        }

        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "list":
            guard rest.isEmpty else {
                throw CLIError.invalidArgument(
                    command: "notebook template list",
                    argument: rest[0],
                    reason: "No arguments are accepted."
                )
            }
            return .notebookTemplateList
        case "create":
            let options = try parseNotebookTemplateCreateOptions(arguments: rest)
            return .notebookTemplateCreate(
                templateID: options.templateID,
                outputPath: options.output,
                force: options.force
            )
        default:
            throw CLIError.invalidArgument(
                command: "notebook template",
                argument: subcommand,
                reason: "Unknown subcommand. Use list or create."
            )
        }
    }

    private static func parseNotebookTemplateCreateOptions(
        arguments: [String]
    ) throws -> (templateID: String, output: String, force: Bool) {
        var templateID: String?
        var output: String?
        var force = false
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--output", "-o":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "notebook template create", argument: "output")
                }
                output = arguments[index + 1]
                index += 2
            case "--force":
                force = true
                index += 1
            default:
                if token.hasPrefix("-") {
                    throw CLIError.invalidArgument(
                        command: "notebook template create",
                        argument: token,
                        reason: "Unknown option. Valid flags: --output, -o, --force."
                    )
                }
                guard templateID == nil else {
                    throw CLIError.invalidArgument(
                        command: "notebook template create",
                        argument: token,
                        reason: "Only one template id is accepted."
                    )
                }
                templateID = token
                index += 1
            }
        }

        guard let templateID, !templateID.isEmpty else {
            throw CLIError.missingArgument(command: "notebook template create", argument: "template-id")
        }
        guard let output, !output.isEmpty else {
            throw CLIError.missingArgument(command: "notebook template create", argument: "output")
        }
        return (templateID, output, force)
    }

    private static func parseNotebookConversionOptions(
        command: String,
        arguments: [String]
    ) throws -> (input: String, output: String, force: Bool) {
        var input: String?
        var output: String?
        var force = false
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--output", "-o":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: command, argument: "output")
                }
                output = arguments[index + 1]
                index += 2
            case "--force":
                force = true
                index += 1
            default:
                if token.hasPrefix("-") {
                    throw CLIError.invalidArgument(
                        command: command,
                        argument: token,
                        reason: "Unknown option. Valid flags: --output, -o, --force."
                    )
                }
                guard input == nil else {
                    throw CLIError.invalidArgument(
                        command: command,
                        argument: token,
                        reason: "Only one input path is accepted."
                    )
                }
                input = token
                index += 1
            }
        }

        guard let input, !input.isEmpty else {
            throw CLIError.missingArgument(command: command, argument: "input")
        }
        guard let output, !output.isEmpty else {
            throw CLIError.missingArgument(command: command, argument: "output")
        }
        return (input, output, force)
    }

    private static func parseNotebookRunOptions(
        arguments: [String]
    ) throws -> (
        input: String,
        output: String?,
        workingDirectory: String?,
        timeoutSeconds: Double?,
        sandbox: String,
        continueOnFailure: Bool
    ) {
        var input: String?
        var output: String?
        var workingDirectory: String?
        var timeoutSeconds: Double?
        var sandbox = "workspace"
        var continueOnFailure = false
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--output", "-o":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "notebook run", argument: "output")
                }
                output = arguments[index + 1]
                index += 2
            case "--cwd":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "notebook run", argument: "cwd")
                }
                workingDirectory = arguments[index + 1]
                index += 2
            case "--timeout":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "notebook run", argument: "timeout")
                }
                guard let parsed = Double(arguments[index + 1]), parsed > 0 else {
                    throw CLIError.invalidArgument(
                        command: "notebook run",
                        argument: arguments[index + 1],
                        reason: "Timeout must be a positive number of seconds."
                    )
                }
                timeoutSeconds = parsed
                index += 2
            case "--sandbox":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "notebook run", argument: "sandbox")
                }
                let mode = arguments[index + 1]
                guard ["workspace", "none"].contains(mode) else {
                    throw CLIError.invalidArgument(
                        command: "notebook run",
                        argument: mode,
                        reason: "Sandbox must be one of: workspace, none."
                    )
                }
                sandbox = mode
                index += 2
            case "--continue-on-failure":
                continueOnFailure = true
                index += 1
            default:
                if token.hasPrefix("-") {
                    throw CLIError.invalidArgument(
                        command: "notebook run",
                        argument: token,
                        reason: "Unknown option. Valid flags: --output, -o, --cwd, --timeout, --sandbox, --continue-on-failure."
                    )
                }
                guard input == nil else {
                    throw CLIError.invalidArgument(
                        command: "notebook run",
                        argument: token,
                        reason: "Only one input path is accepted."
                    )
                }
                input = token
                index += 1
            }
        }

        guard let input, !input.isEmpty else {
            throw CLIError.missingArgument(command: "notebook run", argument: "input")
        }
        return (input, output, workingDirectory, timeoutSeconds, sandbox, continueOnFailure)
    }

    // MARK: - Workflow Parser

    private static func parseWorkflow(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "workflow", argument: "run")
        }
        if isHelpToken(subcommand) {
            return .help
        }

        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "run":
            let options = try parseWorkflowRunOptions(arguments: rest)
            return .workflowRun(
                inputPath: options.input,
                workingDirectory: options.workingDirectory
            )
        default:
            throw CLIError.invalidArgument(
                command: "workflow",
                argument: subcommand,
                reason: "Unknown subcommand. Use run."
            )
        }
    }

    private static func parseWorkflowRunOptions(
        arguments: [String]
    ) throws -> (input: String, workingDirectory: String?) {
        var input: String?
        var workingDirectory: String?
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--cwd":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument(command: "workflow run", argument: "cwd")
                }
                workingDirectory = arguments[index + 1]
                index += 2
            default:
                if token.hasPrefix("-") {
                    throw CLIError.invalidArgument(
                        command: "workflow run",
                        argument: token,
                        reason: "Unknown option. Valid flags: --cwd."
                    )
                }
                guard input == nil else {
                    throw CLIError.invalidArgument(
                        command: "workflow run",
                        argument: token,
                        reason: "Only one input path is accepted."
                    )
                }
                input = token
                index += 1
            }
        }

        guard let input, !input.isEmpty else {
            throw CLIError.missingArgument(command: "workflow run", argument: "input")
        }
        return (input, workingDirectory)
    }

    // MARK: - Skill Parser

    private static func parseSkill(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "skill", argument: "list")
        }
        if isHelpToken(subcommand) {
            return .help
        }

        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "list":
            guard rest.isEmpty else {
                throw CLIError.invalidArgument(
                    command: "skill list",
                    argument: rest.first ?? "",
                    reason: "`skill list` takes no arguments."
                )
            }
            return .skillList
        case "source":
            return try parseSkillSource(arguments: rest)
        case "install":
            guard let url = rest.first, !url.isEmpty else {
                throw CLIError.missingArgument(command: "skill install", argument: "url")
            }
            let flags = rest.dropFirst()
            let replace = flags.contains("--replace")
            let unknown = flags.first { $0 != "--replace" }
            if let unknown {
                throw CLIError.invalidArgument(
                    command: "skill install",
                    argument: unknown,
                    reason: "Unknown option. Use --replace to reinstall an existing skill."
                )
            }
            return .skillInstall(url: url, replaceExisting: replace)
        case "uninstall":
            guard let id = rest.first, !id.isEmpty else {
                throw CLIError.missingArgument(command: "skill uninstall", argument: "id")
            }
            return .skillUninstall(id: id)
        default:
            throw CLIError.invalidArgument(
                command: "skill",
                argument: subcommand,
                reason: "Unknown subcommand. Use list, source, install, or uninstall."
            )
        }
    }

    private static func parseSkillSource(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(command: "skill source", argument: "subcommand")
        }

        switch subcommand {
        case "list":
            return .skillSourceList
        case "add":
            let rest = Array(arguments.dropFirst())
            guard let url = rest.first, !url.isEmpty else {
                throw CLIError.missingArgument(command: "skill source add", argument: "url")
            }
            var displayName: String?
            var index = 1
            while index < rest.count {
                let argument = rest[index]
                switch argument {
                case "--name":
                    guard index + 1 < rest.count else {
                        throw CLIError.missingArgument(command: "skill source add", argument: "name")
                    }
                    displayName = rest[index + 1]
                    index += 2
                default:
                    throw CLIError.invalidArgument(
                        command: "skill source add",
                        argument: argument,
                        reason: "Unknown option. Use --name <display-name>."
                    )
                }
            }
            return .skillSourceAdd(url: url, displayName: displayName)
        default:
            throw CLIError.invalidArgument(
                command: "skill source",
                argument: subcommand,
                reason: "Unknown subcommand. Use list or add."
            )
        }
    }

    /// Parses `cocxy worktree <subcommand> [...]`.
    private static func parseWorktree(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(
                command: "worktree",
                argument: "add|create|list|focus|remove|prune"
            )
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "add", "create":
            var agent: String?
            var branch: String?
            var baseRef: String?
            var positionalBranch: String?
            var index = 0
            while index < rest.count {
                let token = rest[index]
                switch token {
                case "--agent":
                    guard index + 1 < rest.count else {
                        throw CLIError.missingArgument(
                            command: "worktree add",
                            argument: "value for --agent"
                        )
                    }
                    agent = rest[index + 1]
                    index += 2
                case "--branch":
                    guard index + 1 < rest.count else {
                        throw CLIError.missingArgument(
                            command: "worktree add",
                            argument: "value for --branch"
                        )
                    }
                    branch = rest[index + 1]
                    index += 2
                case "--base-ref":
                    guard index + 1 < rest.count else {
                        throw CLIError.missingArgument(
                            command: "worktree add",
                            argument: "value for --base-ref"
                        )
                    }
                    baseRef = rest[index + 1]
                    index += 2
                default:
                    if subcommand == "create", positionalBranch == nil, !token.hasPrefix("-") {
                        positionalBranch = token
                        index += 1
                        continue
                    }
                    throw CLIError.invalidArgument(
                        command: "worktree \(subcommand)",
                        argument: token,
                        reason: "Unknown option. Valid flags: --agent, --branch, --base-ref."
                    )
                }
            }
            branch = branch ?? positionalBranch
            return .worktreeAdd(agent: agent, branch: branch, baseRef: baseRef)

        case "list":
            return .worktreeList

        case "focus":
            guard rest.count == 1, let id = rest.first, !id.isEmpty else {
                throw CLIError.missingArgument(
                    command: "worktree focus",
                    argument: "id"
                )
            }
            return .worktreeFocus(id: id)

        case "remove":
            guard let id = rest.first else {
                throw CLIError.missingArgument(
                    command: "worktree remove",
                    argument: "id"
                )
            }
            var force = false
            for token in rest.dropFirst() {
                if token == "--force" || token == "-f" {
                    force = true
                } else {
                    throw CLIError.invalidArgument(
                        command: "worktree remove",
                        argument: token,
                        reason: "Unknown option. Only --force / -f is supported."
                    )
                }
            }
            return .worktreeRemove(id: id, force: force)

        case "prune":
            return .worktreePrune

        case "cleanup-merged", "cleanup":
            var baseRef: String?
            var force = false
            var dryRun = false
            var index = 0
            while index < rest.count {
                let token = rest[index]
                switch token {
                case "--base-ref":
                    guard index + 1 < rest.count else {
                        throw CLIError.missingArgument(
                            command: "worktree cleanup-merged",
                            argument: "value for --base-ref"
                        )
                    }
                    baseRef = rest[index + 1]
                    index += 2
                case "--force":
                    force = true
                    index += 1
                case "--dry-run":
                    dryRun = true
                    index += 1
                default:
                    throw CLIError.invalidArgument(
                        command: "worktree cleanup-merged",
                        argument: token,
                        reason: "Unknown option. Valid flags: --base-ref, --force, --dry-run."
                    )
                }
            }
            return .worktreeCleanupMerged(baseRef: baseRef, force: force, dryRun: dryRun)

        default:
            throw CLIError.invalidArgument(
                command: "worktree",
                argument: subcommand,
                reason: "Unknown subcommand. Use add, create, list, focus, remove, prune, or cleanup-merged."
            )
        }
    }

    /// Parses `cocxy github <subcommand> [...]`.
    private static func parseGitHub(arguments: [String]) throws -> ParsedCommand {
        guard let subcommand = arguments.first else {
            throw CLIError.missingArgument(
                command: "github",
                argument: "status|prs|issues|open|refresh"
            )
        }
        if isHelpToken(subcommand) {
            return .help
        }
        let rest = Array(arguments.dropFirst())
        if isOnlyHelpRequest(rest) {
            return .help
        }
        switch subcommand {
        case "status":
            guard rest.isEmpty else {
                throw CLIError.invalidArgument(
                    command: "github status",
                    argument: rest.first ?? "",
                    reason: "`github status` takes no arguments."
                )
            }
            return .githubStatus

        case "prs":
            let parsed = try parseGitHubListOptions(rest: rest, subcommand: "github prs")
            return .githubPRs(state: parsed.state, limit: parsed.limit)

        case "issues":
            let parsed = try parseGitHubListOptions(rest: rest, subcommand: "github issues")
            return .githubIssues(state: parsed.state, limit: parsed.limit)

        case "open":
            guard rest.isEmpty else {
                throw CLIError.invalidArgument(
                    command: "github open",
                    argument: rest.first ?? "",
                    reason: "`github open` takes no arguments."
                )
            }
            return .githubOpen

        case "refresh":
            guard rest.isEmpty else {
                throw CLIError.invalidArgument(
                    command: "github refresh",
                    argument: rest.first ?? "",
                    reason: "`github refresh` takes no arguments."
                )
            }
            return .githubRefresh

        case "pr-merge":
            return try parseGitHubPRMergeArgs(rest: rest)

        default:
            throw CLIError.invalidArgument(
                command: "github",
                argument: subcommand,
                reason: "Unknown subcommand. Use status, prs, issues, open, refresh, or pr-merge."
            )
        }
    }

    /// Parses the `github pr-merge` argument list. Exactly one of
    /// `--squash`, `--merge`, or `--rebase` is required; the other
    /// flags are optional. Mirrors `gh pr merge --help` so users
    /// familiar with the upstream tool find the same surface.
    private static func parseGitHubPRMergeArgs(rest: [String]) throws -> ParsedCommand {
        var method: GitHubMergeMethodCLI?
        var prNumber: Int?
        var deleteBranch: Bool = true
        var subject: String?
        var body: String?
        var index = 0
        while index < rest.count {
            let arg = rest[index]
            switch arg {
            case "--squash", "-s":
                if method != nil {
                    throw CLIError.invalidArgument(
                        command: "github pr-merge",
                        argument: arg,
                        reason: "Pass exactly one of --squash, --merge, --rebase."
                    )
                }
                method = .squash
                index += 1
            case "--merge", "-m":
                if method != nil {
                    throw CLIError.invalidArgument(
                        command: "github pr-merge",
                        argument: arg,
                        reason: "Pass exactly one of --squash, --merge, --rebase."
                    )
                }
                method = .merge
                index += 1
            case "--rebase", "-r":
                if method != nil {
                    throw CLIError.invalidArgument(
                        command: "github pr-merge",
                        argument: arg,
                        reason: "Pass exactly one of --squash, --merge, --rebase."
                    )
                }
                method = .rebase
                index += 1
            case "--pr":
                guard index + 1 < rest.count, let parsed = Int(rest[index + 1]), parsed > 0 else {
                    throw CLIError.invalidArgument(
                        command: "github pr-merge",
                        argument: arg,
                        reason: "--pr expects a positive integer."
                    )
                }
                prNumber = parsed
                index += 2
            case "--no-delete-branch":
                deleteBranch = false
                index += 1
            case "--delete-branch":
                deleteBranch = true
                index += 1
            case "--subject":
                guard index + 1 < rest.count else {
                    throw CLIError.invalidArgument(
                        command: "github pr-merge",
                        argument: arg,
                        reason: "--subject expects a value."
                    )
                }
                subject = rest[index + 1]
                index += 2
            case "--body":
                guard index + 1 < rest.count else {
                    throw CLIError.invalidArgument(
                        command: "github pr-merge",
                        argument: arg,
                        reason: "--body expects a value."
                    )
                }
                body = rest[index + 1]
                index += 2
            default:
                throw CLIError.invalidArgument(
                    command: "github pr-merge",
                    argument: arg,
                    reason: "Unknown flag. See `cocxy github pr-merge --help`."
                )
            }
        }
        guard let resolvedMethod = method else {
            throw CLIError.invalidArgument(
                command: "github pr-merge",
                argument: "",
                reason: "Pass exactly one of --squash, --merge, --rebase."
            )
        }
        return .githubPRMerge(
            method: resolvedMethod,
            prNumber: prNumber,
            deleteBranch: deleteBranch,
            subject: subject,
            body: body
        )
    }

    /// Shared `--state` / `--limit` parser for `github prs` and
    /// `github issues`. Returns raw values so the caller can thread
    /// them into the matching `ParsedCommand` case verbatim.
    private static func parseGitHubListOptions(
        rest: [String],
        subcommand: String
    ) throws -> (state: String?, limit: Int?) {
        var state: String?
        var limit: Int?
        var index = 0
        while index < rest.count {
            let token = rest[index]
            switch token {
            case "--state":
                guard index + 1 < rest.count else {
                    throw CLIError.missingArgument(
                        command: subcommand,
                        argument: "value for --state"
                    )
                }
                state = rest[index + 1]
                index += 2
            case "--limit":
                guard index + 1 < rest.count else {
                    throw CLIError.missingArgument(
                        command: subcommand,
                        argument: "value for --limit"
                    )
                }
                guard let value = Int(rest[index + 1]) else {
                    throw CLIError.invalidArgument(
                        command: subcommand,
                        argument: rest[index + 1],
                        reason: "--limit must be a positive integer."
                    )
                }
                limit = value
                index += 2
            default:
                throw CLIError.invalidArgument(
                    command: subcommand,
                    argument: token,
                    reason: "Unknown option. Valid flags: --state, --limit."
                )
            }
        }
        return (state, limit)
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
        for command in CLICommand.allCases where !command.isInternal {
            let padding = String(
                repeating: " ",
                count: max(1, 52 - command.usageExample.count)
            )
            lines.append("  \(command.usageExample)\(padding)\(command.helpDescription)")
        }
        lines.append("  cocxy open <path> [--editor <id>] [--line <n>] [--column <n>] Open a file or folder in a registered editor")
        lines.append("")
        lines.append("OPTIONS:")
        lines.append("  --help, -h              Show this help message")
        lines.append("  --version, -v           Show version")
        lines.append("")
        lines.append("ENGINE VALUES:")
        lines.append("  system, in-process, daemon")
        lines.append("  aliases: default, auto, inprocess, core, cocxycore, pty-daemon, ptydaemon")
        lines.append("")
        lines.append("EXAMPLES:")
        lines.append("  cocxy notify \"Build complete\"")
        lines.append("  cocxy new-tab --dir ~/projects --engine daemon")
        lines.append("  cocxy split --dir h")
        lines.append("  cocxy list-tabs | jq '.'")
        lines.append("  cocxy tab rename <id> \"My Tab\"")
        lines.append("  cocxy dashboard toggle")
        lines.append("  cocxy search \"error\" --regex")
        lines.append("  cocxy search \"network timeout\" --tab <id>")
        lines.append("  cocxy config get font.size")
        lines.append("  cocxy theme set dracula")
        lines.append("  cocxy core semantic --limit 5")
        lines.append("  printf 'echo hi\\r' | cocxy send --stdin")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Generates the version output.
    public static func versionText() -> String {
        return "cocxy \(version)"
    }
}
