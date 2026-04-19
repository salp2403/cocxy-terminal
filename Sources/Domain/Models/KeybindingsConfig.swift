// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// KeybindingsConfig.swift - TOML [keybindings] section model.

import Foundation

// MARK: - Keybindings Config

/// `[keybindings]` section of the configuration.
///
/// Represented as a set of typed fields for the eight legacy settings that
/// existed before the keybindings editor, plus an arbitrary `customOverrides`
/// dictionary for any action in `KeybindingActionCatalog` that does not have
/// a dedicated field.
///
/// ## Backward compatibility
///
/// Callers that read `keybindings.newTab`, `keybindings.closeTab`, etc.
/// continue to work unchanged. New callers should prefer
/// `shortcutString(for:)` which understands both the legacy typed fields
/// and the generic `customOverrides` dictionary.
///
/// ## TOML shape
///
/// Legacy kebab-case keys (`new-tab`, `split-horizontal`, ...) and the new
/// dotted catalog ids (`"tab.new"`, `"split.horizontal"`, ...) are both
/// accepted on parse. On write, the serializer emits the legacy kebab-case
/// fields for the eight well-known actions and quoted dotted ids for any
/// other customized action.
struct KeybindingsConfig: Codable, Sendable, Equatable {
    let newTab: String
    let closeTab: String
    let nextTab: String
    let prevTab: String
    let splitVertical: String
    let splitHorizontal: String
    let gotoAttention: String
    let toggleQuickTerminal: String

    /// Additional action-id -> canonical shortcut string entries that do not
    /// correspond to one of the typed legacy fields above.
    ///
    /// Keys are the catalog ids from `KeybindingActionCatalog` (for example
    /// `"split.close"`). Values are canonical shortcut strings
    /// (`"cmd+shift+w"`). Entries matching the catalog default should not be
    /// stored here — the writer normalizes by dropping no-op overrides.
    let customOverrides: [String: String]

    init(
        newTab: String,
        closeTab: String,
        nextTab: String,
        prevTab: String,
        splitVertical: String,
        splitHorizontal: String,
        gotoAttention: String,
        toggleQuickTerminal: String,
        customOverrides: [String: String] = [:]
    ) {
        self.newTab = newTab
        self.closeTab = closeTab
        self.nextTab = nextTab
        self.prevTab = prevTab
        self.splitVertical = splitVertical
        self.splitHorizontal = splitHorizontal
        self.gotoAttention = gotoAttention
        self.toggleQuickTerminal = toggleQuickTerminal
        self.customOverrides = customOverrides
    }

    // MARK: - Codable

    /// Custom decoder that treats `customOverrides` as optional and falls
    /// back to an empty map when the payload omits it. This keeps legacy
    /// `CocxyConfig` JSON snapshots — persisted before the editable
    /// keybindings feature existed — decoding cleanly instead of throwing
    /// `.keyNotFound`. The eight typed fields remain required because
    /// every released config has always carried them.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.newTab = try container.decode(String.self, forKey: .newTab)
        self.closeTab = try container.decode(String.self, forKey: .closeTab)
        self.nextTab = try container.decode(String.self, forKey: .nextTab)
        self.prevTab = try container.decode(String.self, forKey: .prevTab)
        self.splitVertical = try container.decode(String.self, forKey: .splitVertical)
        self.splitHorizontal = try container.decode(String.self, forKey: .splitHorizontal)
        self.gotoAttention = try container.decode(String.self, forKey: .gotoAttention)
        self.toggleQuickTerminal = try container.decode(String.self, forKey: .toggleQuickTerminal)
        self.customOverrides = try container.decodeIfPresent(
            [String: String].self,
            forKey: .customOverrides
        ) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case newTab
        case closeTab
        case nextTab
        case prevTab
        case splitVertical
        case splitHorizontal
        case gotoAttention
        case toggleQuickTerminal
        case customOverrides
    }

    static var defaults: KeybindingsConfig {
        KeybindingsConfig(
            newTab: "cmd+t",
            closeTab: "cmd+w",
            nextTab: "cmd+shift+]",
            prevTab: "cmd+shift+[",
            splitVertical: "cmd+shift+d",
            splitHorizontal: "cmd+d",
            gotoAttention: "cmd+shift+u",
            toggleQuickTerminal: "cmd+grave"
        )
    }

    // MARK: - Catalog Resolution

    /// Returns the resolved shortcut string for a catalog action id.
    ///
    /// Resolution order:
    /// 1. Value stored in a legacy typed field (for the eight well-known ids).
    /// 2. Value in `customOverrides` for this id.
    /// 3. The catalog default — so the editor always has a value to display.
    func shortcutString(for actionId: String) -> String {
        if let legacyValue = legacyValue(forActionId: actionId) {
            return legacyValue
        }
        if let customValue = customOverrides[actionId] {
            return customValue
        }
        if let entry = KeybindingAction.catalogEntry(for: actionId) {
            return entry.defaultShortcut.canonical
        }
        return ""
    }

    /// Whether the user has explicitly customized this action.
    ///
    /// Returns `true` when the resolved shortcut differs from the catalog
    /// default. Used by the editor to surface a "Reset" affordance and by
    /// the writer to avoid persisting no-op overrides.
    func isCustomized(_ actionId: String) -> Bool {
        guard let entry = KeybindingAction.catalogEntry(for: actionId) else {
            return false
        }
        let resolved = shortcutString(for: actionId)
        return resolved != entry.defaultShortcut.canonical
    }

    /// Reads the legacy typed field that corresponds to this action id, if any.
    private func legacyValue(forActionId actionId: String) -> String? {
        switch actionId {
        case KeybindingActionCatalog.tabNew.id: return newTab
        case KeybindingActionCatalog.tabClose.id: return closeTab
        case KeybindingActionCatalog.tabNext.id: return nextTab
        case KeybindingActionCatalog.tabPrevious.id: return prevTab
        case KeybindingActionCatalog.splitVertical.id: return splitVertical
        case KeybindingActionCatalog.splitHorizontal.id: return splitHorizontal
        case KeybindingActionCatalog.remoteGoToAttention.id: return gotoAttention
        case KeybindingActionCatalog.windowQuickTerminal.id: return toggleQuickTerminal
        default: return nil
        }
    }

    // MARK: - TOML Serialization

    /// Generates the `[keybindings]` TOML section text.
    ///
    /// Emits the eight legacy kebab-case fields unconditionally (preserving
    /// forward compatibility for tools that parsed the old format), and then
    /// appends quoted dotted-id lines for every non-default custom override.
    func tomlSection() -> String {
        var lines: [String] = ["[keybindings]"]

        lines.append("new-tab = \"\(newTab)\"")
        lines.append("close-tab = \"\(closeTab)\"")
        lines.append("next-tab = \"\(nextTab)\"")
        lines.append("prev-tab = \"\(prevTab)\"")
        lines.append("split-vertical = \"\(splitVertical)\"")
        lines.append("split-horizontal = \"\(splitHorizontal)\"")
        lines.append("goto-attention = \"\(gotoAttention)\"")
        lines.append("toggle-quick-terminal = \"\(toggleQuickTerminal)\"")

        if !customOverrides.isEmpty {
            let sorted = customOverrides.keys.sorted()
            for id in sorted {
                guard let value = customOverrides[id] else { continue }
                lines.append("\"\(id)\" = \"\(value)\"")
            }
        }

        return lines.joined(separator: "\n")
    }
}
