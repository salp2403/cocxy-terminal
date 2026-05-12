// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+ThemeBrowser.swift - Floating searchable theme picker.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ThemeBrowserWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

extension MainWindowController {
    @objc func showThemeBrowserAction(_ sender: Any?) {
        showThemeBrowser()
    }

    func showThemeBrowser() {
        if let controller = themeBrowserWindowController {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }

        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let engine = appDelegate.themeEngine else {
            NSSound.beep()
            return
        }

        let viewModel = ThemeBrowserViewModel(
            themeEngine: engine,
            importer: ThemeImporter(),
            applyTheme: { [weak appDelegate] themeName in
                appDelegate?.switchTheme(to: themeName)
            }
        )

        var closeFromView: (() -> Void)?
        let rootView = ThemePickerView(
            viewModel: viewModel,
            onImportRequested: { [weak self, weak viewModel] in
                self?.presentThemeImportPanel(viewModel: viewModel)
            },
            onClose: {
                closeFromView?()
            }
        )
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Themes"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 500)
        window.center()

        var didClose = false
        let cleanup: () -> Void = { [weak self, weak viewModel] in
            guard !didClose else { return }
            didClose = true
            viewModel?.restorePreviewIfNeeded()
            self?.themeBrowserWindowController = nil
            self?.themeBrowserWindowDelegate = nil
        }
        closeFromView = { [weak window] in
            cleanup()
            window?.close()
        }

        let controller = NSWindowController(window: window)
        let delegate = ThemeBrowserWindowDelegate(onClose: cleanup)
        window.delegate = delegate
        themeBrowserWindowDelegate = delegate
        themeBrowserWindowController = controller

        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func presentThemeImportPanel(viewModel: ThemeBrowserViewModel?) {
        guard let viewModel else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Theme"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text, .data]

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            try viewModel.importTheme(from: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
