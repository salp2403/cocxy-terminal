// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppSocketCommandHandler+CellHandlers.swift - Cocxy Cells CLI bridge.

import Foundation

extension AppSocketCommandHandler {
    func handleCell(kind: String, request: SocketRequest) -> SocketResponse {
        guard let provider = cellCLIProvider else {
            return .failure(id: request.id, error: "Cells not available")
        }
        let result = provider(kind, request.params ?? [:])
        guard result.success else {
            return .failure(id: request.id, error: result.data["error"] ?? "Cell command failed")
        }
        return .ok(id: request.id, data: result.data)
    }
}
