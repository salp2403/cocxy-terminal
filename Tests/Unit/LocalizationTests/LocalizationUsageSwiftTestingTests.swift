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
        let dynamicKeys = expandedDynamicKeys(scan.dynamicUsages)
        let usedKeys = Set(scan.staticUsages.keys)
            .union(dynamicKeys)
            .union(MobileMirrorWebLocalization.english.catalog.keys)
        let english = try localizationStrings(locale: "en", root: root)
        let missing = usedKeys.subtracting(english.keys).sorted()
        let requiredSwiftUsageKeys = Self.requiredKeys.subtracting(Self.catalogOnlyKeys)
        let uncoveredRequired = requiredSwiftUsageKeys.subtracting(usedKeys).sorted()

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
        let expanded = expandedDynamicKeys(scan.dynamicUsages)
        let unsupported = scan.dynamicUsages.filter {
            $0.template != #"taskQueue.event.\(event.rawValue)"#
        }
        let unsupportedDescription = unsupported.map { usage in
            "\(usage.template) [\(usage.location.path):\(usage.location.line)]"
        }.joined(separator: "; ")

        #expect(PluginEvent.allCases.count == 11)
        #expect(expected.isSubset(of: expanded))
        #expect(
            unsupported.isEmpty,
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

    @Test("scanner ignores non-localization string calls and comments")
    func scannerIgnoresNonLocalizationStringCallsAndComments() {
        let source = #"""
        let payload: JSONValue = .string("payload.value")
        let fallback = json.string("payload.fallback", fallback: "none")
        // localizer.string("comment.key", fallback: "Comment")
        let timestamp = formatter.string(from: date)
        let title = localizer.string("real.key", fallback: "Real")
        let detail = localized("wrapped.key", fallback: "Wrapped")
        """#
        let scan = SwiftLocalizationUsageScanner.scan(source: source, path: "Fixture.swift")

        #expect(Set(scan.staticUsages.keys) == ["real.key", "wrapped.key"])
        #expect(scan.dynamicUsages.isEmpty)
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

    private func expandedDynamicKeys(
        _ usages: [SwiftLocalizationUsageScanner.DynamicUsage]
    ) -> Set<String> {
        var keys: Set<String> = []
        for usage in usages where usage.template == #"taskQueue.event.\(event.rawValue)"# {
            keys.formUnion(PluginEvent.allCases.map { "taskQueue.event.\($0.rawValue)" })
        }
        return keys
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

private enum SwiftLocalizationUsageScanner {
    struct Location: Hashable {
        let path: String
        let line: Int
    }

    struct DynamicUsage: Hashable {
        let template: String
        let location: Location
    }

    struct Result {
        var staticUsages: [String: [Location]] = [:]
        var dynamicUsages: [DynamicUsage] = []

        mutating func merge(_ other: Result) {
            for (key, locations) in other.staticUsages {
                staticUsages[key, default: []].append(contentsOf: locations)
            }
            dynamicUsages.append(contentsOf: other.dynamicUsages)
        }
    }

    private enum TokenKind: Equatable {
        case identifier(String)
        case stringLiteral(String)
        case symbol(Character)
    }

    private struct Token: Equatable {
        let kind: TokenKind
        let line: Int
    }

    static func scan(directory: URL, relativeTo root: URL) throws -> Result {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return Result() }

        var result = Result()
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            result.merge(scan(source: source, path: relativePath(for: fileURL, from: root)))
        }
        return result
    }

    static func scan(source: String, path: String) -> Result {
        let tokens = tokenize(source)
        let appLocalizerExtension = tokens.indices.contains { index in
            guard case .identifier("extension") = tokens[index].kind,
                  index + 1 < tokens.count,
                  case .identifier("AppLocalizer") = tokens[index + 1].kind else {
                return false
            }
            return true
        }
        var result = Result()

        for index in tokens.indices {
            guard case .identifier(let function) = tokens[index].kind,
                  ["localized", "localizedString", "string"].contains(function),
                  index + 2 < tokens.count,
                  tokens[index + 1].kind == .symbol("("),
                  case .stringLiteral(let key) = tokens[index + 2].kind,
                  callHasFallbackLabel(tokens, openingAt: index + 1) else {
                continue
            }
            if function == "string",
               !isLocalizationStringCall(tokens, functionAt: index, appLocalizerExtension: appLocalizerExtension) {
                continue
            }

            let location = Location(path: path, line: tokens[index].line)
            if key.contains(#"\("#) {
                result.dynamicUsages.append(DynamicUsage(template: key, location: location))
            } else if key.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil {
                result.staticUsages[key, default: []].append(location)
            }
        }
        return result
    }

    private static func isLocalizationStringCall(
        _ tokens: [Token],
        functionAt index: Int,
        appLocalizerExtension: Bool
    ) -> Bool {
        guard index > 0, tokens[index - 1].kind == .symbol(".") else {
            return appLocalizerExtension
        }
        let lowerBound = max(0, index - 16)
        return tokens[lowerBound..<index].contains { token in
            guard case .identifier(let identifier) = token.kind else { return false }
            return identifier.localizedCaseInsensitiveContains("localizer")
        }
    }

    private static func callHasFallbackLabel(_ tokens: [Token], openingAt opening: Int) -> Bool {
        var depth = 0
        var index = opening
        while index < tokens.count {
            switch tokens[index].kind {
            case .symbol("("):
                depth += 1
            case .symbol(")"):
                depth -= 1
                if depth == 0 { return false }
            case .identifier("fallback") where depth == 1:
                if index + 1 < tokens.count, tokens[index + 1].kind == .symbol(":") {
                    return true
                }
            default:
                break
            }
            index += 1
        }
        return false
    }

    private static func tokenize(_ source: String) -> [Token] {
        var tokens: [Token] = []
        var index = source.startIndex
        var line = 1
        var blockCommentDepth = 0

        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index)
            let nextCharacter = next < source.endIndex ? source[next] : nil

            if blockCommentDepth > 0 {
                if character == "/", nextCharacter == "*" {
                    blockCommentDepth += 1
                    index = source.index(after: next)
                } else if character == "*", nextCharacter == "/" {
                    blockCommentDepth -= 1
                    index = source.index(after: next)
                } else {
                    if character == "\n" { line += 1 }
                    index = next
                }
                continue
            }
            if character == "/", nextCharacter == "/" {
                while index < source.endIndex, source[index] != "\n" {
                    index = source.index(after: index)
                }
                continue
            }
            if character == "/", nextCharacter == "*" {
                blockCommentDepth = 1
                index = source.index(after: next)
                continue
            }
            if character == "\n" {
                line += 1
                index = next
                continue
            }
            if character.isWhitespace {
                index = next
                continue
            }
            if character == "\"" {
                let tokenLine = line
                var value = ""
                index = next
                var escaped = false
                while index < source.endIndex {
                    let current = source[index]
                    if current == "\n" { line += 1 }
                    if escaped {
                        value.append("\\")
                        value.append(current)
                        escaped = false
                    } else if current == "\\" {
                        escaped = true
                    } else if current == "\"" {
                        index = source.index(after: index)
                        break
                    } else {
                        value.append(current)
                    }
                    index = source.index(after: index)
                }
                tokens.append(Token(kind: .stringLiteral(value), line: tokenLine))
                continue
            }
            if isIdentifierStart(character) {
                let start = index
                index = next
                while index < source.endIndex, isIdentifierContinuation(source[index]) {
                    index = source.index(after: index)
                }
                tokens.append(Token(kind: .identifier(String(source[start..<index])), line: line))
                continue
            }

            tokens.append(Token(kind: .symbol(character), line: line))
            index = next
        }
        return tokens
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private static func isIdentifierContinuation(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }

    private static func relativePath(for fileURL: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return filePath }
        return String(filePath.dropFirst(rootPath.count + 1))
    }
}
