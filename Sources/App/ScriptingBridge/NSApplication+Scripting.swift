// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NSApplication+Scripting.swift - Exposes tabs to Cocoa Scripting.

import AppKit

/// Extends NSApplication to provide the `scriptableTabs` element
/// required by the .sdef vocabulary.
///
/// Cocoa Scripting accesses elements via KVC. The .sdef declares
/// `<element type="tab"><cocoa key="scriptableTabs"/></element>`
/// on the application class, so NSApplication must respond to
/// `scriptableTabs` with an array of ScriptableTab objects.
///
/// Uses `MainActor.assumeIsolated` because Cocoa Scripting always
/// dispatches KVC lookups on the main thread.
extension NSApplication {

    /// Returns all tabs as scriptable objects for AppleScript access.
    ///
    /// KVC key: `scriptableTabs` (matches .sdef element declaration).
    @objc var scriptableTabs: [ScriptableTab] {
        var tabs: [ScriptableTab] = []
        MainActor.assumeIsolated {
            guard let appDelegate = delegate as? AppDelegate else {
                return
            }

            tabs = appDelegate.allWindowControllers.flatMap { controller in
                controller.tabManager.tabs.map { tab in
                    ScriptableTab(tabID: tab.id, tabManager: controller.tabManager)
                }
            }
        }
        return tabs
    }
}
