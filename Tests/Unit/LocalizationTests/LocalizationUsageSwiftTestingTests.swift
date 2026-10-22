// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LocalizationUsageSwiftTestingTests.swift - Source-to-resource localization coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Swift localization usage")
struct LocalizationUsageSwiftTestingTests {
    private static let requiredKeys: Set<String> = [
        "browser.route.local",
        "browser.route.local.accessibility",
        "browser.route.local.detail",
        "browser.route.notice.dismiss",
        "browser.route.notice.missingForward.detail",
        "browser.route.notice.missingForward.title",
        "browser.route.notice.navigationFailed.detail",
        "browser.route.notice.navigationFailed.title",
        "browser.route.notice.proxyConnecting.detail",
        "browser.route.notice.proxyConnecting.title",
        "browser.route.notice.proxyDegraded.detail",
        "browser.route.notice.proxyDegraded.title",
        "browser.route.notice.proxyFailed.detail",
        "browser.route.notice.proxyFailed.title",
        "browser.route.notice.retry",
        "browser.route.notice.switchLocal",
        "browser.route.remote",
        "browser.route.remote.accessibility",
        "github.pane.createPR.created",
        "github.pane.sourceControl.branchCreated",
        "github.pane.sourceControl.openRepository",
        "mobile.web.action.completed",
        "mobile.web.action.failed",
        "mobile.web.action.partial",
        "mobile.mirror.securitySSH",
        "mobile.mirror.status.activeSSH",
        "mobile.mirror.status.startingSSH",
        "mobile.mirror.transport.localDetail",
        "mobile.mirror.transport.sshDetail",
        "mobile.mirror.transport.sshLabel",
        "mobile.mirror.transport.sshOptional",
        "project.activation.verifiedSurfaceUnavailable",
        "projectHome.fanOut.error.baseChanged",
        "projectHome.fanOut.error.cancelled",
        "projectHome.fanOut.error.duplicateRun",
        "projectHome.fanOut.error.gitFailed",
        "projectHome.fanOut.error.gitUnavailable",
        "projectHome.fanOut.error.launchFailed",
        "projectHome.fanOut.error.launchRollbackIncomplete",
        "projectHome.fanOut.error.manifestUnavailable",
        "projectHome.fanOut.error.notRepository",
        "projectHome.fanOut.error.originDirty",
        "projectHome.fanOut.error.promotionUnavailable",
        "projectHome.fanOut.error.targetUnavailable",
        "projectHome.fanOut.error.uncommittedChanges",
        "projectHome.fanOut.error.unknown",
        "projectHome.fanOut.error.worktreeCollision",
        "projectHome.fanOut.error.worktreeMissing",
        "projectHome.fanOut.inferredPaths",
        "projectHome.fanOut.noInferredPaths",
        "projectHome.fanOut.promotionRefreshed",
        "taskRun.lifecycle.cancel.action",
        "taskRun.lifecycle.cancel.message",
        "taskRun.lifecycle.cancel.title",
        "taskRun.lifecycle.forget.action",
        "taskRun.lifecycle.forget.message",
        "taskRun.lifecycle.forget.title",
        "taskQueue.event.task-run-finished",
        "taskQueue.event.task-run-started",
    ]

    private static let catalogOnlyKeys: Set<String> = [
        "mobile.mirror.securitySSH",
        "mobile.mirror.status.activeSSH",
        "mobile.mirror.status.startingSSH",
        "mobile.mirror.transport.localDetail",
        "mobile.mirror.transport.sshDetail",
        "mobile.mirror.transport.sshLabel",
        "mobile.mirror.transport.sshOptional",
        "taskRun.lifecycle.cancel.action",
        "taskRun.lifecycle.cancel.message",
        "taskRun.lifecycle.cancel.title",
        "taskRun.lifecycle.forget.action",
        "taskRun.lifecycle.forget.message",
        "taskRun.lifecycle.forget.title",
    ]

    private static let fanOutErrorEnglishCopy: [String: String] = [
        "projectHome.fanOut.error.targetUnavailable": "The task target is no longer available. Reopen Project Home and try again.",
        "projectHome.fanOut.error.duplicateRun": "A task run with this identifier is already active: %@",
        "projectHome.fanOut.error.launchFailed": "The parallel task could not start. Verify the selected providers and worktree state, then try again.",
        "projectHome.fanOut.error.launchRollbackIncomplete": "The parallel task could not start, and %d cleanup operation(s) need attention.",
        "projectHome.fanOut.error.promotionUnavailable": "The promotion preview is no longer valid: %@",
        "projectHome.fanOut.error.cancelled": "The parallel task was cancelled.",
        "projectHome.fanOut.error.gitUnavailable": "Git is unavailable. Check your installation and PATH.",
        "projectHome.fanOut.error.notRepository": "The project is no longer a Git repository: %@",
        "projectHome.fanOut.error.worktreeCollision": "A unique worktree could not be created after %d attempts.",
        "projectHome.fanOut.error.gitFailed": "Git could not complete the operation (exit %d). Review the repository state and try again.",
        "projectHome.fanOut.error.worktreeMissing": "The worktree is no longer available: %@",
        "projectHome.fanOut.error.uncommittedChanges": "Commit or stash the changes in %@ before continuing.",
        "projectHome.fanOut.error.originDirty": "Commit or stash the changes in the project checkout before promotion: %@",
        "projectHome.fanOut.error.baseChanged": "The project branch changed after the parallel task started. Refresh or restart the task.",
        "projectHome.fanOut.error.manifestUnavailable": "The worktree registry could not be updated safely.",
        "projectHome.fanOut.error.unknown": "The parallel task could not be completed. Technical category: %@",
    ]

    private static let sshTransportEnglishCopy: [String: String] = [
        "mobile.mirror.status.startingSSH": "Opening secure SSH connection",
        "mobile.mirror.status.activeSSH": "Connected through SSH",
        "mobile.mirror.securitySSH": "One-use code · encrypted SSH · 90 seconds",
        "mobile.mirror.transport.sshLabel": "Secure SSH Connection",
    ]

    private static let taskRunLifecycleEnglishCopy: [String: String] = [
        "taskRun.lifecycle.cancel.title": "Cancel Parallel Task?",
        "taskRun.lifecycle.cancel.action": "Cancel Task",
        "taskRun.lifecycle.cancel.message": "Running agents will stop. Their worktrees and files will be kept.",
        "taskRun.lifecycle.forget.title": "Remove Task History?",
        "taskRun.lifecycle.forget.action": "Remove History",
        "taskRun.lifecycle.forget.message": "This removes the saved task record. Worktrees and files will be kept.",
    ]

    @Test("every Swift localization key exists in the English resource")
    func everySwiftLocalizationKeyExistsInEnglishResource() throws {
        let root = repositoryRoot()
        let scan = try SwiftLocalizationUsageScanner.scan(
            directory: root.appendingPathComponent("Sources", isDirectory: true),
            relativeTo: root
        )
        let expansion = expandedDynamicKeys(
            scan.dynamicUsages,
            registry: try dynamicKeyRegistry(root: root)
        )
        let unregistered = expansion.unregistered.map { usage in
            "\(usage.template) [\(usage.location.path):\(usage.location.line)]"
        }.joined(separator: "; ")
        let usedKeys = Set(scan.staticUsages.keys)
            .union(expansion.keys)
            .union(MobileMirrorWebLocalization.english.catalog.keys)
        let english = try localizationStrings(locale: "en", root: root)
        let missing = usedKeys.subtracting(english.keys).sorted()
        let requiredSwiftUsageKeys = Self.requiredKeys.subtracting(Self.catalogOnlyKeys)
        let uncoveredRequired = requiredSwiftUsageKeys.subtracting(usedKeys).sorted()

        #expect(
            expansion.unregistered.isEmpty,
            Comment(rawValue: "Dynamic localization usages need an explicit expansion: \(unregistered)")
        )
        #expect(
            uncoveredRequired.isEmpty,
            Comment(rawValue: "Required keys not discovered by the Swift scanner: \(uncoveredRequired.joined(separator: ", "))")
        )
        #expect(
            missing.isEmpty,
            Comment(rawValue: missingMessage(missing, scan: scan))
        )
    }

    @Test("task queue event expansion covers every plugin event")
    func taskQueueEventExpansionCoversEveryPluginEvent() throws {
        let root = repositoryRoot()
        let scan = try SwiftLocalizationUsageScanner.scan(
            directory: root.appendingPathComponent("Sources", isDirectory: true),
            relativeTo: root
        )
        let expected = Set(PluginEvent.allCases.map { "taskQueue.event.\($0.rawValue)" })
        let expansion = expandedDynamicKeys(
            scan.dynamicUsages,
            registry: try dynamicKeyRegistry(root: root)
        )
        let taskQueueEventUsages = scan.dynamicUsages.filter {
            $0.template.hasPrefix("taskQueue.event.")
        }
        let unsupportedDescription = expansion.unregistered.map { usage in
            "\(usage.template) [\(usage.location.path):\(usage.location.line)]"
        }.joined(separator: "; ")

        #expect(PluginEvent.allCases.count == 11)
        #expect(!taskQueueEventUsages.isEmpty)
        #expect(expected.isSubset(of: expansion.keys))
        #expect(
            expansion.unregistered.isEmpty,
            Comment(rawValue: "Dynamic localization usages need an explicit expansion: \(unsupportedDescription)")
        )
    }

    @Test("required coverage exists with nonempty values in all locales")
    func requiredCoverageExistsInAllLocales() throws {
        let root = repositoryRoot()

        #expect(AppLocalizationResolver.supportedLanguages.count == 21)
        for language in AppLocalizationResolver.supportedLanguages {
            let strings = try localizationStrings(locale: language.rawValue, root: root)
            let missing = Self.requiredKeys.subtracting(strings.keys).sorted()
            let empty = Self.requiredKeys.filter { strings[$0]?.isEmpty != false }.sorted()

            #expect(
                missing.isEmpty,
                Comment(rawValue: "\(language.rawValue) is missing required localization keys: \(missing.joined(separator: ", "))")
            )
            #expect(
                empty.isEmpty,
                Comment(rawValue: "\(language.rawValue) has empty required localizations: \(empty.joined(separator: ", "))")
            )
        }
    }

    @Test("fan-out error copy matches the safe public contract")
    func fanOutErrorCopyMatchesSafePublicContract() throws {
        let root = repositoryRoot()
        let english = try localizationStrings(locale: "en", root: root)

        for (key, expected) in Self.fanOutErrorEnglishCopy {
            let actual = try #require(english[key])
            #expect(
                actual == expected,
                Comment(rawValue: "Unexpected English fan-out error copy for \(key)")
            )
            #expect(!actual.localizedCaseInsensitiveContains("stderr"))
            #expect(!actual.localizedCaseInsensitiveContains("process output"))
        }
    }

    @Test("SSH transport variants match the public copy contract")
    func sshTransportVariantsMatchPublicCopyContract() throws {
        let root = repositoryRoot()
        let english = try localizationStrings(locale: "en", root: root)

        for (key, expected) in Self.sshTransportEnglishCopy {
            #expect(
                english[key] == expected,
                Comment(rawValue: "Unexpected English SSH transport copy for \(key)")
            )
        }
    }

    @Test("task run lifecycle copy matches the preservation contract")
    func taskRunLifecycleCopyMatchesPreservationContract() throws {
        let root = repositoryRoot()
        let english = try localizationStrings(locale: "en", root: root)

        for (key, expected) in Self.taskRunLifecycleEnglishCopy {
            #expect(
                english[key] == expected,
                Comment(rawValue: "Unexpected English task lifecycle copy for \(key)")
            )
        }
    }

    @Test("scanner resolves native variable and conditional localization calls")
    func scannerResolvesNativeVariableAndConditionalLocalizationCalls() {
        let source = #"""
        let payload: JSONValue = .string("payload.value")
        let fallback = json.string("payload.fallback", fallback: "none")
        // localizer.string("comment.key", fallback: "Comment")
        let timestamp = formatter.string(from: date)
        let variableKey = "variable.key"
        let conditionalKey = enabled ? "conditional.enabled" : "conditional.disabled"
        let title = localizer.string("real.key", fallback: "Real")
        let variable = localizer.string(variableKey, fallback: "Variable")
        let conditional = localizer.string(conditionalKey, fallback: "Conditional")
        let detail = localized("wrapped.key", fallback: "Wrapped")
        let error = formattedProjectString("formatted.key", fallback: "Formatted: %@", value)
        let foundation = NSLocalizedString("foundation.key", comment: "Foundation")
        let native = String(localized: enabled ? "native.enabled" : "native.disabled")
        let computed = localizer.string(computedKey, fallback: "Computed")
        let dynamic = localizer.string("dynamic.\(value)", fallback: "Dynamic")
        var computedKey: String {
            if enabled { return "computed.enabled" }
            return "computed.disabled"
        }
        """#
        let scan = SwiftLocalizationUsageScanner.scan(source: source, path: "Fixture.swift")

        #expect(Set(scan.staticUsages.keys) == [
            "conditional.disabled",
            "conditional.enabled",
            "computed.disabled",
            "computed.enabled",
            "formatted.key",
            "foundation.key",
            "native.disabled",
            "native.enabled",
            "real.key",
            "variable.key",
            "wrapped.key",
        ])
        #expect(Set(scan.dynamicUsages.map(\.template)) == [#"dynamic.\(value)"#])
    }

    @Test("unregistered dynamic templates fail expansion")
    func unregisteredDynamicTemplatesFailExpansion() {
        let scan = SwiftLocalizationUsageScanner.scan(
            source: #"localizer.string("fixture.\(value)", fallback: "Fixture")"#,
            path: "Fixture.swift"
        )

        let expansion = expandedDynamicKeys(scan.dynamicUsages, registry: [:])

        #expect(expansion.keys.isEmpty)
        #expect(expansion.unregistered.map(\.template) == [#"fixture.\(value)"#])
    }

    @Test("revocation placeholders preserve capability and plugin roles")
    func revocationPlaceholdersPreserveSemanticRoles() throws {
        let root = repositoryRoot()
        let capability = "filesystem-write"
        let plugin = "plugin.example"
        let korean = try #require(localizationStrings(locale: "ko", root: root)["sandboxInspector.status.revoked"])
        let traditionalChinese = try #require(localizationStrings(locale: "zh-TW", root: root)["sandboxInspector.status.revoked"])

        #expect(String(format: korean, capability, plugin) == "plugin.example에서 filesystem-write 권한을 철회했습니다.")
        #expect(String(format: traditionalChinese, capability, plugin) == "已撤銷 plugin.example 的「filesystem-write」權限。")
    }

    @Test("localized vault labels use one term per locale")
    func localizedVaultLabelsUseOneTermPerLocale() throws {
        let root = repositoryRoot()
        for language in AppLocalizationResolver.supportedLanguages where language != .english {
            let strings = try localizationStrings(locale: language.rawValue, root: root)
            let accessibility = try #require(strings["vault.sidebar.accessibility"])

            #expect(
                !accessibility.localizedCaseInsensitiveContains("Vault"),
                Comment(rawValue: "\(language.rawValue) mixes its localized Vault title with the English term")
            )
        }
    }

    private struct DynamicExpansion {
        let keys: Set<String>
        let unregistered: [SwiftLocalizationUsageScanner.DynamicUsage]
    }

    private func expandedDynamicKeys(
        _ usages: [SwiftLocalizationUsageScanner.DynamicUsage],
        registry: [String: Set<String>]
    ) -> DynamicExpansion {
        var keys: Set<String> = []
        var unregistered: [SwiftLocalizationUsageScanner.DynamicUsage] = []
        for usage in usages {
            guard let expansion = registry[usage.template] else {
                unregistered.append(usage)
                continue
            }
            keys.formUnion(expansion)
        }
        return DynamicExpansion(keys: keys, unregistered: unregistered)
    }

    private func dynamicKeyRegistry(root: URL) throws -> [String: Set<String>] {
        let plugins = try BundledPluginCatalog(
            pluginsDirectory: root.appendingPathComponent("Resources/Plugins", isDirectory: true)
        ).loadManifests()
        let helperIDs = DBCloudHelperCatalog.descriptors(from: plugins).map(\.id)
        let skillIDs = try SkillRegistry(directories: [SkillDirectory(
            url: root.appendingPathComponent("Resources/Skills", isDirectory: true),
            source: .builtIn
        )]).loadSkills().map(\.id)
        let templates = try ProjectTemplateRegistry(directories: [ProjectTemplateDirectory(
            url: root.appendingPathComponent("Resources/Templates", isDirectory: true),
            source: .builtIn
        )]).loadTemplates()
        let templateIDs = templates.map(\.id)
        let pluginIDs = plugins.map(\.id)
        let shortcutIDs = CocxyShortcutsCatalog.descriptors.map(\.id)
        let worktreeTemplateIDs = WorktreeTemplate.builtIns.map(\.id)
        let remoteSubPanelIDs = RemoteConnectionViewModel.SubPanel.allCases.map(\.rawValue)
        let lspSuggestionIDs = LSPLanguageRegistry.defaults.servers
            .filter { $0.installSuggestion.command == nil }
            .map(\.languageID)
        let englishKeys = Set(try localizationStrings(locale: "en", root: root).keys)
        let commandNameKeys = englishKeys.filter {
            $0.hasPrefix("command.") && $0.hasSuffix(".name")
        }
        let commandDescriptionKeys = englishKeys.filter {
            $0.hasPrefix("command.") && $0.contains(".description")
        }

        return [
            #"agent.panel.skill.builtIn.\(skill.id).name"#: family(skillIDs, prefix: "agent.panel.skill.builtIn.", suffix: ".name"),
            #"agent.panel.skill.builtIn.\(skill.id).summary"#: family(skillIDs, prefix: "agent.panel.skill.builtIn.", suffix: ".summary"),
            #"dbCloud.helper.\(descriptor.id).description"#: family(helperIDs, prefix: "dbCloud.helper.", suffix: ".description"),
            #"dbCloud.status.postgres.\(keySuffix)"#: family(["finished", "failed"], prefix: "dbCloud.status.postgres."),
            #"dbCloud.status.s3.\(keySuffix)"#: family(["finished", "failed"], prefix: "dbCloud.status.s3."),
            #"dbCloud.status.sqlite.\(keySuffix)"#: family(["finished", "failed"], prefix: "dbCloud.status.sqlite."),
            #"keybindings.action.\(id).name"#: family(KeybindingActionCatalog.all.map(\.id), prefix: "keybindings.action.", suffix: ".name"),
            #"keybindings.action.\(id).summary"#: family(KeybindingActionCatalog.all.map(\.id), prefix: "keybindings.action.", suffix: ".summary"),
            #"keybindings.category.\(id)"#: family(KeybindingCategory.allCases.map(\.rawValue), prefix: "keybindings.category."),
            #"command.category.\(rawValue.lowercased())"#: family(CommandCategory.allCases.map { $0.rawValue.lowercased() }, prefix: "command.category."),
            #"command.\(id).description"#: commandDescriptionKeys,
            #"command.\(id).name"#: commandNameKeys,
            #"plugins.builtin.\(plugin.id).description"#: family(pluginIDs, prefix: "plugins.builtin.", suffix: ".description"),
            #"plugins.builtin.\(plugin.id).name"#: family(pluginIDs, prefix: "plugins.builtin.", suffix: ".name"),
            #"preferences.appearance.sidebarDensity.\(rawValue)"#: family(AuroraSidebarDisplayMode.allCases.map(\.rawValue), prefix: "preferences.appearance.sidebarDensity."),
            #"preferences.appearance.sidebarRowDetail.\(rawValue)"#: family(AuroraSidebarPrimaryInfo.allCases.map(\.rawValue), prefix: "preferences.appearance.sidebarRowDetail."),
            #"preferences.lsp.install.\(server.languageID)"#: family(lspSuggestionIDs, prefix: "preferences.lsp.install."),
            #"preferences.section.\(rawValue)"#: family(PreferencesSection.allCases.map(\.rawValue), prefix: "preferences.section."),
            #"preferences.updates.channel.\(channel.rawValue)"#: family(ChannelKind.allCases.map(\.rawValue), prefix: "preferences.updates.channel."),
            #"remoteWorkspace.subPanel.\(rawValue)"#: family(remoteSubPanelIDs, prefix: "remoteWorkspace.subPanel."),
            #"remoteWorkspace.subPanel.\(rawValue).detail"#: family(remoteSubPanelIDs, prefix: "remoteWorkspace.subPanel.", suffix: ".detail"),
            #"sandboxInspector.capability.\(capability.rawValue)"#: family(PluginCapability.allCases.map(\.rawValue), prefix: "sandboxInspector.capability."),
            #"shortcuts.\(id).privacy"#: family(shortcutIDs, prefix: "shortcuts.", suffix: ".privacy"),
            #"shortcuts.\(id).summary"#: family(shortcutIDs, prefix: "shortcuts.", suffix: ".summary"),
            #"shortcuts.\(id).title"#: family(shortcutIDs, prefix: "shortcuts.", suffix: ".title"),
            #"taskQueue.event.\(event.rawValue)"#: family(PluginEvent.allCases.map(\.rawValue), prefix: "taskQueue.event."),
            #"taskQueue.status.\(rawValue)"#: family(["scheduled", "queued", "running", "retrying", "succeeded", "failed", "cancelled"], prefix: "taskQueue.status."),
            #"taskQueue.status.\(status.rawValue)"#: family(["scheduled", "queued", "running", "retrying", "succeeded", "failed", "cancelled"], prefix: "taskQueue.status."),
            #"taskRun.status.\(rawValue)"#: family(["launching", "running", "promoting", "completed", "failed", "cancelled"], prefix: "taskRun.status."),
            #"agentDashboard.state.\(dashboardValue)"#: family(AgentDashboardState.allCases.map(\.rawValue), prefix: "agentDashboard.state."),
            #"markdown.search.matches.\(matchSegment).\(fileSegment)"#: family(["one.oneFile", "one.manyFiles", "many.oneFile", "many.manyFiles"], prefix: "markdown.search.matches."),
            #"templates.builtIn.\(template.id).name"#: family(templateIDs, prefix: "templates.builtIn.", suffix: ".name"),
            #"templates.builtIn.\(template.id).summary"#: family(templateIDs, prefix: "templates.builtIn.", suffix: ".summary"),
            #"templates.builtIn.\(template.id).variable.\(variable.name).prompt"#: Set(templates.flatMap { template in
                template.variables.map { "templates.builtIn.\(template.id).variable.\($0.name).prompt" }
            }),
            #"worktree.template.\(id).description"#: family(worktreeTemplateIDs, prefix: "worktree.template.", suffix: ".description"),
            #"worktree.template.\(id).name"#: family(worktreeTemplateIDs, prefix: "worktree.template.", suffix: ".name"),
        ]
    }

    private func family(
        _ values: [String],
        prefix: String,
        suffix: String = ""
    ) -> Set<String> {
        Set(values.map { prefix + $0 + suffix })
    }

    private func missingMessage(
        _ missing: [String],
        scan: SwiftLocalizationUsageScanner.Result
    ) -> String {
        let details = missing.prefix(30).map { key in
            let locations = scan.staticUsages[key, default: []]
                .prefix(3)
                .map { "\($0.path):\($0.line)" }
                .joined(separator: ", ")
            return locations.isEmpty ? key : "\(key) [\(locations)]"
        }
        return "Swift localization keys missing from English: \(details.joined(separator: "; "))"
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private func localizationStrings(locale: String, root: URL) throws -> [String: String] {
        let url = root
            .appendingPathComponent("Resources/Localization/\(locale).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        return try #require(propertyList as? [String: String])
    }
}
