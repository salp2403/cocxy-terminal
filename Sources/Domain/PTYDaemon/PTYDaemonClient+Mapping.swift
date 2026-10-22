// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonClient+Mapping.swift - Stateless daemon request and frame mappings.

#if canImport(AppKit)
import AppKit
#endif
import CocxyShared
import Foundation

extension PTYDaemonClient {
    static func detectedContent(
        from content: PTYDaemonDetectedContent
    ) -> TerminalDetectedContent? {
        guard let kind = TerminalDetectedContentKind(rawValue: content.kind.rawValue) else {
            return nil
        }
        return TerminalDetectedContent(
            kind: kind,
            text: content.text,
            target: content.target,
            startRow: content.startRow,
            startColumn: content.startColumn,
            endRow: content.endRow,
            endColumn: content.endColumn,
            line: content.line.map(Int.init),
            column: content.column.map(Int.init),
            isExplicitHyperlink: content.isExplicitHyperlink
        )
    }

    func surfaceRequest(
        _ surface: SurfaceID,
        command: PTYDaemonRequest.Command,
        payload: [String: String] = [:]
    ) -> PTYDaemonRequest {
        var payload = payload
        payload["surfaceID"] = surface.rawValue.uuidString
        return PTYDaemonRequest(id: UUID().uuidString, command: command, payload: payload)
    }

    static func backingScale(for view: NativeTerminalView) -> Double {
        #if canImport(AppKit)
        let rawScale = view.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2.0
        let scale = Double(rawScale)
        return scale.isFinite && scale > 0 ? scale : 2.0
        #else
        return 1.0
        #endif
    }
}
