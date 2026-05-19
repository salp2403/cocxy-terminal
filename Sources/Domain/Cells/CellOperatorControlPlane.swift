// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CellOperatorControlPlane.swift - Private self-hosted Cocxy Cells control plane.

import Foundation

enum CellOperatorError: Error, Equatable, Sendable {
    case unsupportedProvider(CellProviderKind)
    case cellNotFound(UUID)
    case emptyCommand
}

struct CellOperatorSnapshot: Equatable, Sendable {
    let cells: [Cell]
    let providerCount: Int
    let runningCount: Int
}

actor CellOperatorControlPlane {
    private let providers: [CellProviderKind: any CellProvider]
    private var cellProviderIndex: [UUID: CellProviderKind]

    init(
        providers: [CellProviderKind: any CellProvider],
        cellProviderIndex: [UUID: CellProviderKind] = [:]
    ) {
        self.providers = providers
        self.cellProviderIndex = cellProviderIndex
    }

    func create(provider kind: CellProviderKind, request: CellCreateRequest) async throws -> Cell {
        let provider = try provider(for: kind)
        let cell = try await provider.create(request)
        cellProviderIndex[cell.id] = kind
        return cell
    }

    func list() async throws -> [Cell] {
        var cells: [Cell] = []
        for (kind, provider) in orderedProviders() {
            let providerCells = try await provider.list()
            for cell in providerCells {
                cellProviderIndex[cell.id] = kind
            }
            cells.append(contentsOf: providerCells)
        }
        return cells.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func snapshot() async throws -> CellOperatorSnapshot {
        let cells = try await list()
        return CellOperatorSnapshot(
            cells: cells,
            providerCount: providers.count,
            runningCount: cells.filter { $0.status == .running }.count
        )
    }

    func status(cellID: UUID) async throws -> CellStatus {
        let provider = try await providerForCell(cellID)
        return try await provider.status(cellID: cellID)
    }

    func exec(cellID: UUID, command: [String]) async throws -> String {
        guard !command.isEmpty else {
            throw CellOperatorError.emptyCommand
        }
        let provider = try await providerForCell(cellID)
        return try await provider.exec(cellID: cellID, command: command)
    }

    func attachCommand(cellID: UUID) async throws -> CellAttachCommand {
        let provider = try await providerForCell(cellID)
        return try await provider.attachCommand(cellID: cellID)
    }

    func logs(cellID: UUID) async throws -> String {
        let provider = try await providerForCell(cellID)
        return try await provider.logs(cellID: cellID)
    }

    func destroy(cellID: UUID, force: Bool) async throws {
        let provider = try await providerForCell(cellID)
        try await provider.destroy(cellID: cellID, force: force)
        cellProviderIndex.removeValue(forKey: cellID)
    }

    private func provider(for kind: CellProviderKind) throws -> any CellProvider {
        guard let provider = providers[kind] else {
            throw CellOperatorError.unsupportedProvider(kind)
        }
        return provider
    }

    private func providerForCell(_ cellID: UUID) async throws -> any CellProvider {
        if let kind = cellProviderIndex[cellID],
           let provider = providers[kind] {
            return provider
        }

        for (kind, provider) in orderedProviders() {
            let cells = try await provider.list()
            if cells.contains(where: { $0.id == cellID }) {
                cellProviderIndex[cellID] = kind
                return provider
            }
        }

        throw CellOperatorError.cellNotFound(cellID)
    }

    private func orderedProviders() -> [(CellProviderKind, any CellProvider)] {
        providers.sorted { $0.key.rawValue < $1.key.rawValue }
    }
}
