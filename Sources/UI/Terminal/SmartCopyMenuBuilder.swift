// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SmartCopyMenuBuilder.swift - Engine-backed terminal context menu.

import AppKit

@MainActor
enum SmartCopyMenuBuilder {
    static func buildMenu(
        detectedContent: TerminalDetectedContent?,
        copyText: String,
        lineText: String,
        clipboardService: ClipboardServiceProtocol,
        paste: (() -> Void)? = nil,
        activate: ((TerminalDetectedContent) -> Bool)? = nil,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) -> NSMenu {
        let menu = NSMenu()

        if let detectedContent {
            menu.addItem(menuItem(
                for: detectedContent,
                clipboard: clipboardService,
                activate: activate,
                localizer: localizer
            ))
            menu.addItem(.separator())
        }

        let copyItem = NSMenuItem(
            title: localizer.string("common.copy", fallback: "Copy"),
            action: nil,
            keyEquivalent: "c"
        )
        copyItem.keyEquivalentModifierMask = [.command]
        copyItem.isEnabled = copyText.isEmpty == false
        retainAction(on: copyItem) {
            clipboardService.write(copyText)
        }
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(
            title: localizer.string("common.paste", fallback: "Paste"),
            action: nil,
            keyEquivalent: "v"
        )
        pasteItem.keyEquivalentModifierMask = [.command]
        pasteItem.isEnabled = paste != nil
        if let paste {
            retainAction(on: pasteItem, handler: paste)
        }
        menu.addItem(pasteItem)
        menu.addItem(.separator())

        let copyLineItem = NSMenuItem(
            title: localizer.string("terminal.smartCopy.copyLine", fallback: "Copy Line"),
            action: nil,
            keyEquivalent: ""
        )
        let normalizedLine = lineText.trimmingCharacters(in: .newlines)
        copyLineItem.isEnabled = normalizedLine.isEmpty == false
        retainAction(on: copyLineItem) {
            clipboardService.write(normalizedLine)
        }
        menu.addItem(copyLineItem)
        return menu
    }

    static func localizedActionTitle(
        for kind: TerminalDetectedContentKind,
        using localizer: AppLocalizer
    ) -> String {
        switch kind {
        case .hyperlink:
            return localizer.string("terminal.smartCopy.openLink", fallback: "Open Link")
        case .url:
            return localizer.string("terminal.smartCopy.openURL", fallback: "Open URL")
        case .filePath:
            return localizer.string("terminal.smartCopy.openPath", fallback: "Open Path")
        case .ipAddress:
            return localizer.string("terminal.smartCopy.copyIPAddress", fallback: "Copy IP Address")
        case .gitHash:
            return localizer.string("terminal.smartCopy.copyGitHash", fallback: "Copy Git Hash")
        case .email:
            return localizer.string("terminal.smartCopy.copyEmail", fallback: "Copy Email")
        }
    }

    static func localizedDetectedTitle(
        actionTitle: String,
        value: String,
        using localizer: AppLocalizer
    ) -> String {
        String(
            format: localizer.string("terminal.smartCopy.detectedTitle", fallback: "%@: %@"),
            actionTitle,
            value
        )
    }

    private static func menuItem(
        for content: TerminalDetectedContent,
        clipboard: ClipboardServiceProtocol,
        activate: ((TerminalDetectedContent) -> Bool)?,
        localizer: AppLocalizer
    ) -> NSMenuItem {
        let actionTitle = localizedActionTitle(for: content.kind, using: localizer)
        let displayValue = content.text.count > 40
            ? String(content.text.prefix(37)) + "..."
            : content.text
        let item = NSMenuItem(
            title: localizedDetectedTitle(
                actionTitle: actionTitle,
                value: displayValue,
                using: localizer
            ),
            action: nil,
            keyEquivalent: ""
        )
        item.image = NSImage(
            systemSymbolName: symbolName(for: content.kind),
            accessibilityDescription: actionTitle
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))

        switch content.kind {
        case .ipAddress, .gitHash, .email:
            retainAction(on: item) {
                clipboard.write(content.target)
            }
        case .hyperlink, .url, .filePath:
            item.isEnabled = activate != nil
            if let activate {
                retainAction(on: item) {
                    _ = activate(content)
                }
            }
        }
        return item
    }

    private static func symbolName(for kind: TerminalDetectedContentKind) -> String {
        switch kind {
        case .hyperlink, .url: return "link"
        case .filePath: return "doc"
        case .ipAddress: return "network"
        case .gitHash: return "number"
        case .email: return "envelope"
        }
    }

    private static func retainAction(on item: NSMenuItem, handler: @escaping () -> Void) {
        let action = SmartCopyAction(handler: handler)
        item.target = action
        item.action = #selector(SmartCopyAction.execute)
        item.representedObject = action
    }
}

@MainActor
final class SmartCopyAction: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func execute() {
        handler()
    }
}
