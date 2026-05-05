// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyTouchBarController.swift - Local Touch Bar actions for the main window.

import AppKit

@MainActor
final class CocxyTouchBarController: NSObject, NSTouchBarDelegate {
    static let customizationIdentifier = NSTouchBar.CustomizationIdentifier("dev.cocxy.terminal.touchbar")

    static let newTabIdentifier = NSTouchBarItem.Identifier("dev.cocxy.terminal.touchbar.new-tab")
    static let commandPaletteIdentifier = NSTouchBarItem.Identifier("dev.cocxy.terminal.touchbar.command-palette")
    static let agentPanelIdentifier = NSTouchBarItem.Identifier("dev.cocxy.terminal.touchbar.agent-panel")
    static let searchIdentifier = NSTouchBarItem.Identifier("dev.cocxy.terminal.touchbar.search")

    static let defaultItemIdentifiers: [NSTouchBarItem.Identifier] = [
        newTabIdentifier,
        commandPaletteIdentifier,
        agentPanelIdentifier,
        searchIdentifier
    ]

    struct Labels {
        let newTab: String
        let commandPalette: String
        let agentPanel: String
        let search: String

        static let defaults = Labels(
            newTab: "New Tab",
            commandPalette: "Command Palette",
            agentPanel: "Agent Mode",
            search: "Find..."
        )
    }

    private struct ItemDescriptor {
        let title: String
        let symbolName: String
        let action: () -> Void
    }

    private let itemsByIdentifier: [NSTouchBarItem.Identifier: ItemDescriptor]

    init(
        labels: Labels = .defaults,
        newTab: @escaping () -> Void,
        commandPalette: @escaping () -> Void,
        agentPanel: @escaping () -> Void,
        search: @escaping () -> Void
    ) {
        self.itemsByIdentifier = [
            Self.newTabIdentifier: ItemDescriptor(
                title: labels.newTab,
                symbolName: "plus",
                action: newTab
            ),
            Self.commandPaletteIdentifier: ItemDescriptor(
                title: labels.commandPalette,
                symbolName: "command",
                action: commandPalette
            ),
            Self.agentPanelIdentifier: ItemDescriptor(
                title: labels.agentPanel,
                symbolName: "sparkles",
                action: agentPanel
            ),
            Self.searchIdentifier: ItemDescriptor(
                title: labels.search,
                symbolName: "magnifyingglass",
                action: search
            )
        ]
        super.init()
    }

    func makeTouchBar() -> NSTouchBar {
        let touchBar = NSTouchBar()
        touchBar.customizationIdentifier = Self.customizationIdentifier
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = Self.defaultItemIdentifiers
        touchBar.customizationAllowedItemIdentifiers = Self.defaultItemIdentifiers
        return touchBar
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        guard let descriptor = itemsByIdentifier[identifier] else { return nil }

        let item = NSCustomTouchBarItem(identifier: identifier)
        item.customizationLabel = descriptor.title

        let button = NSButton(
            image: Self.image(named: descriptor.symbolName, fallbackTitle: descriptor.title),
            target: self,
            action: #selector(runAction(_:))
        )
        button.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
        button.toolTip = descriptor.title
        button.bezelStyle = .texturedRounded
        item.view = button

        return item
    }

    @objc private func runAction(_ sender: NSButton) {
        guard let rawIdentifier = sender.identifier?.rawValue else { return }
        let identifier = NSTouchBarItem.Identifier(rawIdentifier)
        itemsByIdentifier[identifier]?.action()
    }

    private static func image(named symbolName: String, fallbackTitle: String) -> NSImage {
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: fallbackTitle) {
            return image
        }
        return NSImage(size: NSSize(width: 18, height: 18))
    }
}
