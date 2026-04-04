// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+CLICommands.swift - Helpers backing CLI socket providers.

import AppKit
import Foundation

extension AppDelegate {

    @MainActor
    func timelineQuery(for tabIDString: String?) -> TimelineQueryResult? {
        guard let store = agentTimelineStore else { return nil }

        if let tabIDString {
            guard let tabUUID = UUID(uuidString: tabIDString),
                  let windowController,
                  windowController.tabManager.tabs.contains(where: { $0.id.rawValue == tabUUID }) else {
                return nil
            }

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
        guard let windowController else { return nil }

        let resolvedTabID: String?
        let lines: [String]

        if let tabIDString {
            guard let tabUUID = UUID(uuidString: tabIDString) else { return nil }
            let tabID = TabID(rawValue: tabUUID)
            guard windowController.tabManager.tabs.contains(where: { $0.id == tabID }) else {
                return nil
            }
            lines = windowController.tabOutputBuffers[tabID]?.lines ?? []
            resolvedTabID = tabIDString
        } else {
            lines = windowController.terminalOutputBuffer.lines
            resolvedTabID = windowController.tabManager.activeTabID?.rawValue.uuidString
        }

        let engine = ScrollbackSearchEngineImpl()
        let options = SearchOptions(
            query: query,
            caseSensitive: caseSensitive,
            useRegex: regex
        )
        let results = engine.search(options: options, in: lines)

        return SearchCommandResult(
            tabID: resolvedTabID,
            lineCount: lines.count,
            results: results
        )
    }

    @MainActor
    func focusSplit(in direction: NavigationDirection) -> Bool {
        guard let windowController,
              let activeTabID = windowController.tabManager.activeTabID else {
            return false
        }

        let splitManager = windowController.tabSplitCoordinator.splitManager(for: activeTabID)
        return splitManager.focusInDirection(direction)
    }

    @MainActor
    func swapSplit(in direction: NavigationDirection) -> Bool {
        guard let windowController,
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
        guard let windowController,
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
        guard let windowController,
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
