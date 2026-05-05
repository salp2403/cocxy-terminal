// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyShortcuts.swift - Shortcuts.app actions with local-only execution.

import AppKit
import Foundation

enum CocxyShortcutNetworkPolicy: String, Equatable, Sendable {
    case localOnly = "local-only"
}

struct CocxyShortcutDescriptor: Equatable, Sendable {
    let id: String
    let title: String
    let summary: String
    let systemImageName: String
    let networkPolicy: CocxyShortcutNetworkPolicy
    let requiresUserInitiation: Bool
    let privacySummary: String
}

enum CocxyShortcutsCatalog {
    static let descriptors: [CocxyShortcutDescriptor] = [
        CocxyShortcutDescriptor(
            id: "open-app",
            title: "Open Cocxy",
            summary: "Bring the local terminal window forward.",
            systemImageName: "terminal",
            networkPolicy: .localOnly,
            requiresUserInitiation: true,
            privacySummary: "Activates the local app only; no terminal content leaves the Mac."
        ),
        CocxyShortcutDescriptor(
            id: "run-command",
            title: "Run Command in Cocxy",
            summary: "Send text to the focused local terminal and optionally press Return.",
            systemImageName: "chevron.left.forwardslash.chevron.right",
            networkPolicy: .localOnly,
            requiresUserInitiation: true,
            privacySummary: "Writes only to the focused local terminal surface selected by the user."
        ),
        CocxyShortcutDescriptor(
            id: "open-notebook",
            title: "Open Cocxy Notebook",
            summary: "Open a local executable notebook panel in the current workspace.",
            systemImageName: "text.book.closed",
            networkPolicy: .localOnly,
            requiresUserInitiation: true,
            privacySummary: "Opens local UI state only; notebook execution remains user-triggered."
        ),
        CocxyShortcutDescriptor(
            id: "list-skills",
            title: "List Cocxy Skills",
            summary: "Return local built-in and user skill identifiers.",
            systemImageName: "list.bullet.rectangle",
            networkPolicy: .localOnly,
            requiresUserInitiation: true,
            privacySummary: "Reads local skill manifests only; nothing is uploaded or synced."
        ),
    ]

    static func descriptor(id: String) -> CocxyShortcutDescriptor? {
        descriptors.first { $0.id == id }
    }

    static func descriptors(localizer: AppLocalizer) -> [CocxyShortcutDescriptor] {
        descriptors.map { descriptor in
            descriptor.localized(using: localizer)
        }
    }
}

extension CocxyShortcutDescriptor {
    func localized(using localizer: AppLocalizer) -> CocxyShortcutDescriptor {
        CocxyShortcutDescriptor(
            id: id,
            title: localizer.string("shortcuts.\(id).title", fallback: title),
            summary: localizer.string("shortcuts.\(id).summary", fallback: summary),
            systemImageName: systemImageName,
            networkPolicy: networkPolicy,
            requiresUserInitiation: requiresUserInitiation,
            privacySummary: localizer.string(
                "shortcuts.\(id).privacy",
                fallback: privacySummary
            )
        )
    }
}

enum CocxyShortcutError: Error, LocalizedError {
    case appDelegateUnavailable
    case noActiveTerminal
    case noWindow

    var errorDescription: String? {
        localizedDescription(using: AppLocalizer(languagePreference: .system))
    }

    func localizedDescription(using localizer: AppLocalizer) -> String {
        switch self {
        case .appDelegateUnavailable:
            return localizer.string(
                "shortcuts.error.appDelegateUnavailable",
                fallback: "Cocxy is not ready yet."
            )
        case .noActiveTerminal:
            return localizer.string(
                "shortcuts.error.noActiveTerminal",
                fallback: "No active terminal surface is available."
            )
        case .noWindow:
            return localizer.string(
                "shortcuts.error.noWindow",
                fallback: "No Cocxy window is available."
            )
        }
    }
}

#if canImport(AppIntents)
import AppIntents

@available(macOS 14.0, *)
struct CocxyOpenAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Cocxy"
    static let description = IntentDescription("Bring the local Cocxy Terminal window forward.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            throw CocxyShortcutError.appDelegateUnavailable
        }
        appDelegate.activateForShortcut()
        return .result()
    }
}

@available(macOS 14.0, *)
struct CocxyRunCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Command in Cocxy"
    static let description = IntentDescription("Send text to the focused Cocxy terminal and optionally press Return.")
    static let openAppWhenRun = true

    @Parameter(title: "Command")
    var command: String

    @Parameter(title: "Press Return")
    var pressReturn: Bool

    init() {
        self.command = ""
        self.pressReturn = true
    }

    init(command: String, pressReturn: Bool = true) {
        self.command = command
        self.pressReturn = pressReturn
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            throw CocxyShortcutError.appDelegateUnavailable
        }
        guard appDelegate.sendTextToActiveTerminalForShortcut(command, pressReturn: pressReturn) else {
            throw CocxyShortcutError.noActiveTerminal
        }
        return .result()
    }
}

@available(macOS 14.0, *)
struct CocxyOpenNotebookIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Cocxy Notebook"
    static let description = IntentDescription("Open a local Cocxy notebook panel in the current workspace.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            throw CocxyShortcutError.appDelegateUnavailable
        }
        guard appDelegate.openNotebookPanelForShortcut() else {
            throw CocxyShortcutError.noWindow
        }
        return .result()
    }
}

@available(macOS 14.0, *)
struct CocxyListSkillsIntent: AppIntent {
    static let title: LocalizedStringResource = "List Cocxy Skills"
    static let description = IntentDescription("Return local Cocxy skill identifiers.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let skills = try SkillRegistry.localDefault().loadSkills()
        let output = skills.map(\.id).joined(separator: "\n")
        return .result(value: output)
    }
}

@available(macOS 14.0, *)
struct CocxyShortcutsProvider: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .navy

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CocxyOpenAppIntent(),
            phrases: ["Open \(.applicationName)", "Show \(.applicationName)"],
            shortTitle: "Open Cocxy",
            systemImageName: "terminal"
        )
        AppShortcut(
            intent: CocxyRunCommandIntent(),
            phrases: ["Run command in \(.applicationName)", "Send text to \(.applicationName)"],
            shortTitle: "Run Command",
            systemImageName: "chevron.left.forwardslash.chevron.right"
        )
        AppShortcut(
            intent: CocxyOpenNotebookIntent(),
            phrases: ["Open notebook in \(.applicationName)", "Show \(.applicationName) notebook"],
            shortTitle: "Open Notebook",
            systemImageName: "text.book.closed"
        )
        AppShortcut(
            intent: CocxyListSkillsIntent(),
            phrases: ["List \(.applicationName) skills", "Show \(.applicationName) skills"],
            shortTitle: "List Skills",
            systemImageName: "list.bullet.rectangle"
        )
    }
}
#endif
