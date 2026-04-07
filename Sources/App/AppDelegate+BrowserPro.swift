// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+BrowserPro.swift - Browser Pro service initialization.

import AppKit

// MARK: - Browser Pro Wiring

/// Extension that initializes and wires the Browser Pro subsystem:
/// profile management, history storage, and bookmark persistence.
///
/// Extracted from AppDelegate to isolate browser service setup
/// from app lifecycle management.
extension AppDelegate {

    /// Initializes Browser Pro services and injects them into the window controller.
    ///
    /// Creates the full dependency chain:
    /// 1. `JSONBrowserProfileStore` -- JSON-backed profile persistence.
    /// 2. `BrowserProfileManager` -- profile CRUD and active profile switching.
    /// 3. `SQLiteBrowserHistoryStore` -- SQLite FTS5 history with full-text search.
    /// 4. `JSONBrowserBookmarkStore` -- JSON-backed bookmark tree persistence.
    ///
    /// History store initialization can fail (e.g., disk full, permissions).
    /// The browser remains functional without history -- only search is degraded.
    ///
    /// Must be called AFTER `createMainWindow()` since it injects services
    /// into the window controller.
    func setupBrowserPro() {
        let profileStore = JSONBrowserProfileStore()
        let profileManager = BrowserProfileManager(store: profileStore)

        let historyPath = NSHomeDirectory() + "/.config/cocxy/browser/history.db"
        let historyStore: BrowserHistoryStoring?
        do {
            historyStore = try SQLiteBrowserHistoryStore(databasePath: historyPath)
        } catch {
            NSLog("[AppDelegate] Failed to initialize browser history store: %@",
                  String(describing: error))
            historyStore = nil
        }

        let bookmarkStore = JSONBrowserBookmarkStore()

        self.browserProfileManager = profileManager
        self.browserHistoryStore = historyStore
        self.browserBookmarkStore = bookmarkStore

        for controller in allWindowControllers {
            controller.browserProfileManager = profileManager
            controller.browserHistoryStore = historyStore
            controller.browserBookmarkStore = bookmarkStore
        }
    }
}
