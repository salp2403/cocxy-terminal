// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+BrowserImport.swift - Native browser import sheet wiring.

import AppKit
import SwiftUI

extension MainWindowController {
    @objc func showBrowserImportAction(_ sender: Any?) {
        showBrowserImportWizard(profileID: browserProfileManager?.activeProfileID)
    }

    @MainActor
    func showBrowserImportWizard(profileID: UUID? = nil) {
        guard let window else { return }
        if let existing = browserImportSheetWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        if browserProfileManager == nil,
           let delegate = NSApp.delegate as? AppDelegate {
            delegate.setupBrowserPro()
        }
        guard let profileManager = browserProfileManager else {
            presentBrowserImportUnavailableAlert()
            return
        }

        let localizer = appLocalizer()
        let bookmarkRootTitleFormat = localizer.string(
            BrowserImportBookmarkRootLocalization.key,
            fallback: BrowserImportBookmarkRootLocalization.fallback
        )
        let service = BrowserImportService(
            historyStore: browserHistoryStore,
            bookmarkStore: browserBookmarkStore,
            cookieStore: BrowserWebKitCookieImportStore(),
            auditLogger: FileBrowserImportAuditLogger(),
            bookmarkRootTitleFormat: bookmarkRootTitleFormat,
            bookmarkRootTitleAliases: BrowserImportBookmarkRootLocalization.formats(
                current: bookmarkRootTitleFormat
            )
        )
        let viewModel = BrowserImportViewModel(
            destinationProfiles: profileManager.profiles,
            initialDestinationProfileID: profileID ?? profileManager.activeProfileID,
            historyDestinationAvailable: browserHistoryStore != nil,
            cookieDestinationAvailable: true,
            bookmarkDestinationAvailable: browserBookmarkStore != nil,
            service: service,
            destinationProfileProvider: { [weak profileManager] in
                profileManager?.profiles ?? []
            },
            destinationProfileManager: profileManager
        )
        viewModel.onImportCompleted = { [weak self] result in
            self?.refreshBrowserImportConsumers(after: result)
        }

        let sheetReference = WeakReference<NSWindow>(nil)
        let closeSheet = { [weak self, weak window, weak viewModel] in
            viewModel?.cancelPendingWork()
            guard let sheet = sheetReference.value else { return }
            if sheet.sheetParent != nil {
                window?.endSheet(sheet)
            } else {
                sheet.orderOut(nil)
            }
            if self?.browserImportSheetWindow === sheet {
                self?.browserImportSheetWindow = nil
            }
        }
        let content = BrowserImportWizardView(
            viewModel: viewModel,
            localizer: localizer,
            onCancel: closeSheet,
            onDone: closeSheet
        )
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: content))
        sheetReference.value = sheet
        sheet.title = BrowserImportWizardView.localizedTitle(using: localizer)
        sheet.styleMask = [.titled]
        sheet.isReleasedWhenClosed = false
        sheet.contentMinSize = NSSize(width: 700, height: 570)
        sheet.contentMaxSize = NSSize(width: 700, height: 570)
        browserImportSheetWindow = sheet
        window.beginSheet(sheet)
    }

    @MainActor
    private func refreshBrowserImportConsumers(after result: BrowserImportResult) {
        if result.importedHistoryCount > 0, isBrowserHistoryVisible {
            showBrowserHistory()
        }
        if result.importedBookmarkCount > 0, isBrowserBookmarksVisible {
            showBrowserBookmarks()
        }
    }

    @MainActor
    private func presentBrowserImportUnavailableAlert() {
        let localizer = appLocalizer()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizer.string(
            "browser.import.error.unavailable.title",
            fallback: "Browser Import Unavailable"
        )
        alert.informativeText = localizer.string(
            "browser.import.error.unavailable.detail",
            fallback: "Cocxy could not initialize local browser profile storage."
        )
        alert.addButton(withTitle: localizer.string("common.ok", fallback: "OK"))
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
