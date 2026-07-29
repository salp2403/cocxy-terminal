// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalSemanticNavigation.swift - Shared semantic-grid navigation contract.

import Foundation

public enum TerminalSemanticNavigationAction: String, Codable, CaseIterable, Sendable {
    case previousPrompt = "previous_prompt"
    case nextPrompt = "next_prompt"
    case selectCommandOutput = "select_command_output"
}

public enum TerminalSemanticBlockKind: UInt8, Codable, Sendable {
    case prompt = 0
    case commandInput = 1
    case commandOutput = 2
    case errorOutput = 3
    case toolCall = 4
    case agentStatus = 5
    case unknown = 6
}

public struct TerminalSemanticRegion: Equatable, Sendable {
    public let offset: UInt32?
    public let blockID: UInt64?
    public let kind: TerminalSemanticBlockKind
    public let startRow: UInt32
    public let endRow: UInt32

    public init(
        offset: UInt32? = nil,
        blockID: UInt64? = nil,
        kind: TerminalSemanticBlockKind,
        startRow: UInt32,
        endRow: UInt32
    ) {
        self.offset = offset
        self.blockID = blockID
        self.kind = kind
        self.startRow = startRow
        self.endRow = endRow
    }
}

public struct TerminalSemanticSelection: Codable, Equatable, Sendable {
    public let blockID: UInt64
    public let startRow: UInt32
    public let startColumn: UInt16
    public let endRow: UInt32
    public let endColumn: UInt16
    public let text: String

    public init(
        blockID: UInt64,
        startRow: UInt32,
        startColumn: UInt16,
        endRow: UInt32,
        endColumn: UInt16,
        text: String
    ) {
        self.blockID = blockID
        self.startRow = startRow
        self.startColumn = startColumn
        self.endRow = endRow
        self.endColumn = endColumn
        self.text = text
    }

    public func contains(absoluteRow row: UInt32, column: UInt16) -> Bool {
        guard row >= startRow, row <= endRow else { return false }
        if startRow == endRow {
            return column >= startColumn && column <= endColumn
        }
        if row == startRow { return column >= startColumn }
        if row == endRow { return column <= endColumn }
        return true
    }
}

public struct TerminalSemanticNavigationResult: Codable, Equatable, Sendable {
    public let action: TerminalSemanticNavigationAction
    public let viewportStartRow: UInt32
    public let selection: TerminalSemanticSelection?

    public init(
        action: TerminalSemanticNavigationAction,
        viewportStartRow: UInt32,
        selection: TerminalSemanticSelection? = nil
    ) {
        self.action = action
        self.viewportStartRow = viewportStartRow
        self.selection = selection
    }
}

public enum TerminalSemanticNavigationResolver {
    public static func promptRegion(
        for action: TerminalSemanticNavigationAction,
        visibleStartRow: UInt32,
        regions: [TerminalSemanticRegion],
        maximumSearchSteps: Int,
        findOlder: (UInt32) -> Int32,
        findNewer: (UInt32) -> Int32
    ) -> TerminalSemanticRegion? {
        let prompts = regions.filter {
            $0.kind == .prompt && $0.offset != nil && $0.startRow <= $0.endRow
        }
        guard prompts.isEmpty == false, maximumSearchSteps > 0 else { return nil }
        let byOffset = Dictionary(uniqueKeysWithValues: prompts.compactMap { region in
            region.offset.map { ($0, region) }
        })

        switch action {
        case .previousPrompt:
            guard let anchor = nearestPrompt(
                in: prompts,
                where: { $0.startRow >= visibleStartRow },
                orderedBy: { lhs, rhs in
                    lhs.startRow < rhs.startRow ||
                        (lhs.startRow == rhs.startRow && (lhs.offset ?? 0) < (rhs.offset ?? 0))
                }
            ) else {
                return prompts
                    .filter { $0.startRow < visibleStartRow }
                    .max(by: promptRowAscending)
            }
            return searchPrompt(
                from: anchor.offset,
                maximumSearchSteps: maximumSearchSteps,
                search: findOlder,
                byOffset: byOffset,
                accepts: { $0.startRow < visibleStartRow }
            )

        case .nextPrompt:
            guard let anchor = nearestPrompt(
                in: prompts,
                where: { $0.startRow <= visibleStartRow },
                orderedBy: { lhs, rhs in
                    lhs.startRow > rhs.startRow ||
                        (lhs.startRow == rhs.startRow && (lhs.offset ?? 0) > (rhs.offset ?? 0))
                }
            ) else {
                return prompts
                    .filter { $0.startRow > visibleStartRow }
                    .min(by: promptRowAscending)
            }
            return searchPrompt(
                from: anchor.offset,
                maximumSearchSteps: maximumSearchSteps,
                search: findNewer,
                byOffset: byOffset,
                accepts: { $0.startRow > visibleStartRow }
            )

        case .selectCommandOutput:
            return nil
        }
    }

    public static func commandOutputRegion(
        visibleStartRow: UInt32,
        regions: [TerminalSemanticRegion]
    ) -> TerminalSemanticRegion? {
        let outputs = regions.filter {
            ($0.kind == .commandOutput || $0.kind == .errorOutput) &&
                $0.blockID != nil &&
                $0.startRow <= $0.endRow
        }
        guard outputs.isEmpty == false else { return nil }

        let containingOutputs = outputs.filter {
            $0.startRow <= visibleStartRow && visibleStartRow <= $0.endRow
        }
        if let containing = containingOutputs.max(by: regionStartAscending) {
            return containing
        }

        let prompts = regions.filter {
            $0.kind == .prompt && $0.startRow <= $0.endRow
        }
        let precedingPrompts = prompts.filter { $0.startRow <= visibleStartRow }
        if let currentPrompt = precedingPrompts.max(by: regionStartAscending) {
            let nextPromptRow = prompts
                .filter { $0.startRow > currentPrompt.startRow }
                .map(\.startRow)
                .min()
            let currentCommandOutputs = outputs.filter { output in
                guard output.startRow >= currentPrompt.startRow else { return false }
                return nextPromptRow.map { output.startRow < $0 } ?? true
            }
            if let output = currentCommandOutputs.min(by: regionStartAscending) {
                return output
            }
            let priorOutputs = outputs.filter { $0.endRow < currentPrompt.startRow }
            if let completed = priorOutputs.max(by: regionEndAscending) {
                return completed
            }
        }

        return outputs
            .filter { $0.startRow > visibleStartRow }
            .min(by: regionStartAscending)
            ?? outputs
                .filter { $0.endRow < visibleStartRow }
                .max(by: regionEndAscending)
    }

    private static func nearestPrompt(
        in prompts: [TerminalSemanticRegion],
        where predicate: (TerminalSemanticRegion) -> Bool,
        orderedBy areInIncreasingOrder: (TerminalSemanticRegion, TerminalSemanticRegion) -> Bool
    ) -> TerminalSemanticRegion? {
        prompts.filter(predicate).sorted(by: areInIncreasingOrder).first
    }

    private static func searchPrompt(
        from initialOffset: UInt32?,
        maximumSearchSteps: Int,
        search: (UInt32) -> Int32,
        byOffset: [UInt32: TerminalSemanticRegion],
        accepts: (TerminalSemanticRegion) -> Bool
    ) -> TerminalSemanticRegion? {
        guard var offset = initialOffset else { return nil }
        for _ in 0..<maximumSearchSteps {
            let found = search(offset)
            guard found >= 0 else { return nil }
            let nextOffset = UInt32(found)
            guard nextOffset != offset else { return nil }
            if let region = byOffset[nextOffset], accepts(region) {
                return region
            }
            offset = nextOffset
        }
        return nil
    }

    private static func promptRowAscending(
        _ lhs: TerminalSemanticRegion,
        _ rhs: TerminalSemanticRegion
    ) -> Bool {
        lhs.startRow < rhs.startRow ||
            (lhs.startRow == rhs.startRow && (lhs.offset ?? 0) > (rhs.offset ?? 0))
    }

    private static func regionStartAscending(
        _ lhs: TerminalSemanticRegion,
        _ rhs: TerminalSemanticRegion
    ) -> Bool {
        lhs.startRow < rhs.startRow ||
            (lhs.startRow == rhs.startRow && lhs.endRow < rhs.endRow)
    }

    private static func regionEndAscending(
        _ lhs: TerminalSemanticRegion,
        _ rhs: TerminalSemanticRegion
    ) -> Bool {
        lhs.endRow < rhs.endRow ||
            (lhs.endRow == rhs.endRow && lhs.startRow < rhs.startRow)
    }
}
