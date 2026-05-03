// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BlockSelectionMode.swift - Multi-select state for command block actions.

import Foundation

struct BlockSelectionMode: Equatable, Sendable {
    private(set) var selectedIDs: Set<UInt64> = []

    var selectedCount: Int {
        selectedIDs.count
    }

    var isActive: Bool {
        !selectedIDs.isEmpty
    }

    func contains(_ blockID: UInt64) -> Bool {
        selectedIDs.contains(blockID)
    }

    mutating func toggle(_ blockID: UInt64) {
        if selectedIDs.contains(blockID) {
            selectedIDs.remove(blockID)
        } else {
            selectedIDs.insert(blockID)
        }
    }

    mutating func prune(validIDs: Set<UInt64>) {
        selectedIDs = selectedIDs.intersection(validIDs)
    }

    func selectedBlocks(in blocks: [TerminalCommandBlock]) -> [TerminalCommandBlock] {
        blocks.filter { selectedIDs.contains($0.id) }
    }
}

enum BlockSelectionCopyFormatter {
    static func outputText(for blocks: [TerminalCommandBlock]) -> String {
        blocks
            .map { block in
                block.output.isEmpty ? block.command : block.output
            }
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
