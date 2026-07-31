// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowMenuValidationSwiftTestingTests.swift - Focus-aware menu validation coverage.

import AppKit
import Testing
@testable import CocxyTerminal

@Suite("Terminal scroll menu validation", .serialized)
@MainActor
struct MainWindowMenuValidationSwiftTestingTests {
    private let terminalScrollActions: [Selector] = [
        #selector(MainWindowController.scrollTerminalPageUpAction(_:)),
        #selector(MainWindowController.scrollTerminalPageDownAction(_:)),
        #selector(MainWindowController.scrollTerminalToTopAction(_:)),
        #selector(MainWindowController.scrollTerminalToBottomAction(_:)),
    ]

    @Test("all terminal scroll items are enabled for a focused terminal surface")
    func terminalScrollItemsAreEnabledForTerminalFocus() throws {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let window = try #require(controller.window)
        let contentView = try #require(window.contentView)
        let terminalView = CocxyCoreView()
        contentView.addSubview(terminalView)
        defer { controller.close() }

        #expect(window.makeFirstResponder(terminalView))
        for action in terminalScrollActions {
            #expect(controller.validateMenuItem(menuItem(action: action), keyWindow: window))
        }
    }

    @Test("all terminal scroll items are disabled for a focused text editor")
    func terminalScrollItemsAreDisabledForEditorFocus() throws {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let window = try #require(controller.window)
        let contentView = try #require(window.contentView)
        let editor = NSTextView()
        contentView.addSubview(editor)
        defer { controller.close() }

        #expect(window.makeFirstResponder(editor))
        for action in terminalScrollActions {
            #expect(!controller.validateMenuItem(menuItem(action: action), keyWindow: window))
        }

        let unrelatedItem = menuItem(action: #selector(MainWindowController.zoomInAction(_:)))
        #expect(controller.validateMenuItem(unrelatedItem, keyWindow: nil))
    }

    @Test("terminal scroll validation follows the key window")
    func terminalScrollValidationFollowsKeyWindow() throws {
        let receiver = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let receiverWindow = try #require(receiver.window)
        let receiverContent = try #require(receiverWindow.contentView)
        let receiverTerminal = CocxyCoreView()
        receiverContent.addSubview(receiverTerminal)

        let keyController = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let keyWindow = try #require(keyController.window)
        let keyContent = try #require(keyWindow.contentView)
        let keyEditor = NSTextView()
        keyContent.addSubview(keyEditor)
        defer {
            keyController.close()
            receiver.close()
        }

        #expect(receiverWindow.makeFirstResponder(receiverTerminal))
        #expect(keyWindow.makeFirstResponder(keyEditor))

        for action in terminalScrollActions {
            #expect(!receiver.validateMenuItem(menuItem(action: action), keyWindow: keyWindow))
        }
    }

    private func menuItem(action: Selector) -> NSMenuItem {
        NSMenuItem(title: "Test", action: action, keyEquivalent: "")
    }
}
