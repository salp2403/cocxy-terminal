// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserDevToolsView.swift - In-app browser developer tools panel.

import SwiftUI

// MARK: - DevTools Tab Selection

/// The active tab within the DevTools panel.
enum DevToolsTab: String, CaseIterable, Identifiable {
    case console = "Console"
    case network = "Network"
    case dom = "DOM"

    var id: String { rawValue }

    /// SF Symbol for each tab.
    var symbolName: String {
        switch self {
        case .console: return "terminal"
        case .network: return "network"
        case .dom:     return "chevron.left.forwardslash.chevron.right"
        }
    }
}

// MARK: - DOM Node

/// A simplified DOM node for the tree inspector.
///
/// Contains the tag name, element ID, CSS classes, and a list of
/// child nodes for recursive tree rendering.
struct DOMNode: Identifiable {

    /// Unique identifier for SwiftUI list identity.
    let id: UUID = UUID()

    /// HTML tag name (e.g., "div", "span", "body").
    let tag: String

    /// The element's `id` attribute, if present.
    let elementID: String?

    /// CSS class names on the element.
    let classes: [String]

    /// Direct child nodes.
    let children: [DOMNode]

    /// A compact display label combining tag, id, and classes.
    var displayLabel: String {
        var label = "<\(tag)"
        if let elementID, !elementID.isEmpty {
            label += " id=\"\(elementID)\""
        }
        if !classes.isEmpty {
            label += " class=\"\(classes.joined(separator: " "))\""
        }
        label += ">"
        return label
    }
}

// MARK: - Browser DevTools View

/// Developer tools panel for the in-app browser with Console, Network, and DOM tabs.
///
/// ## Layout
///
/// ```
/// +---------------------------------------------+
/// | [Console] [Network] [DOM]              [x]  |
/// +---------------------------------------------+
/// | (Tab-specific content fills remaining space) |
/// +---------------------------------------------+
/// ```
///
/// ## Console Tab
///
/// Displays captured `console.log/warn/error/info` output from the page.
/// Entries are color-coded by level and can be filtered by text or level.
///
/// ## Network Tab
///
/// Shows resource requests captured via the Performance API. Each row
/// displays the method, URL, duration, and transfer size.
///
/// ## DOM Tab
///
/// Renders a basic tree of DOM elements with tag names, IDs, and classes.
/// Nodes are expandable to explore the document structure.
///
/// - SeeAlso: ``BrowserConsoleCapture`` for console message capture.
/// - SeeAlso: ``BrowserNetworkMonitor`` for network request capture.
struct BrowserDevToolsView: View {

    /// Console entries to display.
    let consoleEntries: [ConsoleEntry]

    /// Network entries to display.
    @ObservedObject var networkMonitor: BrowserNetworkMonitor

    /// DOM tree root nodes.
    let domNodes: [DOMNode]

    /// Called to clear console entries.
    let onClearConsole: () -> Void

    /// Called to clear network entries.
    let onClearNetwork: () -> Void

    /// Called to refresh the DOM tree snapshot.
    let onRefreshDOM: () -> Void

    /// Called when the user taps the close button.
    let onDismiss: () -> Void

    /// The currently selected tab.
    @State private var selectedTab: DevToolsTab = .console

    /// Text filter for console entries.
    @State private var consoleFilterText: String = ""

    /// Level filter for console entries. Nil shows all levels.
    @State private var consoleLevelFilter: ConsoleEntry.Level? = nil

    /// Text filter for network entries.
    @State private var networkFilterText: String = ""

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            tabContent
        }
        .background(
            ZStack {
                Color(nsColor: CocxyColors.mantle)
                VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Browser DevTools")
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 0) {
            ForEach(DevToolsTab.allCases) { tab in
                devToolsTabButton(tab)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .accessibilityLabel("Close DevTools")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func devToolsTabButton(_ tab: DevToolsTab) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 4) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 10))
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
            }
            .foregroundColor(
                selectedTab == tab
                    ? Color(nsColor: CocxyColors.text)
                    : Color(nsColor: CocxyColors.overlay1)
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(selectedTab == tab
                          ? Color(nsColor: CocxyColors.surface0)
                          : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab.rawValue) tab")
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }

    // MARK: - Tab Content Router

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .console:
            consoleTabView
        case .network:
            networkTabView
        case .dom:
            domTabView
        }
    }

    // MARK: - Console Tab

    private var consoleTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            consoleFilterBar
            Divider()

            if filteredConsoleEntries.isEmpty {
                devToolsEmptyState(
                    symbol: "terminal",
                    title: "No console output",
                    detail: "Console messages from the page will appear here."
                )
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredConsoleEntries) { entry in
                            consoleEntryRow(entry)
                            Divider()
                                .padding(.leading, 8)
                        }
                    }
                }
            }
        }
    }

    private var consoleFilterBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))

                TextField("Filter...", text: $consoleFilterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: CocxyColors.surface0))
            )

            consoleLevelPicker

            Spacer()

            Button("Clear", action: onClearConsole)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                .buttonStyle(.plain)
                .accessibilityLabel("Clear console")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var consoleLevelPicker: some View {
        HStack(spacing: 2) {
            consoleLevelChip(label: "All", level: nil)
            consoleLevelChip(label: "Err", level: .error)
            consoleLevelChip(label: "Warn", level: .warn)
            consoleLevelChip(label: "Info", level: .info)
        }
    }

    private func consoleLevelChip(label: String, level: ConsoleEntry.Level?) -> some View {
        Button(action: { consoleLevelFilter = level }) {
            Text(label)
                .font(.system(size: 9, weight: consoleLevelFilter == level ? .semibold : .regular))
                .foregroundColor(
                    consoleLevelFilter == level
                        ? Color(nsColor: CocxyColors.crust)
                        : Color(nsColor: CocxyColors.overlay1)
                )
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(consoleLevelFilter == level
                              ? colorForConsoleLevel(level)
                              : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) filter")
    }

    private func consoleEntryRow(_ entry: ConsoleEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(levelBadge(entry.level))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(colorForConsoleLevel(entry.level))
                .frame(width: 32, alignment: .center)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.text))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.level.rawValue): \(entry.message)")
    }

    private var filteredConsoleEntries: [ConsoleEntry] {
        var filtered = consoleEntries

        if let levelFilter = consoleLevelFilter {
            filtered = filtered.filter { $0.level == levelFilter }
        }

        if !consoleFilterText.isEmpty {
            let lowered = consoleFilterText.lowercased()
            filtered = filtered.filter { $0.message.lowercased().contains(lowered) }
        }

        return filtered
    }

    // MARK: - Network Tab

    private var networkTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            networkFilterBar
            Divider()
            networkColumnHeader

            if filteredNetworkEntries.isEmpty {
                devToolsEmptyState(
                    symbol: "network",
                    title: "No network requests",
                    detail: "Resource requests from the page will appear here."
                )
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredNetworkEntries) { entry in
                            networkEntryRow(entry)
                            Divider()
                                .padding(.leading, 8)
                        }
                    }
                }
            }
        }
    }

    private var networkFilterBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))

                TextField("Filter URLs...", text: $networkFilterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: CocxyColors.surface0))
            )

            Spacer()

            Text("\(networkMonitor.entries.count) requests")
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))

            Button("Clear", action: onClearNetwork)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                .buttonStyle(.plain)
                .accessibilityLabel("Clear network log")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var networkColumnHeader: some View {
        HStack(spacing: 0) {
            Text("Method")
                .frame(width: 44, alignment: .leading)
            Text("URL")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Time")
                .frame(width: 54, alignment: .trailing)
            Text("Size")
                .frame(width: 54, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .foregroundColor(Color(nsColor: CocxyColors.overlay0))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: CocxyColors.crust))
    }

    private func networkEntryRow(_ entry: NetworkEntry) -> some View {
        HStack(spacing: 0) {
            Text(entry.method)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(colorForNetworkMethod(entry.method))
                .frame(width: 44, alignment: .leading)

            Text(truncatedURL(entry.url))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.text))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(formattedDuration(entry.duration))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(colorForDuration(entry.duration))
                .frame(width: 54, alignment: .trailing)

            Text(formattedSize(entry.transferSize))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                .frame(width: 54, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.method) \(entry.url), \(formattedDuration(entry.duration))")
    }

    private var filteredNetworkEntries: [NetworkEntry] {
        guard !networkFilterText.isEmpty else { return networkMonitor.entries }
        let lowered = networkFilterText.lowercased()
        return networkMonitor.entries.filter { $0.url.lowercased().contains(lowered) }
    }

    // MARK: - DOM Tab

    private var domTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            domToolbar
            Divider()

            if domNodes.isEmpty {
                devToolsEmptyState(
                    symbol: "chevron.left.forwardslash.chevron.right",
                    title: "No DOM data",
                    detail: "Tap Refresh to capture the current page structure."
                )
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(domNodes) { node in
                            DOMNodeRow(node: node, depth: 0)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var domToolbar: some View {
        HStack {
            Spacer()

            Button(action: onRefreshDOM) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                    Text("Refresh")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh DOM tree")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Shared Empty State

    private func devToolsEmptyState(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Formatting Helpers

    private func levelBadge(_ level: ConsoleEntry.Level) -> String {
        switch level {
        case .log:   return "LOG"
        case .warn:  return "WRN"
        case .error: return "ERR"
        case .info:  return "INF"
        }
    }

    private func colorForConsoleLevel(_ level: ConsoleEntry.Level?) -> Color {
        switch level {
        case .log, .none: return Color(nsColor: CocxyColors.text)
        case .warn:       return Color(nsColor: CocxyColors.yellow)
        case .error:      return Color(nsColor: CocxyColors.red)
        case .info:       return Color(nsColor: CocxyColors.blue)
        }
    }

    private func colorForNetworkMethod(_ method: String) -> Color {
        switch method {
        case "XHR":  return Color(nsColor: CocxyColors.mauve)
        default:     return Color(nsColor: CocxyColors.blue)
        }
    }

    private func colorForDuration(_ milliseconds: Double) -> Color {
        if milliseconds < 100 {
            return Color(nsColor: CocxyColors.green)
        } else if milliseconds < 500 {
            return Color(nsColor: CocxyColors.yellow)
        } else {
            return Color(nsColor: CocxyColors.red)
        }
    }

    private func formattedDuration(_ milliseconds: Double) -> String {
        if milliseconds < 1000 {
            return String(format: "%.0fms", milliseconds)
        } else {
            return String(format: "%.1fs", milliseconds / 1000)
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        if bytes == 0 {
            return "--"
        } else if bytes < 1024 {
            return "\(bytes)B"
        } else if bytes < 1_048_576 {
            return String(format: "%.1fKB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1fMB", Double(bytes) / 1_048_576)
        }
    }

    private func truncatedURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        return url.path.isEmpty ? urlString : url.path
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

// MARK: - DOM Node Row

/// A single row in the DOM tree inspector, with recursive children.
///
/// Uses a disclosure group to allow expanding/collapsing child nodes.
/// Leaf nodes (no children) are shown as simple text rows.
struct DOMNodeRow: View {

    /// The node to display.
    let node: DOMNode

    /// The indentation depth (0 = root level).
    let depth: Int

    /// Whether this node's children are expanded.
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if !node.children.isEmpty {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                        .frame(width: 12)
                        .onTapGesture { isExpanded.toggle() }
                } else {
                    Spacer()
                        .frame(width: 12)
                }

                Text(tagPortion(node.tag))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(nsColor: CocxyColors.red))

                if let elementID = node.elementID, !elementID.isEmpty {
                    Text("#\(elementID)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(nsColor: CocxyColors.mauve))
                }

                if !node.classes.isEmpty {
                    Text(".\(node.classes.joined(separator: "."))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(nsColor: CocxyColors.blue))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 16 + 8)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture {
                if !node.children.isEmpty {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                ForEach(node.children) { child in
                    DOMNodeRow(node: child, depth: depth + 1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("DOM element: \(node.tag)")
    }

    /// Wraps the tag name in angle brackets for display.
    private func tagPortion(_ tag: String) -> String {
        "<\(tag)>"
    }
}
