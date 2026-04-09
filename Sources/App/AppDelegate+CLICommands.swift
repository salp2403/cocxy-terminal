// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+CLICommands.swift - Helpers backing CLI socket providers.

import AppKit
import Foundation

extension AppDelegate {

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
            data["alt_screen"] = modeDetails.altScreen ? "true" : "false"
            data["semantic_block_count"] = "\(modeDetails.semanticBlockCount)"
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

        guard cocxyBridge.sendProtocolV2Message(type: type, json: payload, to: surfaceID) else {
            return nil
        }
        return [
            "status": "sent",
            "type": type
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
