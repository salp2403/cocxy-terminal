// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabConfigLayout.swift - Project-scoped reusable pane layout schema.

import Foundation

struct TabConfigPane: Equatable, Sendable {
    let type: PanelType
    let workingDirectory: String?
    let filePath: String?
    let initialURL: URL?
    let title: String?

    init(
        type: PanelType = .terminal,
        workingDirectory: String? = nil,
        filePath: String? = nil,
        initialURL: URL? = nil,
        title: String? = nil
    ) {
        self.type = type
        self.workingDirectory = workingDirectory
        self.filePath = filePath
        self.initialURL = initialURL
        self.title = title
    }
}

indirect enum TabConfigLayout: Equatable, Sendable {
    case pane(TabConfigPane)
    case split(
        direction: SplitDirection,
        ratio: Double,
        first: TabConfigLayout,
        second: TabConfigLayout
    )

    var panes: [TabConfigPane] {
        switch self {
        case .pane(let pane):
            return [pane]
        case .split(_, _, let first, let second):
            return first.panes + second.panes
        }
    }

    var depth: Int {
        switch self {
        case .pane:
            return 1
        case .split(_, _, let first, let second):
            return 1 + max(first.depth, second.depth)
        }
    }
}

enum TabConfigLayoutTOMLCodec {
    private struct ParseState {
        var activeNodeIDs = Set<String>()
        var consumedNodeIDs = Set<String>()
    }

    private static let maximumPaneCount = 4
    private static let maximumDepth = 4
    private static let minimumRatio = 0.1
    private static let maximumRatio = 0.9
    private static let nodePrefix = "layout.node."

    static func parse(from parsed: [String: TOMLValue]) throws -> TabConfigLayout? {
        let nodeTables = try layoutNodeTables(from: parsed)
        guard parsed["layout"] != nil || !nodeTables.isEmpty else { return nil }
        guard case .table(let layoutTable)? = parsed["layout"],
              let rootID = nonEmptyString(layoutTable["root"]) else {
            throw TabConfigStoreError.invalidConfig("layout requires a root node")
        }
        guard Set(layoutTable.keys) == ["root"] else {
            throw TabConfigStoreError.invalidConfig("layout contains unsupported fields")
        }
        guard isValidNodeID(rootID) else {
            throw TabConfigStoreError.invalidConfig("layout root node id is invalid")
        }

        var state = ParseState()
        let layout = try parseNode(rootID, tables: nodeTables, state: &state)
        guard state.consumedNodeIDs.count == nodeTables.count else {
            throw TabConfigStoreError.invalidConfig("layout contains unreachable nodes")
        }
        try validate(layout)
        return layout
    }

    static func render(_ layout: TabConfigLayout) -> [String] {
        var nextID = 0
        let rendered = renderNode(layout, nextID: &nextID)
        var lines = [
            "[layout]",
            "root = \"\(rendered.id)\"",
        ]
        for section in rendered.sections {
            lines.append("")
            lines.append(contentsOf: section)
        }
        return lines
    }

    static func validate(_ layout: TabConfigLayout) throws {
        let panes = layout.panes
        guard !panes.isEmpty, panes.count <= maximumPaneCount else {
            throw TabConfigStoreError.invalidConfig("layout must contain between one and four panes")
        }
        guard layout.depth <= maximumDepth else {
            throw TabConfigStoreError.invalidConfig("layout nesting exceeds four levels")
        }
        guard panes.first?.type == .terminal else {
            throw TabConfigStoreError.invalidConfig("layout first pane must be a terminal")
        }
        try validateNode(layout)
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= 4_096,
              !trimmed.hasPrefix("/"),
              !trimmed.contains("\0") else {
            return false
        }
        return trimmed.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            $0 != ".." && $0 != ""
        }
    }

    private static func parseNode(
        _ nodeID: String,
        tables: [String: [String: TOMLValue]],
        state: inout ParseState
    ) throws -> TabConfigLayout {
        guard !state.activeNodeIDs.contains(nodeID) else {
            throw TabConfigStoreError.invalidConfig("layout contains a cycle")
        }
        guard !state.consumedNodeIDs.contains(nodeID) else {
            throw TabConfigStoreError.invalidConfig("layout node is referenced more than once")
        }
        guard let table = tables[nodeID], let kind = nonEmptyString(table["kind"]) else {
            throw TabConfigStoreError.invalidConfig("layout node \(nodeID) is missing")
        }

        state.activeNodeIDs.insert(nodeID)
        defer { state.activeNodeIDs.remove(nodeID) }

        let node: TabConfigLayout
        switch kind {
        case "pane":
            node = try parsePane(nodeID: nodeID, table: table)
        case "split":
            node = try parseSplit(nodeID: nodeID, table: table, tables: tables, state: &state)
        default:
            throw TabConfigStoreError.invalidConfig("layout node \(nodeID) has an invalid kind")
        }
        state.consumedNodeIDs.insert(nodeID)
        return node
    }

    private static func parsePane(
        nodeID: String,
        table: [String: TOMLValue]
    ) throws -> TabConfigLayout {
        let allowed = Set(["kind", "type", "working-directory", "file-path", "url", "title"])
        guard Set(table.keys).isSubset(of: allowed),
              let rawType = nonEmptyString(table["type"]),
              let type = PanelType(rawValue: rawType) else {
            throw TabConfigStoreError.invalidConfig("layout pane \(nodeID) is invalid")
        }
        let rawURL = nonEmptyString(table["url"])
        let initialURL: URL?
        if let rawURL {
            guard let url = URL(string: rawURL) else {
                throw TabConfigStoreError.invalidConfig("layout pane \(nodeID) has an invalid URL")
            }
            initialURL = url
        } else {
            initialURL = nil
        }
        return .pane(TabConfigPane(
            type: type,
            workingDirectory: nonEmptyString(table["working-directory"]),
            filePath: nonEmptyString(table["file-path"]),
            initialURL: initialURL,
            title: nonEmptyString(table["title"])
        ))
    }

    private static func parseSplit(
        nodeID: String,
        table: [String: TOMLValue],
        tables: [String: [String: TOMLValue]],
        state: inout ParseState
    ) throws -> TabConfigLayout {
        let allowed = Set(["kind", "direction", "ratio", "first", "second"])
        guard Set(table.keys) == allowed,
              let rawDirection = nonEmptyString(table["direction"]),
              let direction = SplitDirection(rawValue: rawDirection),
              let ratio = doubleValue(table["ratio"]),
              let firstID = nonEmptyString(table["first"]),
              let secondID = nonEmptyString(table["second"]),
              isValidNodeID(firstID), isValidNodeID(secondID) else {
            throw TabConfigStoreError.invalidConfig("layout split \(nodeID) is invalid")
        }
        return .split(
            direction: direction,
            ratio: ratio,
            first: try parseNode(firstID, tables: tables, state: &state),
            second: try parseNode(secondID, tables: tables, state: &state)
        )
    }

    private static func validateNode(_ layout: TabConfigLayout) throws {
        switch layout {
        case .pane(let pane):
            try validatePane(pane)
        case .split(_, let ratio, let first, let second):
            guard ratio.isFinite, ratio >= minimumRatio, ratio <= maximumRatio else {
                throw TabConfigStoreError.invalidConfig("layout split ratio must be between 0.1 and 0.9")
            }
            try validateNode(first)
            try validateNode(second)
        }
    }

    private static func validatePane(_ pane: TabConfigPane) throws {
        guard pane.type != .subagent else {
            throw TabConfigStoreError.invalidConfig("subagent panes cannot be reused in a layout")
        }
        if let workingDirectory = pane.workingDirectory {
            guard pane.type == .terminal, isSafeRelativePath(workingDirectory) else {
                throw TabConfigStoreError.invalidConfig("pane working-directory must be project-relative")
            }
        }
        if let filePath = pane.filePath {
            let fileBackedTypes: Set<PanelType> = [
                .markdown, .editor, .notebook, .workflow, .aiEditHistory,
                .templates, .macros, .dbCloud, .projectHome,
            ]
            guard fileBackedTypes.contains(pane.type), isSafeRelativePath(filePath) else {
                throw TabConfigStoreError.invalidConfig("pane file-path must be project-relative")
            }
        }
        if let title = pane.title, title.utf8.count > 128 {
            throw TabConfigStoreError.invalidConfig("pane title exceeds 128 bytes")
        }
        if let initialURL = pane.initialURL {
            guard pane.type == .browser, isLoopbackURL(initialURL) else {
                throw TabConfigStoreError.invalidConfig("browser pane URLs must use loopback HTTP")
            }
        }
    }

    private static func layoutNodeTables(
        from parsed: [String: TOMLValue]
    ) throws -> [String: [String: TOMLValue]] {
        var result: [String: [String: TOMLValue]] = [:]
        for key in parsed.keys where key.hasPrefix("layout.") && !key.hasPrefix(nodePrefix) {
            throw TabConfigStoreError.invalidConfig("layout contains an unsupported table: \(key)")
        }
        for (key, value) in parsed where key.hasPrefix(nodePrefix) {
            let nodeID = String(key.dropFirst(nodePrefix.count))
            guard isValidNodeID(nodeID), case .table(let table) = value else {
                throw TabConfigStoreError.invalidConfig("layout node table is invalid")
            }
            result[nodeID] = table
        }
        return result
    }

    private static func renderNode(
        _ node: TabConfigLayout,
        nextID: inout Int
    ) -> (id: String, sections: [[String]]) {
        let id = "n\(nextID)"
        nextID += 1

        switch node {
        case .pane(let pane):
            var section = [
                "[\(nodePrefix)\(id)]",
                "kind = \"pane\"",
                "type = \"\(pane.type.rawValue)\"",
            ]
            appendString(pane.workingDirectory, key: "working-directory", to: &section)
            appendString(pane.filePath, key: "file-path", to: &section)
            appendString(pane.initialURL?.absoluteString, key: "url", to: &section)
            appendString(pane.title, key: "title", to: &section)
            return (id, [section])

        case .split(let direction, let ratio, let first, let second):
            let firstRendered = renderNode(first, nextID: &nextID)
            let secondRendered = renderNode(second, nextID: &nextID)
            let section = [
                "[\(nodePrefix)\(id)]",
                "kind = \"split\"",
                "direction = \"\(direction.rawValue)\"",
                "ratio = \(ratio)",
                "first = \"\(firstRendered.id)\"",
                "second = \"\(secondRendered.id)\"",
            ]
            return (id, [section] + firstRendered.sections + secondRendered.sections)
        }
    }

    private static func appendString(_ value: String?, key: String, to lines: inout [String]) {
        guard let value else { return }
        lines.append("\(key) = \"\(escape(value))\"")
    }

    private static func nonEmptyString(_ value: TOMLValue?) -> String? {
        guard case .string(let value)? = value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func doubleValue(_ value: TOMLValue?) -> Double? {
        switch value {
        case .float(let value): return value
        case .integer(let value): return Double(value)
        default: return nil
        }
    }

    private static func isValidNodeID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 64 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isLoopbackURL(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "::1" || isIPv4Loopback(host)
    }

    private static func isIPv4Loopback(_ host: String) -> Bool {
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4,
              components.first == "127" else {
            return false
        }
        return components.allSatisfy { component in
            guard !component.isEmpty,
                  component.allSatisfy(\.isNumber),
                  let octet = UInt8(component) else {
                return false
            }
            return String(octet) == component || component.allSatisfy { $0 == "0" }
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
