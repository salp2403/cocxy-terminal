// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// KeybindingShortcutTests.swift - Parsing, canonicalization and pretty printing tests.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("KeybindingShortcut parsing")
struct KeybindingShortcutParsingTests {

    @Test func parsesSingleLetterWithCommand() {
        let shortcut = KeybindingShortcut.parse("cmd+t")
        #expect(shortcut != nil)
        #expect(shortcut?.requiresCommand == true)
        #expect(shortcut?.requiresShift == false)
        #expect(shortcut?.requiresControl == false)
        #expect(shortcut?.requiresOption == false)
        #expect(shortcut?.baseKey == "t")
    }

    @Test func parsesMultipleModifiers() {
        let shortcut = KeybindingShortcut.parse("cmd+shift+alt+ctrl+f12")
        #expect(shortcut != nil)
        #expect(shortcut?.requiresCommand == true)
        #expect(shortcut?.requiresShift == true)
        #expect(shortcut?.requiresOption == true)
        #expect(shortcut?.requiresControl == true)
        #expect(shortcut?.baseKey == "f12")
    }

    @Test func parsesAliasesCaseInsensitive() {
        let control = KeybindingShortcut.parse("Control+Option+D")
        #expect(control?.requiresControl == true)
        #expect(control?.requiresOption == true)
        #expect(control?.baseKey == "d")

        let meta = KeybindingShortcut.parse("META+r")
        #expect(meta?.requiresCommand == true)
        #expect(meta?.baseKey == "r")
    }

    @Test func rejectsEmptyInput() {
        #expect(KeybindingShortcut.parse("") == nil)
        #expect(KeybindingShortcut.parse("   ") == nil)
    }

    @Test func rejectsOnlyModifiers() {
        #expect(KeybindingShortcut.parse("cmd") == nil)
        #expect(KeybindingShortcut.parse("cmd+shift") == nil)
    }

    @Test func rejectsTwoBaseKeys() {
        let invalid = KeybindingShortcut.parse("cmd+t+u")
        #expect(invalid == nil)
    }

    @Test func rejectsDanglingPlus() {
        #expect(KeybindingShortcut.parse("cmd+") == nil)
        #expect(KeybindingShortcut.parse("+t") == nil)
    }
}

@Suite("KeybindingShortcut canonical round-trip")
struct KeybindingShortcutCanonicalTests {

    @Test func canonicalOrdersModifiersDeterministically() {
        let a = KeybindingShortcut.parse("shift+cmd+alt+ctrl+k")!
        let b = KeybindingShortcut.parse("cmd+ctrl+alt+shift+k")!
        #expect(a.canonical == b.canonical)
        #expect(a.canonical == "cmd+ctrl+alt+shift+k")
    }

    @Test func canonicalRoundTripsPunctuation() {
        let cases = ["cmd+shift+[", "cmd+shift+]", "cmd+,", "cmd+grave"]
        for raw in cases {
            let parsed = KeybindingShortcut.parse(raw)
            #expect(parsed != nil, "Expected \(raw) to parse")
            #expect(parsed?.canonical == raw, "\(raw) should round-trip")
        }
    }

    @Test func canonicalNormalizesAliasesToCmdCtrlAlt() {
        let parsed = KeybindingShortcut.parse("Option+Command+Control+f")
        #expect(parsed?.canonical == "cmd+ctrl+alt+f")
    }
}

@Suite("KeybindingShortcut pretty label")
struct KeybindingShortcutPrettyTests {

    @Test func prettyLabelUsesMacOSGlyphs() {
        let shortcut = KeybindingShortcut(
            requiresCommand: true,
            requiresShift: true,
            baseKey: "d"
        )
        #expect(shortcut.prettyLabel == "\u{21E7}\u{2318}D")
    }

    @Test func prettyLabelFullStackOrder() {
        let shortcut = KeybindingShortcut(
            requiresCommand: true,
            requiresControl: true,
            requiresOption: true,
            requiresShift: true,
            baseKey: "k"
        )
        #expect(shortcut.prettyLabel == "\u{2303}\u{2325}\u{21E7}\u{2318}K")
    }

    @Test func prettyLabelRendersArrowGlyphs() {
        let left = KeybindingShortcut(requiresCommand: true, requiresOption: true, baseKey: "left")
        #expect(left.prettyLabel == "\u{2325}\u{2318}\u{2190}")

        let down = KeybindingShortcut(requiresCommand: true, requiresOption: true, baseKey: "down")
        #expect(down.prettyLabel == "\u{2325}\u{2318}\u{2193}")
    }

    @Test func prettyLabelNamedKeys() {
        let tab = KeybindingShortcut(requiresCommand: true, baseKey: "tab")
        #expect(tab.prettyLabel == "\u{2318}Tab")

        let escape = KeybindingShortcut(requiresCommand: true, baseKey: "escape")
        #expect(escape.prettyLabel == "\u{2318}Esc")

        let f5 = KeybindingShortcut(baseKey: "f5")
        #expect(f5.prettyLabel == "F5")
    }
}

@Suite("KeybindingActionCatalog integrity")
struct KeybindingActionCatalogTests {

    @Test func catalogIsNonEmpty() {
        #expect(KeybindingActionCatalog.all.count >= 30)
    }

    @Test func actionIdsAreUnique() {
        let ids = KeybindingActionCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func allDefaultsParseBackToThemselves() {
        for action in KeybindingActionCatalog.all {
            let canonical = action.defaultShortcut.canonical
            let reparsed = KeybindingShortcut.parse(canonical)
            #expect(reparsed != nil, "Default for \(action.id) should parse")
            #expect(reparsed?.canonical == canonical, "\(action.id) must round-trip (\(canonical))")
        }
    }

    @Test func groupedContainsEveryAction() {
        let total = KeybindingActionCatalog.grouped.reduce(0) { $0 + $1.actions.count }
        #expect(total == KeybindingActionCatalog.all.count)
    }

    @Test func legacyMappingTargetsExistingIds() {
        let catalogIds = Set(KeybindingActionCatalog.all.map(\.id))
        for actionId in KeybindingActionCatalog.legacyFieldMapping.values {
            #expect(catalogIds.contains(actionId), "Legacy mapping -> \(actionId) is not in catalog")
        }
    }
}
