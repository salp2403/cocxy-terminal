// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandPaletteRowView.swift - Individual row in the command palette results.

import SwiftUI

// MARK: - Command Palette Row View

/// A single row in the command palette result list.
///
/// Displays the action name (with matched characters highlighted),
/// a short description, the category badge, and the keyboard shortcut
/// if one exists.
///
/// ## Layout
///
/// ```
/// +--------------------------------------------------+
/// | [Category]  Action Name          Shortcut         |
/// |             Short description                     |
/// +--------------------------------------------------+
/// ```
///
/// - SeeAlso: `CommandPaletteView` (parent container)
/// - SeeAlso: `CommandAction` (data model)
struct CommandPaletteRowView: View {

    /// The action to display.
    let action: CommandAction

    /// Whether this row is currently selected (highlighted).
    let isSelected: Bool

    /// The current search query, used to highlight matching characters.
    let query: String

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            categoryBadge
            actionDetails
            Spacer()
            shortcutLabel
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            isSelected
                ? Color(nsColor: CocxyColors.surface0)
                : Color.clear
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: CocxyColors.blue))
                    .frame(width: 4)
                    .padding(.vertical, 4)
            }
        }
        .cornerRadius(6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(action.name), \(action.category.rawValue)")
        .accessibilityValue(action.shortcut ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Category Badge

    private var categoryBadge: some View {
        Text(action.category.rawValue)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(Color(nsColor: CocxyColors.text))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(nsColor: CocxyColors.surface1))
            .cornerRadius(3)
    }

    // MARK: - Action Details

    private var actionDetails: some View {
        VStack(alignment: .leading, spacing: 1) {
            highlightedName(name: action.name, query: query)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            if !action.description.isEmpty {
                Text(action.description)
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Query Highlight

    /// Builds a `Text` with matching characters highlighted in accent blue.
    ///
    /// For each character in the query (case-insensitive), finds its next
    /// occurrence in the name and highlights it. Non-matching characters
    /// use the primary foreground color.
    ///
    /// - Parameters:
    ///   - name: The action name to display.
    ///   - query: The current search query.
    /// - Returns: A styled `Text` with highlighted matches.
    private func highlightedName(name: String, query: String) -> Text {
        guard !query.isEmpty else {
            return Text(name).foregroundColor(.primary)
        }

        let matchedIndices = findMatchedIndices(in: name, query: query)
        let nameCharacters = Array(name)
        let accentColor = Color(nsColor: CocxyColors.blue)

        var result = Text("")
        for (index, character) in nameCharacters.enumerated() {
            let segment = Text(String(character))
            if matchedIndices.contains(index) {
                result = result + segment.foregroundColor(accentColor)
            } else {
                result = result + segment.foregroundColor(.primary)
            }
        }
        return result
    }

    /// Finds the indices in `name` that match the characters of `query`
    /// in order (case-insensitive fuzzy matching).
    ///
    /// - Parameters:
    ///   - name: The string to search within.
    ///   - query: The query characters to match.
    /// - Returns: A set of character indices in `name` that match.
    private func findMatchedIndices(in name: String, query: String) -> Set<Int> {
        var matched = Set<Int>()
        let lowercasedName = Array(name.lowercased())
        let lowercasedQuery = Array(query.lowercased())

        var nameIndex = 0
        var queryIndex = 0

        while nameIndex < lowercasedName.count, queryIndex < lowercasedQuery.count {
            if lowercasedName[nameIndex] == lowercasedQuery[queryIndex] {
                matched.insert(nameIndex)
                queryIndex += 1
            }
            nameIndex += 1
        }

        return matched
    }

    // MARK: - Shortcut Label

    private var shortcutLabel: some View {
        Group {
            if let shortcut = action.shortcut {
                Text(shortcut)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }
        }
    }
}
