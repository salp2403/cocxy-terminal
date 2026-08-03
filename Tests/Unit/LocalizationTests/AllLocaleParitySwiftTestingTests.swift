// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("All localization resources")
struct AllLocaleParitySwiftTestingTests {
    private static let localeCodes = [
        "en", "es", "ar", "bs", "da", "de", "fr", "it", "ja", "km", "ko",
        "no", "pl", "pt-BR", "ru", "th", "tr", "uk", "vi", "zh-CN", "zh-TW",
    ]

    private static let intentionalTechnicalCloneKeys: Set<String> = [
        "activity.export.json",
        "browser.devTools.network.column.url",
        "browser.devTools.tab.dom",
        "browser.dialog.ok",
        "browser.import.filters.allowPlaceholder",
        "browser.import.filters.blockPlaceholder",
        "codeReview.diff.line.accessibility",
        "codeReview.gitWorkflow.commitPlaceholder",
        "codeReview.gitWorkflow.placeholder.branch",
        "codeReview.toolbar.git",
        "command.category.cli",
        "common.ok",
        "dbCloud.title",
        "horizontalTab.add.markdown",
        "keybindings.category.markdown",
        "macros.returnKey",
        "markdown.toolbar.untitledFile",
        "pip.window.title",
        "plugins.builtin.cocxy-aws-cli-helper.name",
        "plugins.builtin.cocxy-azure-cli.name",
        "preferences.about.license",
        "preferences.appearance.aurora.section",
        "preferences.appearance.fontPreview.command",
        "preferences.editor.foundationModels",
        "preferences.mcp.json.section",
        "preferences.section.github",
        "preferences.section.spotlight",
        "projectHome.fanOut.pathPlaceholder",
        "projectHome.team.defaultTeammates",
        "remoteWorkspace.daemon.forwardSpec.placeholder",
        "remoteWorkspace.daemon.pid",
        "remoteWorkspace.keys.name.placeholder",
        "remoteWorkspace.profile.accessibility",
        "remoteWorkspace.profileEditor.placeholder.environmentKey",
        "remoteWorkspace.profileEditor.placeholder.environmentValue",
        "remoteWorkspace.profileEditor.placeholder.group",
        "remoteWorkspace.profileEditor.placeholder.host",
        "remoteWorkspace.profileEditor.placeholder.jumpHost",
        "remoteWorkspace.profileEditor.placeholder.name",
        "remoteWorkspace.profileEditor.placeholder.port",
        "remoteWorkspace.profileEditor.placeholder.username",
        "remoteWorkspace.proxy.httpTitle",
        "remoteWorkspace.relay.remotePort",
        "remoteWorkspace.sftp.entry.accessibility",
        "remoteWorkspace.subPanel.sftp",
        "shortcutHints.debug.offsetX",
        "shortcutHints.debug.offsetY",
        "taskQueue.composer.pipeline",
        "taskQueue.composer.taskIDPlaceholder",
        "taskQueue.composer.timeZonePlaceholder",
        "taskQueue.source.pipeline",
        "taskQueue.trigger.cron.detail",
        "taskRun.compare.costUnavailable",
        "templates.builtIn.docker-service.name",
        "templates.builtIn.flutter-app.name",
        "templates.builtIn.go-module.name",
        "templates.builtIn.node-typescript.name",
        "templates.builtIn.php-composer.name",
        "templates.builtIn.ruby-gem.name",
        "templates.defaultDestinationName",
        "terminal.blockOverlay.commandPlaceholder",
        "terminal.blockOverlay.status.exit",
        "terminal.blockOverlay.status.ok",
        "terminal.blockOverlay.status.run",
        "terminal.smartCopy.detectedTitle",
        "theme.browser.preview.local",
        "theme.browser.preview.main",
        "theme.browser.preview.title",
        "vault.export.json",
        "vault.export.markdown",
        "vault.search.shortcutHint",
        "vault.sort.alphabetical",
        "verticalTab.density.compact.short",
        "verticalTab.density.detailed.short",
        "verticalTab.density.summary.short",
        "verticalTab.primary.command.short",
        "verticalTab.primary.directory.short",
        "verticalTab.primary.process.short",
        "welcome.title",
        "workflow.defaultSource.command",
        "workspaceToolbar.panel.markdown",
    ]

    private static let intentionalNativeTechnicalValues: [String: Set<String>] = [
        "es": [
            "%d alias", "%d commit", "%d commits", "%d conn", "%d err", "%d error",
            "Auto", "Commits", "Cookies", "DB/Cloud", "Daemon", "Diffs", "Editor", "Err",
            "Error", "Error: %@", "General", "Hooks", "Hotfix", "Local", "Local:", "Macros",
            "Manual", "Neutral", "PRs", "Panel", "Pipeline", "Plugins", "Proxy", "Relay",
            "Terminal %d", "Terminal", "Terminal: %@", "Tokens", "Variables", "Visual", "Zoom",
            "base %@", "base: %@", "error", "inspector", "manual",
        ],
        "bs": [
            "%@, %@, plus %d, minus %d", "%d alias", "%d commit", "Agent", "Agent: %@",
            "DOM element: %@", "Filter: %@", "Font", "Format", "Host", "Port", "Port:",
            "Proxy", "Push", "SOCKS5 Proxy", "SOCKS5 port", "Terminal %d", "Terminal",
            "Terminal: %@",
        ],
        "da": [
            "%@, %@, plus %d, minus %d", "%d alias", "%d commit", "%d commits", "%d hunks",
            "%d match", "%d matches", "%d note", "%d reference", "%d session", "%d snippet",
            "%d snippets", "Agent", "Agent: %@", "Auto", "Branch", "Browser", "Browser: %@",
            "Commits", "Container", "Cookies", "Dashboard", "Data", "Database", "Destination",
            "Destination: %@", "Diffs", "Downloads", "Editor", "Filter: %@", "Find", "Find...",
            "Format", "Hooks", "Hotfix", "Input", "Integration", "Issues", "Layout", "Liquid",
            "Minimal", "Navigation", "Neutral", "Note", "Note: %@", "Output", "Pipeline",
            "Plugins", "Port", "Port:", "Prompt", "Proxy", "Push", "Reference", "Region",
            "Replay", "Repository", "Send", "Session", "Shell", "Skills", "Snippet", "Snippets",
            "Standard", "Stop", "Subagent", "System (%@)", "System", "Terminal %d", "Terminal",
            "Terminal: %@", "Timing", "Tokens", "Top", "Type", "Version %@", "Workflow", "Zoom",
            "base %@", "branch %@", "ok",
        ],
        "de": [
            "%@ (Remote)", "%@, %@, plus %d, minus %d", "%d Skill", "%d Skills",
            "%d files · %d hunks · +%d / -%d", "Agent", "Agent: %@", "Auto", "Backup",
            "Backups", "Block", "Branch", "Branches", "Browser", "Browser: %@", "Cloud",
            "Commit & Push", "Commits", "Container", "Cookies", "DB/Cloud", "Daemon",
            "Dashboard", "Diffs", "Downloads", "Editor", "Experiment", "Filter: %@", "Format",
            "Hooks", "Host", "Hosts:", "Hotfix", "Info", "Integration", "Issues", "Layout",
            "Minimal", "Mode", "Name", "Navigation", "Neutral", "Nightly", "Notebook", "Optional",
            "PRs", "Passphrase", "Pipeline", "Plugins", "Port", "Port:", "Proxy", "Push",
            "Rebase & Merge", "Region", "Relay", "Repository", "Reviews", "Shell", "Skills",
            "Splits", "Squash & Merge", "Standard", "Subagent", "System (%@)", "System", "Tab %d",
            "Tab: %@", "Tabs", "Terminal %d", "Terminal", "Terminal: %@", "Tokens", "Tool",
            "Tool: %@", "Updates", "Version %@", "Workflow", "Workflows", "Worktree",
            "Worktree: %@", "Worktrees", "Zoom", "base %@", "nowrap", "wrap",
        ],
        "fr": [
            "%d agents", "%d alias", "%d commit", "%d commits", "%d conn", "%d err", "%d note",
            "%d notes", "%d session", "%d sessions", "%d suggestions", "1 suggestion", "Agent",
            "Agents", "Arguments", "Auto", "Branches", "Cloud", "Commits", "Console", "Cookies",
            "DB/Cloud", "Daemon", "Date", "Destination", "Diffs", "Err", "Format", "Hooks",
            "Interaction", "Local", "Macros", "Mode", "Navigation", "Nightly", "Note",
            "Notes — %d note", "Notes — %d notes", "Notes", "Notification",
            "Notifications (Cmd+Alt+Shift+I)", "Notifications", "Opaque", "Pipeline", "Port", "Proxy",
            "Services", "Session", "Sessions", "Shell", "Source", "Sources", "Stable", "Standard",
            "Terminal %d", "Terminal", "Tunnels", "Type", "Variables", "Version %@", "action",
            "actions", "agents", "base %@", "ok", "ports", "remote",
        ],
        "it": [
            "%d alias", "%d commit", "%d conn", "%d file", "%d snippet", "Auto", "Backup",
            "Branch", "Browser", "Browser: %@", "Cloud", "Commits", "Console", "DB/Cloud",
            "Dashboard", "Database", "Directory", "Editor", "Err", "File %@", "File", "Focus",
            "Font", "Host", "Hotfix", "Info", "Input", "Max:", "Nightly", "Notebook", "Output",
            "PRs", "Passphrase", "Password", "Pipeline", "Privacy", "Prompt", "Provider", "Proxy",
            "Push", "Relay", "Replay", "Repository", "SOCKS5 Proxy", "Shell", "Snippet", "Snippets",
            "Standard", "Warn", "Worktree", "Worktree: %@", "Worktrees", "Zoom", "base %@",
            "base: %@", "ok",
        ],
        "no": [
            "%d alias", "%d commit", "%d commits", "Agent", "Agent: %@", "Auto", "Data",
            "Database", "Filter: %@", "Format", "Git Assistant", "Info", "Minimal", "PRs", "Panel",
            "Port", "Port:", "Proxy", "Region", "Send", "Standard", "System (%@)", "System",
            "Terminal %d", "Terminal", "Terminal: %@", "Type", "Zoom",
        ],
        "pl": [
            "%d alias", "Agent", "Agent: %@", "Auto", "DB/Cloud", "Folder", "Folder: %@", "Format",
            "Git Assistant", "Host", "Info", "Liquid", "Opaque", "Panel", "Port", "Port:", "Proxy",
            "Push", "Region", "System", "Terminal %d", "Terminal", "Terminal: %@", "Visual", "ok",
        ],
        "pt-BR": [
            "%d alias", "%d aliases", "%d commit", "%d commits", "%d err", "Aliases", "Backup",
            "Backups", "Branch", "Branches", "Commits", "Console", "Cookies", "DB/Cloud", "Daemon",
            "Diffs", "Downloads", "Editor", "Hooks", "Host", "Hosts:", "Hotfix", "Keybindings",
            "Layout", "Liquid", "Local", "Local:", "Macros", "Manual", "PRs", "Pipeline", "Plugins",
            "Proxy", "Snippet", "Snippets", "Terminal %d", "Terminal", "Terminal: %@", "Tokens",
            "Visual", "Zoom", "base %@", "base: %@", "manual", "ok",
        ],
        "tr": [
            "%d commit", "Agent", "DB/Cloud", "Daemon", "Hotfix", "Minimal", "PRs", "Panel",
            "Proxy", "SOCKS5 Proxy", "Terminal %d", "Terminal", "Terminal: %@",
        ],
    ]

    @Test("all 21 locales have exact nonempty key parity")
    func allLocalesHaveExactNonemptyKeyParity() throws {
        let resources = localizationResourcesURL()
        let english = try localizationStrings(locale: "en", resources: resources)
        let expectedKeys = Set(english.keys)
        let supportedCodes = Set(AppLocalizationResolver.supportedLanguages.map(\.rawValue))

        #expect(Self.localeCodes.count == 21)
        #expect(Set(Self.localeCodes).count == Self.localeCodes.count)
        #expect(Set(Self.localeCodes) == supportedCodes)
        #expect(expectedKeys.isEmpty == false)

        for locale in Self.localeCodes {
            let localized = try localizationStrings(locale: locale, resources: resources)
            let localizedKeys = Set(localized.keys)
            let duplicateKeys = try duplicateLocalizationKeys(locale: locale, resources: resources)
            let missing = expectedKeys.subtracting(localizedKeys).sorted()
            let orphaned = localizedKeys.subtracting(expectedKeys).sorted()
            let empty = localized.compactMap { key, value in
                value.isEmpty ? key : nil
            }.sorted()

            #expect(
                missing.isEmpty,
                Comment(rawValue: "\(locale) is missing keys: \(missing.prefix(20).joined(separator: ", "))")
            )
            #expect(
                orphaned.isEmpty,
                Comment(rawValue: "\(locale) has orphaned keys: \(orphaned.prefix(20).joined(separator: ", "))")
            )
            #expect(
                duplicateKeys.isEmpty,
                Comment(rawValue: "\(locale) has duplicate keys: \(duplicateKeys.prefix(20).joined(separator: ", "))")
            )
            #expect(
                empty.isEmpty,
                Comment(rawValue: "\(locale) has empty values: \(empty.prefix(20).joined(separator: ", "))")
            )
        }
    }

    @Test("all translations preserve format placeholders")
    func allTranslationsPreserveFormatPlaceholders() throws {
        let resources = localizationResourcesURL()
        let english = try localizationStrings(locale: "en", resources: resources)

        for locale in Self.localeCodes where locale != "en" {
            let localized = try localizationStrings(locale: locale, resources: resources)
            let mismatches = english.keys.compactMap { key -> String? in
                guard let value = localized[key] else { return nil }
                let expected = formatContract(in: english[key] ?? "")
                let actual = formatContract(in: value)
                return expected == actual ? nil : "\(key): \(expected) != \(actual)"
            }.sorted()

            #expect(
                mismatches.isEmpty,
                Comment(rawValue: "\(locale) changed format placeholders: \(mismatches.prefix(20).joined(separator: "; "))")
            )
        }
    }

    @Test("supported locales only retain explicitly reviewed technical English")
    func supportedLocalesDoNotFallBackToEnglishUICopy() throws {
        let resources = localizationResourcesURL()
        let english = try localizationStrings(locale: "en", resources: resources)

        for locale in Self.localeCodes where locale != "en" {
            let localized = try localizationStrings(locale: locale, resources: resources)
            let allowedValues = Self.intentionalNativeTechnicalValues[locale] ?? []
            let unexpected = english.keys.filter { key in
                guard localized[key] == english[key] else { return false }
                guard !Self.intentionalTechnicalCloneKeys.contains(key) else { return false }
                return !allowedValues.contains(english[key] ?? "")
            }.sorted()

            #expect(
                unexpected.isEmpty,
                Comment(
                    rawValue: "\(locale) has unreviewed English UI values: \(unexpected.joined(separator: ", "))"
                )
            )
        }
    }

    @Test("resolved Arabic UI direction is RTL")
    func resolvedArabicUIDirectionIsRTL() {
        let arabic = AppLocalizer(languagePreference: .arabic)
        let english = AppLocalizer(languagePreference: .english)
        let systemArabic = AppLocalizer(
            languagePreference: .system,
            resolver: AppLocalizationResolver(preferredLanguageIdentifiers: ["ar-HN"])
        )

        #expect(arabic.isRightToLeft)
        #expect(systemArabic.isRightToLeft)
        #expect(english.isRightToLeft == false)
    }

    private func localizationResourcesURL() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Localization", isDirectory: true)
    }

    private func localizationStrings(
        locale: String,
        resources: URL
    ) throws -> [String: String] {
        let url = resources
            .appendingPathComponent("\(locale).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        return try #require(propertyList as? [String: String])
    }

    private func duplicateLocalizationKeys(
        locale: String,
        resources: URL
    ) throws -> [String] {
        let url = resources
            .appendingPathComponent("\(locale).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        let source = try String(contentsOf: url, encoding: .utf8)
        let expression = try NSRegularExpression(
            pattern: #"(?m)^\"((?:\\.|[^\"\\])*)\"\s*="#
        )
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var counts: [String: Int] = [:]
        for match in expression.matches(in: source, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
            counts[String(source[keyRange]), default: 0] += 1
        }
        return counts.compactMap { key, count in count > 1 ? key : nil }.sorted()
    }

    private func formatContract(in value: String) -> [String] {
        let pattern = #"%(?:(\d+)\$)?([-+#0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|L|q|z|t|j)?(?:@|[diuoxXfFeEgGaAcCsSpn%]))"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        var nextPosition = 1
        var sawPositioned = false
        var sawUnpositioned = false
        var contract = expression.matches(in: value, range: range).compactMap { match -> String? in
            guard let bodyRange = Range(match.range(at: 2), in: value) else { return nil }
            let body = String(value[bodyRange])
            if body == "%" { return "literal:%%" }

            let position: Int
            if let range = Range(match.range(at: 1), in: value),
               let explicitPosition = Int(value[range]) {
                position = explicitPosition
                sawPositioned = true
            } else {
                position = nextPosition
                nextPosition += 1
                sawUnpositioned = true
            }
            return "\(position):%\(body)"
        }
        if sawPositioned && sawUnpositioned { contract.append("invalid:mixed-positioning") }
        return contract.sorted()
    }
}
