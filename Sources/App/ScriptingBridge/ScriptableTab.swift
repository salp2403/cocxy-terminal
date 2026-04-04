// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ScriptableTab.swift - AppleScript-visible tab object for Cocoa Scripting.

import AppKit

/// AppleScript-visible representation of a terminal tab.
///
/// Cocoa Scripting requires `NSObject` subclasses with `@objc` properties
/// for KVC (Key-Value Coding) access. This class bridges the domain `Tab`
/// model to the AppleScript world without modifying the model itself.
///
/// All property accessors use `MainActor.assumeIsolated` because Cocoa
/// Scripting always dispatches on the main thread, but the compiler cannot
/// verify this statically since the class cannot be marked `@MainActor`
/// (it must remain KVC-compatible for Cocoa Scripting).
///
/// This is a read-only facade for most properties. The `name` setter
/// delegates to `TabManager.renameTab` for rename support.
/// Other mutations are handled by command classes that call `TabManager`
/// and `MainWindowController` directly.
@objc(ScriptableTab)
final class ScriptableTab: NSObject, @unchecked Sendable {

    /// The domain tab ID.
    let tabID: TabID

    /// Reference to the tab manager for property lookups.
    private weak var tabManager: TabManager?

    init(tabID: TabID, tabManager: TabManager?) {
        self.tabID = tabID
        self.tabManager = tabManager
        super.init()
    }

    // MARK: - KVC Properties (match .sdef cocoa keys)

    /// Unique identifier string (KVC key: "uniqueID").
    @objc var uniqueID: String {
        tabID.rawValue.uuidString
    }

    /// Tab title (KVC key: "name").
    @objc var name: String {
        get {
            MainActor.assumeIsolated {
                tabManager?.tab(for: tabID)?.displayTitle ?? "Terminal"
            }
        }
        set {
            MainActor.assumeIsolated {
                tabManager?.renameTab(id: tabID, newTitle: newValue.isEmpty ? nil : newValue)
            }
        }
    }

    /// Working directory path (KVC key: "workingDirectory").
    @objc var workingDirectory: String {
        MainActor.assumeIsolated {
            tabManager?.tab(for: tabID)?.workingDirectory.path ?? "~"
        }
    }

    /// Agent state as string (KVC key: "agentState").
    @objc var agentState: String {
        MainActor.assumeIsolated {
            tabManager?.tab(for: tabID)?.agentState.rawValue ?? "idle"
        }
    }

    /// Whether this is the active tab (KVC key: "isActiveTab").
    @objc var isActiveTab: Bool {
        MainActor.assumeIsolated {
            tabManager?.activeTabID == tabID
        }
    }

    /// Foreground process name (KVC key: "processName").
    @objc var processName: String {
        MainActor.assumeIsolated {
            tabManager?.tab(for: tabID)?.processName ?? ""
        }
    }

    // MARK: - Object Specifier

    override var objectSpecifier: NSScriptObjectSpecifier? {
        let specifierBox = LockedBox<NSScriptObjectSpecifier?>(nil)
        MainActor.assumeIsolated {
            guard let tabManager = tabManager else { return }

            let appDescription = NSApplication.shared.classDescription
            guard let classDescription = appDescription as? NSScriptClassDescription else {
                return
            }

            let index = tabManager.tabs.firstIndex(where: { $0.id == tabID }) ?? 0
            specifierBox.withValue {
                $0 = NSIndexSpecifier(
                    containerClassDescription: classDescription,
                    containerSpecifier: nil,
                    key: "scriptableTabs",
                    index: index
                )
            }
        }
        return specifierBox.withValue { $0 }
    }

    // MARK: - Close Command

    @objc func handleCloseCommand(_ command: NSCloseCommand) {
        MainActor.assumeIsolated {
            tabManager?.removeTab(id: tabID)
        }
    }
}
