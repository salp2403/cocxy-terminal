// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+CLICommands.swift - Helpers backing CLI socket providers.

import AppKit
import Darwin
import Foundation

extension AppDelegate {

    private struct SemanticBlockPayload: Encodable {
        let type: UInt8
        let typeName: String
        let detail: String
        let exitCode: Int16
        let startRow: UInt32
        let endRow: UInt32
        let streamID: UInt32
        let timestampStart: UInt64
        let timestampEnd: UInt64
    }

    private struct SemanticSummaryPayload: Encodable {
        let state: UInt8
        let stateName: String
        let currentBlockType: UInt8?
        let currentBlockName: String?
        let totalBlockCount: UInt32
        let promptBlockCount: UInt32
        let commandInputBlockCount: UInt32
        let commandOutputBlockCount: UInt32
        let errorBlockCount: UInt32
        let toolBlockCount: UInt32
        let agentBlockCount: UInt32
        let recentBlocks: [SemanticBlockPayload]
    }

    @MainActor
    private func activeTerminalSurfaceForCLI() -> (controller: MainWindowController, surfaceID: SurfaceID)? {
        guard let controller = focusedWindowController() ?? windowController else { return nil }
        guard let surfaceID = controller.focusedSplitSurfaceView?.terminalViewModel?.surfaceID
            ?? controller.activeTerminalSurfaceView?.terminalViewModel?.surfaceID else {
            return nil
        }
        return (controller, surfaceID)
    }

    @MainActor
    func runtimeStatusDetailsForCLI() -> [String: String] {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI() else {
            return [:]
        }

        var data: [String: String] = [:]

        if let search = cocxyBridge.searchDiagnostics(for: surfaceID) {
            data["search_mode"] = search.gpuActive ? "gpu" : "cpu"
            data["search_indexed_rows"] = "\(search.indexedRows)"
        }

        if let protocolDetails = cocxyBridge.protocolDiagnostics(for: surfaceID) {
            data["protocol_v2_observed"] = protocolDetails.observed ? "true" : "false"
            data["protocol_v2_capabilities_requested"] = protocolDetails.capabilitiesRequested ? "true" : "false"
            data["current_stream_id"] = "\(protocolDetails.currentStreamID)"
        }

        if let modeDetails = cocxyBridge.modeDiagnostics(for: surfaceID) {
            data["cursor_visible"] = modeDetails.cursorVisible ? "true" : "false"
            data["app_cursor_mode"] = modeDetails.appCursorMode ? "true" : "false"
            data["bracketed_paste_mode"] = modeDetails.bracketedPasteMode ? "true" : "false"
            data["mouse_tracking_mode"] = "\(modeDetails.mouseTrackingMode)"
            data["kitty_keyboard_mode"] = "\(modeDetails.kittyKeyboardMode)"
            data["alt_screen"] = modeDetails.altScreen ? "true" : "false"
            data["cursor_shape"] = "\(modeDetails.cursorShape)"
            data["preedit_active"] = modeDetails.preeditActive ? "true" : "false"
            data["semantic_block_count"] = "\(modeDetails.semanticBlockCount)"
        }

        if let process = cocxyBridge.processDiagnostics(for: surfaceID) {
            data["child_pid"] = "\(process.childPID)"
            data["process_alive"] = process.isAlive ? "true" : "false"
        }

        if let fontMetrics = cocxyBridge.fontMetricsSnapshot(for: surfaceID) {
            data["font_cell_width"] = formattedFloat(fontMetrics.cellWidth)
            data["font_cell_height"] = formattedFloat(fontMetrics.cellHeight)
            data["font_ascent"] = formattedFloat(fontMetrics.ascent)
            data["font_descent"] = formattedFloat(fontMetrics.descent)
            data["font_leading"] = formattedFloat(fontMetrics.leading)
            data["font_underline_position"] = formattedFloat(fontMetrics.underlinePosition)
            data["font_underline_thickness"] = formattedFloat(fontMetrics.underlineThickness)
            data["font_strikethrough_position"] = formattedFloat(fontMetrics.strikethroughPosition)
        }

        if let selection = cocxyBridge.selectionSnapshot(for: surfaceID) {
            data["selection_active"] = selection.active ? "true" : "false"
            if let startRow = selection.startRow, let startCol = selection.startCol,
               let endRow = selection.endRow, let endCol = selection.endCol {
                data["selection_start_row"] = "\(startRow)"
                data["selection_start_col"] = "\(startCol)"
                data["selection_end_row"] = "\(endRow)"
                data["selection_end_col"] = "\(endCol)"
            }
            if let text = selection.text {
                data["selection_text_bytes"] = "\(text.utf8.count)"
            }
        }

        if let preedit = cocxyBridge.preeditSnapshot(for: surfaceID), preedit.active {
            data["preedit_text_bytes"] = "\(preedit.text.utf8.count)"
            data["preedit_cursor_bytes"] = "\(preedit.cursorBytes)"
            data["preedit_anchor_row"] = "\(preedit.anchorRow)"
            data["preedit_anchor_col"] = "\(preedit.anchorCol)"
        }

        if let semantic = cocxyBridge.semanticDiagnostics(for: surfaceID) {
            data["semantic_state"] = "\(semantic.state)"
            data["semantic_state_name"] = semanticStateName(semantic.state)
            if let currentBlockType = semantic.currentBlockType {
                data["semantic_current_block_type"] = "\(currentBlockType)"
                data["semantic_current_block_name"] = semanticBlockTypeName(currentBlockType)
            }
            data["semantic_prompt_blocks"] = "\(semantic.promptBlockCount)"
            data["semantic_command_input_blocks"] = "\(semantic.commandInputBlockCount)"
            data["semantic_command_output_blocks"] = "\(semantic.commandOutputBlockCount)"
            data["semantic_error_blocks"] = "\(semantic.errorBlockCount)"
            data["semantic_tool_blocks"] = "\(semantic.toolBlockCount)"
            data["semantic_agent_blocks"] = "\(semantic.agentBlockCount)"
        }

        if let ligatures = cocxyBridge.ligatureDiagnostics(for: surfaceID) {
            data["ligatures_enabled"] = ligatures.enabled ? "true" : "false"
            data["ligature_cache_hits"] = "\(ligatures.cacheHits)"
            data["ligature_cache_misses"] = "\(ligatures.cacheMisses)"
        }

        if let images = cocxyBridge.imageDiagnostics(for: surfaceID) {
            data["image_count"] = "\(images.imageCount)"
            data["image_memory_used_bytes"] = "\(images.memoryUsedBytes)"
            data["image_memory_used_mib"] = "\(images.memoryUsedBytes / (1024 * 1024))"
            data["image_memory_limit_bytes"] = "\(images.memoryLimitBytes)"
            data["image_memory_limit_mib"] = "\(images.memoryLimitBytes / (1024 * 1024))"
            data["image_file_transfer_enabled"] = images.fileTransferEnabled ? "true" : "false"
            data["image_sixel_enabled"] = images.sixelEnabled ? "true" : "false"
            data["image_kitty_enabled"] = images.kittyEnabled ? "true" : "false"
            data["image_atlas_width"] = "\(images.atlasWidth)"
            data["image_atlas_height"] = "\(images.atlasHeight)"
            data["image_atlas_generation"] = "\(images.atlasGeneration)"
            data["image_atlas_dirty"] = images.atlasDirty ? "true" : "false"
        }

        let streams = cocxyBridge.streamSnapshots(for: surfaceID)
        data["stream_count"] = "\(streams.count)"
        for (index, stream) in streams.enumerated() {
            data["stream_\(index)_id"] = "\(stream.streamID)"
            data["stream_\(index)_pid"] = "\(stream.pid)"
            data["stream_\(index)_parent_pid"] = "\(stream.parentPID)"
            data["stream_\(index)_state"] = "\(stream.state)"
            data["stream_\(index)_exit_code"] = "\(stream.exitCode)"
        }

        let webStatus = cocxyBridge.webTerminalStatus(for: surfaceID)
        for (key, value) in webStatusDictionary(from: webStatus) {
            data["web_\(key)"] = value
        }

        return data
    }

    @MainActor
    func startWebTerminalForCLI(
        bindAddress: String,
        port: UInt16,
        token: String,
        maxConnections: UInt16,
        maxFPS: UInt32
    ) -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI() else {
            return nil
        }

        let configuration = WebTerminalConfiguration(
            bindAddress: bindAddress,
            port: port,
            authToken: token,
            maxConnections: min(max(maxConnections, 1), 16),
            maxFrameRate: min(max(maxFPS, 1), 240)
        )

        guard let status = cocxyBridge.startWebTerminal(for: surfaceID, configuration: configuration) else {
            return nil
        }
        return webStatusDictionary(from: status)
    }

    @MainActor
    func stopWebTerminalForCLI() -> Bool {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI() else {
            return false
        }

        guard cocxyBridge.webTerminalStatus(for: surfaceID) != nil else { return false }
        cocxyBridge.stopWebTerminal(for: surfaceID)
        return true
    }

    @MainActor
    func webStatusForCLI() -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI() else {
            return nil
        }
        return webStatusDictionary(from: cocxyBridge.webTerminalStatus(for: surfaceID))
    }

    @MainActor
    func streamListForCLI() -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI() else {
            return nil
        }

        let streams = cocxyBridge.streamSnapshots(for: surfaceID)
        var data: [String: String] = ["count": "\(streams.count)"]
        if let protocolDetails = cocxyBridge.protocolDiagnostics(for: surfaceID) {
            data["current_stream_id"] = "\(protocolDetails.currentStreamID)"
        }
        for (index, stream) in streams.enumerated() {
            data["stream_\(index)_id"] = "\(stream.streamID)"
            data["stream_\(index)_pid"] = "\(stream.pid)"
            data["stream_\(index)_parent_pid"] = "\(stream.parentPID)"
            data["stream_\(index)_state"] = "\(stream.state)"
            data["stream_\(index)_exit_code"] = "\(stream.exitCode)"
        }
        return data
    }

    @MainActor
    func resetTerminalForCLI() -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI(),
              cocxyBridge.resetTerminal(for: surfaceID) else {
            return nil
        }

        return ["status": "reset"]
    }

    @MainActor
    func sendSignalForCLI(_ signal: Int32) -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI(),
              cocxyBridge.sendSignal(signal, to: surfaceID) else {
            return nil
        }

        return [
            "status": "sent",
            "signal": "\(signal)",
        ]
    }

    @MainActor
    func processDiagnosticsForCLI() -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI(),
              let diagnostics = cocxyBridge.processDiagnostics(for: surfaceID),
              let content = encodeCLIJSON(diagnostics) else {
            return nil
        }

        return ["content": content]
    }

    @MainActor
    func modeDiagnosticsForCLI() -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI(),
              let diagnostics = cocxyBridge.modeDiagnostics(for: surfaceID),
              let content = encodeCLIJSON(diagnostics) else {
            return nil
        }

        return ["content": content]
    }

    @MainActor
    func searchDiagnosticsForCLI() -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI(),
              let diagnostics = cocxyBridge.searchDiagnostics(for: surfaceID),
              let content = encodeCLIJSON(diagnostics) else {
            return nil
        }

        return ["content": content]
    }

    @MainActor
    func ligatureDiagnosticsForCLI() -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI(),
              let diagnostics = cocxyBridge.ligatureDiagnostics(for: surfaceID),
              let content = encodeCLIJSON(diagnostics) else {
            return nil
        }

        return ["content": content]
    }

    @MainActor
    func protocolDiagnosticsForCLI() -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI(),
              let diagnostics = cocxyBridge.protocolDiagnostics(for: surfaceID),
              let content = encodeCLIJSON(diagnostics) else {
            return nil
        }

        return ["content": content]
    }

    @MainActor
    func selectionSnapshotForCLI() -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI(),
              let snapshot = cocxyBridge.selectionSnapshot(for: surfaceID),
              let content = encodeCLIJSON(snapshot) else {
            return nil
        }

        return ["content": content]
    }

    @MainActor
    func fontMetricsForCLI() -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI(),
              let snapshot = cocxyBridge.fontMetricsSnapshot(for: surfaceID),
              let content = encodeCLIJSON(snapshot) else {
            return nil
        }

        return ["content": content]
    }

    @MainActor
    func preeditSnapshotForCLI() -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI(),
              let snapshot = cocxyBridge.preeditSnapshot(for: surfaceID),
              let content = encodeCLIJSON(snapshot) else {
            return nil
        }

        return ["content": content]
    }

    @MainActor
    func semanticSummaryForCLI(limit: UInt32) -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI(),
              let diagnostics = cocxyBridge.semanticDiagnostics(for: surfaceID) else {
            return nil
        }

        let blocks = cocxyBridge.semanticBlocks(for: surfaceID, limit: limit).map { block in
            SemanticBlockPayload(
                type: block.blockType,
                typeName: semanticBlockTypeName(block.blockType),
                detail: block.detail,
                exitCode: block.exitCode,
                startRow: block.startRow,
                endRow: block.endRow,
                streamID: block.streamID,
                timestampStart: block.timestampStart,
                timestampEnd: block.timestampEnd
            )
        }

        let payload = SemanticSummaryPayload(
            state: diagnostics.state,
            stateName: semanticStateName(diagnostics.state),
            currentBlockType: diagnostics.currentBlockType,
            currentBlockName: diagnostics.currentBlockType.map { semanticBlockTypeName($0) },
            totalBlockCount: diagnostics.totalBlockCount,
            promptBlockCount: diagnostics.promptBlockCount,
            commandInputBlockCount: diagnostics.commandInputBlockCount,
            commandOutputBlockCount: diagnostics.commandOutputBlockCount,
            errorBlockCount: diagnostics.errorBlockCount,
            toolBlockCount: diagnostics.toolBlockCount,
            agentBlockCount: diagnostics.agentBlockCount,
            recentBlocks: blocks
        )

        guard let content = encodeCLIJSON(payload) else { return nil }
        return ["content": content]
    }

    @MainActor
    func setCurrentStreamForCLI(_ streamID: UInt32) -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI() else {
            return nil
        }

        guard cocxyBridge.setCurrentStream(streamID, for: surfaceID) else { return nil }
        return [
            "status": "current",
            "stream_id": "\(streamID)"
        ]
    }

    @MainActor
    func requestProtocolCapabilitiesForCLI() -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI() else {
            return nil
        }

        guard cocxyBridge.requestProtocolV2Capabilities(for: surfaceID) else { return nil }
        return [
            "status": "sent",
            "message": "terminal.capabilities"
        ]
    }

    @MainActor
    func sendProtocolViewportForCLI(requestID: String?) -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI() else {
            return nil
        }

        guard cocxyBridge.sendProtocolV2Viewport(for: surfaceID, requestID: requestID) else { return nil }
        var data: [String: String] = [
            "status": "sent",
            "message": "terminal.viewport"
        ]
        if let requestID, !requestID.isEmpty {
            data["request_id"] = requestID
        }
        return data
    }

    @MainActor
    func sendProtocolMessageForCLI(type: String, payload: String) -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI() else {
            return nil
        }

        let outboundSent = cocxyBridge.sendProtocolV2Message(type: type, json: payload, to: surfaceID)
        let localInjected = cocxyBridge.injectProtocolV2Message(type: type, json: payload, to: surfaceID)

        guard outboundSent || localInjected else {
            return nil
        }
        return [
            "status": outboundSent ? "sent" : "injected",
            "type": type,
            "outbound_sent": outboundSent ? "true" : "false",
            "local_injected": localInjected ? "true" : "false",
        ]
    }

    @MainActor
    func clearImagesForCLI() -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI() else {
            return nil
        }

        guard let removed = cocxyBridge.clearImages(for: surfaceID) else { return nil }
        return [
            "status": "cleared",
            "removed": "\(removed)"
        ]
    }

    @MainActor
    func listImagesForCLI() -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI() else {
            return nil
        }

        let images = cocxyBridge.imageSnapshots(for: surfaceID)
        var data: [String: String] = ["count": "\(images.count)"]
        if let diagnostics = cocxyBridge.imageDiagnostics(for: surfaceID) {
            data["memory_used_bytes"] = "\(diagnostics.memoryUsedBytes)"
            data["memory_limit_bytes"] = "\(diagnostics.memoryLimitBytes)"
            data["file_transfer_enabled"] = diagnostics.fileTransferEnabled ? "true" : "false"
            data["sixel_enabled"] = diagnostics.sixelEnabled ? "true" : "false"
            data["kitty_enabled"] = diagnostics.kittyEnabled ? "true" : "false"
            data["atlas_width"] = "\(diagnostics.atlasWidth)"
            data["atlas_height"] = "\(diagnostics.atlasHeight)"
            data["atlas_generation"] = "\(diagnostics.atlasGeneration)"
            data["atlas_dirty"] = diagnostics.atlasDirty ? "true" : "false"
        }
        for (index, image) in images.enumerated() {
            data["image_\(index)_id"] = "\(image.imageID)"
            data["image_\(index)_width"] = "\(image.width)"
            data["image_\(index)_height"] = "\(image.height)"
            data["image_\(index)_byte_size"] = "\(image.byteSize)"
            data["image_\(index)_source"] = "\(image.source)"
            data["image_\(index)_placement_count"] = "\(image.placementCount)"
        }
        return data
    }

    @MainActor
    func deleteImageForCLI(_ imageID: UInt32) -> [String: String]? {
        guard let cocxyBridge = bridge as? CocxyCoreBridge,
              let (_, surfaceID) = activeTerminalSurfaceForCLI() else {
            return nil
        }

        guard cocxyBridge.deleteImage(imageID, for: surfaceID) else { return nil }
        return [
            "status": "deleted",
            "image_id": "\(imageID)"
        ]
    }

    private func encodeCLIJSON<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func formattedFloat(_ value: Float) -> String {
        String(format: "%.2f", value)
    }

    private func semanticStateName(_ value: UInt8) -> String {
        switch Int(value) {
        case 0: return "idle"
        case 1: return "prompt"
        case 2: return "command_input"
        case 3: return "command_running"
        case 4: return "agent_active"
        default: return "unknown"
        }
    }

    private func semanticBlockTypeName(_ value: UInt8) -> String {
        switch Int(value) {
        case 0: return "prompt"
        case 1: return "command_input"
        case 2: return "command_output"
        case 3: return "error_output"
        case 4: return "tool_call"
        case 5: return "agent_status"
        default: return "unknown"
        }
    }

    @MainActor
    private func webStatusDictionary(from status: WebTerminalStatus?) -> [String: String] {
        guard let status else {
            return [
                "status": "stopped",
                "running": "false",
                "connections": "0",
            ]
        }

        var data: [String: String] = [
            "status": status.running ? "running" : "stopped",
            "running": status.running ? "true" : "false",
            "bind": status.bindAddress,
            "port": "\(status.port)",
            "connections": "\(status.connectionCount)",
            "auth_required": status.authRequired ? "true" : "false",
            "max_fps": "\(status.maxFrameRate)",
        ]
        if let eventType = status.lastEventType {
            if let connectionID = status.lastEventConnectionID {
                data["last_event"] = "\(eventType)#\(connectionID)"
            } else {
                data["last_event"] = eventType
            }
        }
        return data
    }

    @MainActor
    func activeBrowserViewModelForCLI() -> BrowserViewModel? {
        (focusedWindowController() ?? windowController)?.activeBrowserViewModel()
    }

    @MainActor
    func duplicateFocusedTabForCLI() -> (id: String, title: String)? {
        guard let controller = focusedWindowController() ?? windowController else { return nil }

        let sourceDirectory = controller.tabManager.activeTab?.workingDirectory
        controller.createTab(workingDirectory: sourceDirectory)

        guard let newTabID = controller.visibleTabID ?? controller.tabManager.activeTabID,
              let tab = controller.tabManager.tab(for: newTabID) else {
            return nil
        }

        return (id: newTabID.rawValue.uuidString, title: tab.displayTitle)
    }

    @MainActor
    func restoreSessionFromCLI(named name: String?) -> Bool {
        guard let sessionManager,
              let controller = focusedWindowController() ?? windowController else {
            return false
        }

        let session: Session
        do {
            if let name {
                guard let loaded = try sessionManager.loadSession(named: name) else { return false }
                session = loaded
            } else {
                guard let loaded = try sessionManager.loadLastSession() else { return false }
                session = loaded
            }
        } catch {
            return false
        }

        return restoreSession(session, into: controller)
    }

    @MainActor
    func timelineQuery(for tabIDString: String?) -> TimelineQueryResult? {
        guard let store = agentTimelineStore else { return nil }

        if let tabIDString {
            guard let tabUUID = UUID(uuidString: tabIDString) else {
                return nil
            }
            let tabID = TabID(rawValue: tabUUID)
            guard controllerContainingTab(tabID) != nil else { return nil }

            let sessionIDs = Set(
                agentDashboardViewModel?.sessions
                    .filter { $0.tabId == tabUUID }
                    .map(\.id) ?? []
            )
            let events = store.allEvents.filter { sessionIDs.contains($0.sessionId) }

            return TimelineQueryResult(
                tabID: tabIDString,
                sessionIDs: Array(sessionIDs).sorted(),
                events: events
            )
        }

        return TimelineQueryResult(
            tabID: nil,
            sessionIDs: [],
            events: store.allEvents
        )
    }

    @MainActor
    func exportTimeline(for tabIDString: String?, format: String) -> Data? {
        guard let query = timelineQuery(for: tabIDString) else { return nil }

        switch format {
        case "json":
            return TimelineExporter.exportJSON(events: query.events)
        case "markdown":
            return TimelineExporter.exportMarkdown(events: query.events).data(using: .utf8)
        default:
            return nil
        }
    }

    @MainActor
    func searchScrollback(
        query: String,
        regex: Bool,
        caseSensitive: Bool,
        tabIDString: String?
    ) -> SearchCommandResult? {
        let resolvedTabID: String?
        let lines: [String]
        let nativeResults: [SearchResult]?
        let options = SearchOptions(
            query: query,
            caseSensitive: caseSensitive,
            useRegex: regex
        )

        if let tabIDString {
            guard let tabUUID = UUID(uuidString: tabIDString) else { return nil }
            let tabID = TabID(rawValue: tabUUID)
            guard let controller = controllerContainingTab(tabID) else {
                return nil
            }
            if let surfaceID = controller.surfaceIDs(for: tabID).first,
               let bridge,
               let bridgeResults = bridge.searchScrollback(surfaceID: surfaceID, options: options) {
                nativeResults = bridgeResults
                if let cocxyBridge = bridge as? CocxyCoreBridge {
                    let historyLines = cocxyBridge.historyLines(for: surfaceID)
                    lines = historyLines.isEmpty ? controller.tabOutputBuffers[tabID]?.lines ?? [] : historyLines
                } else {
                    lines = controller.tabOutputBuffers[tabID]?.lines ?? []
                }
            } else {
                nativeResults = nil
                lines = controller.tabOutputBuffers[tabID]?.lines ?? []
            }
            resolvedTabID = tabIDString
        } else {
            guard let controller = focusedWindowController() ?? windowController else { return nil }
            if let surfaceID = controller.focusedSplitSurfaceView?.terminalViewModel?.surfaceID
                ?? controller.activeTerminalSurfaceView?.terminalViewModel?.surfaceID,
               let bridge,
               let bridgeResults = bridge.searchScrollback(surfaceID: surfaceID, options: options) {
                nativeResults = bridgeResults
                if let cocxyBridge = bridge as? CocxyCoreBridge {
                    let historyLines = cocxyBridge.historyLines(for: surfaceID)
                    lines = historyLines.isEmpty ? controller.terminalOutputBuffer.lines : historyLines
                } else {
                    lines = controller.terminalOutputBuffer.lines
                }
            } else {
                nativeResults = nil
                lines = controller.terminalOutputBuffer.lines
            }
            resolvedTabID = (controller.visibleTabID ?? controller.tabManager.activeTabID)?.rawValue.uuidString
        }

        let results = nativeResults ?? ScrollbackSearchEngineImpl().search(options: options, in: lines)

        return SearchCommandResult(
            tabID: resolvedTabID,
            lineCount: lines.count,
            results: results
        )
    }

    @MainActor
    func focusSplit(in direction: NavigationDirection) -> Bool {
        guard let windowController = focusedWindowController() ?? windowController,
              let activeTabID = windowController.tabManager.activeTabID else {
            return false
        }

        let splitManager = windowController.tabSplitCoordinator.splitManager(for: activeTabID)
        return splitManager.focusInDirection(direction)
    }

    @MainActor
    func swapSplit(in direction: NavigationDirection) -> Bool {
        guard let windowController = focusedWindowController() ?? windowController,
              let activeTabID = windowController.tabManager.activeTabID else {
            return false
        }

        let splitManager = windowController.tabSplitCoordinator.splitManager(for: activeTabID)
        guard splitManager.swapFocused(with: direction) else {
            return false
        }

        windowController.rebuildSplitViewHierarchy(for: activeTabID)
        return true
    }

    @MainActor
    func resizeSplit(in direction: NavigationDirection, pixels: CGFloat) -> Bool {
        guard let windowController = focusedWindowController() ?? windowController,
              let activeTabID = windowController.tabManager.activeTabID else {
            return false
        }

        let splitManager = windowController.tabSplitCoordinator.splitManager(for: activeTabID)
        guard let target = splitManager.resizeTarget(for: direction) else {
            return false
        }

        return applySplitRatioDelta(
            splitID: target.splitID,
            deltaSign: target.ratioDeltaSign,
            pixels: pixels,
            windowController: windowController,
            splitManager: splitManager
        )
    }

    @MainActor
    func setSplitRatio(splitID: UUID, ratio: CGFloat) -> Bool {
        guard let windowController = focusedWindowController() ?? windowController,
              windowController.tabManager.activeTabID != nil else {
            return false
        }

        guard let splitView = windowController.findSplitView(withID: splitID) else {
            return false
        }

        applyRatio(SplitNode.clampRatio(ratio), splitID: splitID, splitView: splitView)
        return true
    }

    @MainActor
    private func applySplitRatioDelta(
        splitID: UUID,
        deltaSign: CGFloat,
        pixels: CGFloat,
        windowController: MainWindowController,
        splitManager: SplitManager
    ) -> Bool {
        guard let splitView = windowController.findSplitView(withID: splitID),
              splitView.subviews.count == 2 else {
            return false
        }

        let totalSize = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        let availableSize = totalSize - splitView.dividerThickness
        guard availableSize > 0 else { return false }

        let firstView = splitView.subviews[0]
        let currentFirstSize = splitView.isVertical ? firstView.frame.width : firstView.frame.height
        let currentRatio = currentFirstSize / availableSize
        let ratioDelta = (pixels / availableSize) * deltaSign
        let newRatio = SplitNode.clampRatio(currentRatio + ratioDelta)

        splitManager.setRatio(splitID: splitID, ratio: newRatio)
        applyRatio(newRatio, splitID: splitID, splitView: splitView)
        return true
    }

    @MainActor
    private func applyRatio(_ ratio: CGFloat, splitID: UUID, splitView: NSSplitView) {
        guard let windowController,
              let activeTabID = windowController.tabManager.activeTabID else {
            return
        }

        let splitManager = windowController.tabSplitCoordinator.splitManager(for: activeTabID)
        let clampedRatio = SplitNode.clampRatio(ratio)
        splitManager.setRatio(splitID: splitID, ratio: clampedRatio)

        let totalSize = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        let availableSize = totalSize - splitView.dividerThickness
        guard availableSize > 0 else { return }

        splitView.setPosition(availableSize * clampedRatio, ofDividerAt: 0)
        splitView.adjustSubviews()
    }
}
