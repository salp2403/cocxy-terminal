// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+TabConfigLayout.swift - Capture and restore project pane layouts.

import AppKit

extension MainWindowController {
    func tabConfigProjectDirectory(for tabID: TabID) -> URL? {
        if let projectRoot = tabConfigProjectContextStore.projectRoot(for: tabID) {
            return projectRoot
        }
        guard let tab = tabManager.tab(for: tabID) else { return nil }
        return projectResolver.resolveProject(for: tab.workingDirectory).rootURL
    }

    func captureTabConfigLayout(
        for tabID: TabID,
        projectDirectory: URL
    ) throws -> TabConfigLayout {
        guard (visibleTabID ?? tabManager.activeTabID) == tabID else {
            throw TabConfigLayoutRuntimeError.inconsistentLayout("tab is not visible")
        }

        let splitManager = tabSplitCoordinator.splitManager(for: tabID)
        let leafViews = collectLeafViews()
        guard leafViews.count == splitManager.rootNode.leafCount else {
            throw TabConfigLayoutRuntimeError.inconsistentLayout("pane view count differs from the split tree")
        }

        var leafIndex = 0
        let layout = try captureTabConfigNode(
            splitManager.rootNode,
            tabID: tabID,
            splitManager: splitManager,
            leafViews: leafViews,
            leafIndex: &leafIndex,
            projectDirectory: projectDirectory
        )
        guard leafIndex == leafViews.count else {
            throw TabConfigLayoutRuntimeError.inconsistentLayout("not all pane views were captured")
        }
        try TabConfigLayoutTOMLCodec.validate(layout)
        return layout
    }

    func bindTabConfigProjectDirectory(_ projectDirectory: URL, to tabID: TabID) {
        let canonical = ProjectPathCanonicalizer.canonicalURL(projectDirectory)
        tabConfigProjectContextStore.setProjectRoot(canonical, for: tabID)
        tabManager.updateTab(id: tabID) { tab in
            tab.workingDirectory = canonical
            tab.projectConfig = ProjectConfigService().loadConfig(for: canonical)
        }
        sessionRegistry?.updateWorkingDirectory(sessionIDForTab(tabID), directory: canonical)
        observeProjectDirectory(canonical)
        tabBarViewModel?.syncWithManager()
        applyProjectConfig(for: tabID)
    }

    func installTabConfigLayout(
        _ layout: ResolvedTabConfigLayout,
        in tabID: TabID
    ) throws {
        guard (visibleTabID ?? tabManager.activeTabID) == tabID,
              let primarySurfaceID = tabSurfaceMap[tabID],
              let primaryView = tabSurfaceViews[tabID],
              let primaryDirectory = layout.firstPane.workingDirectory,
              let currentWorkingDirectory = tabManager.tab(for: tabID)?.workingDirectory,
              ProjectPathCanonicalizer.canonicalURL(currentWorkingDirectory)
                == ProjectPathCanonicalizer.canonicalURL(primaryDirectory) else {
            throw TabConfigLayoutRuntimeError.inconsistentLayout("primary terminal is unavailable")
        }

        var didUsePrimaryTerminal = false
        var viewsByContentID: [UUID: NSView] = [:]
        var panelTypes: [UUID: PanelInfo] = [:]
        var panelTitles: [UUID: String] = [:]
        let rootNode = try materializeTabConfigNode(
            layout,
            tabID: tabID,
            primarySurfaceID: primarySurfaceID,
            primaryView: primaryView,
            didUsePrimaryTerminal: &didUsePrimaryTerminal,
            viewsByContentID: &viewsByContentID,
            panelTypes: &panelTypes,
            panelTitles: &panelTitles
        )
        guard didUsePrimaryTerminal,
              viewsByContentID.count == rootNode.leafCount else {
            throw TabConfigLayoutRuntimeError.inconsistentLayout("pane materialization is incomplete")
        }

        let splitManager = tabSplitCoordinator.splitManager(for: tabID)
        let focusedLeafID = rootNode.allLeafIDs().first?.leafID
        splitManager.restoreLayout(
            rootNode: rootNode,
            focusedLeafID: focusedLeafID,
            panelTypes: panelTypes,
            panelTitles: panelTitles
        )
        rebuildSplitViewHierarchy(
            for: tabID,
            viewsByTerminalIDOverride: viewsByContentID
        )
        window?.makeFirstResponder(primaryView)
        updateWorkspaceToolbar()
        refreshTabStrip(syncFromFirstResponder: false)
        auroraChromeController?.refreshSources()
    }

    private func captureTabConfigNode(
        _ node: SplitNode,
        tabID: TabID,
        splitManager: SplitManager,
        leafViews: [NSView],
        leafIndex: inout Int,
        projectDirectory: URL
    ) throws -> TabConfigLayout {
        switch node {
        case .leaf(_, let contentID):
            guard leafIndex < leafViews.count else {
                throw TabConfigLayoutRuntimeError.inconsistentLayout("pane view is missing")
            }
            let view = leafViews[leafIndex]
            leafIndex += 1
            return .pane(try captureTabConfigPane(
                contentID: contentID,
                view: view,
                tabID: tabID,
                splitManager: splitManager,
                projectDirectory: projectDirectory
            ))

        case .split(_, let direction, let first, let second, let ratio):
            return .split(
                direction: direction,
                ratio: Double(ratio),
                first: try captureTabConfigNode(
                    first,
                    tabID: tabID,
                    splitManager: splitManager,
                    leafViews: leafViews,
                    leafIndex: &leafIndex,
                    projectDirectory: projectDirectory
                ),
                second: try captureTabConfigNode(
                    second,
                    tabID: tabID,
                    splitManager: splitManager,
                    leafViews: leafViews,
                    leafIndex: &leafIndex,
                    projectDirectory: projectDirectory
                )
            )
        }
    }

    private func captureTabConfigPane(
        contentID: UUID,
        view: NSView,
        tabID: TabID,
        splitManager: SplitManager,
        projectDirectory: URL
    ) throws -> TabConfigPane {
        let resolver = TabConfigLayoutRuntimeResolver()
        let panelInfo = splitManager.panelInfo(for: contentID)
        let title = splitManager.panelTitle(for: contentID)

        if panelInfo.type == .terminal {
            guard let hostView = view as? TerminalHostView,
                  let surfaceID = tabConfigSurfaceID(for: hostView, tabID: tabID),
                  let directory = workingDirectory(for: surfaceID)
                    ?? tabManager.tab(for: tabID)?.workingDirectory else {
                throw TabConfigLayoutRuntimeError.inconsistentLayout("terminal surface is not tracked")
            }
            return TabConfigPane(
                workingDirectory: try resolver.projectRelativePath(
                    for: directory,
                    projectDirectory: projectDirectory,
                    expectedDirectory: true
                ),
                title: title
            )
        }

        guard panelInfo.type != .subagent,
              panelContentViews[contentID] === view else {
            throw TabConfigLayoutRuntimeError.inconsistentLayout("pane cannot be reused")
        }

        let filePath: String?
        if let fileURL = panelInfo.filePath {
            filePath = try resolver.projectRelativePath(
                for: fileURL,
                projectDirectory: projectDirectory,
                expectedDirectory: Self.tabConfigPanelUsesDirectory(panelInfo.type)
            )
        } else {
            filePath = nil
        }

        let initialURL: URL?
        if panelInfo.type == .browser,
           let browserViewModel = browserViewModel(containedIn: view) {
            initialURL = browserViewModel.currentURL
                ?? URL(string: browserViewModel.urlString)
                ?? panelInfo.initialURL
        } else {
            initialURL = panelInfo.initialURL
        }

        return TabConfigPane(
            type: panelInfo.type,
            filePath: filePath,
            initialURL: initialURL,
            title: title
        )
    }

    private func materializeTabConfigNode(
        _ layout: ResolvedTabConfigLayout,
        tabID: TabID,
        primarySurfaceID: SurfaceID,
        primaryView: TerminalHostView,
        didUsePrimaryTerminal: inout Bool,
        viewsByContentID: inout [UUID: NSView],
        panelTypes: inout [UUID: PanelInfo],
        panelTitles: inout [UUID: String]
    ) throws -> SplitNode {
        switch layout {
        case .pane(let pane):
            let contentID: UUID
            let view: NSView
            let panelInfo = PanelInfo(
                type: pane.type,
                initialURL: pane.initialURL,
                filePath: pane.fileURL
            )

            if !didUsePrimaryTerminal {
                guard pane.type == .terminal else {
                    throw TabConfigLayoutRuntimeError.inconsistentLayout("first pane is not a terminal")
                }
                didUsePrimaryTerminal = true
                contentID = primarySurfaceID.rawValue
                view = primaryView
            } else if pane.type == .terminal {
                let created = try createTabConfigTerminal(
                    in: tabID,
                    workingDirectory: pane.workingDirectory
                )
                contentID = created.surfaceID.rawValue
                view = created.view
            } else {
                contentID = UUID()
                guard let panelView = makeWorkspacePanelView(
                    panel: panelInfo,
                    contentID: contentID,
                    tabID: tabID
                ) else {
                    throw TabConfigLayoutRuntimeError.inconsistentLayout("pane view could not be created")
                }
                applyCurrentAuroraAppearance(to: panelView)
                panelContentViews[contentID] = panelView
                panelTypes[contentID] = panelInfo
                view = panelView
            }

            viewsByContentID[contentID] = view
            if let title = pane.title {
                panelTitles[contentID] = title
            }
            return .leaf(id: UUID(), terminalID: contentID)

        case .split(let direction, let ratio, let first, let second):
            return .clampedSplit(
                id: UUID(),
                direction: direction,
                first: try materializeTabConfigNode(
                    first,
                    tabID: tabID,
                    primarySurfaceID: primarySurfaceID,
                    primaryView: primaryView,
                    didUsePrimaryTerminal: &didUsePrimaryTerminal,
                    viewsByContentID: &viewsByContentID,
                    panelTypes: &panelTypes,
                    panelTitles: &panelTitles
                ),
                second: try materializeTabConfigNode(
                    second,
                    tabID: tabID,
                    primarySurfaceID: primarySurfaceID,
                    primaryView: primaryView,
                    didUsePrimaryTerminal: &didUsePrimaryTerminal,
                    viewsByContentID: &viewsByContentID,
                    panelTypes: &panelTypes,
                    panelTitles: &panelTitles
                ),
                ratio: CGFloat(ratio)
            )
        }
    }

    private func createTabConfigTerminal(
        in tabID: TabID,
        workingDirectory: URL?
    ) throws -> (surfaceID: SurfaceID, view: TerminalHostView) {
        guard let workingDirectory else {
            throw TabConfigLayoutRuntimeError.inconsistentLayout("terminal directory is missing")
        }
        let engine = terminalEngine(for: tabID)
        let viewModel = TerminalViewModel(engine: engine)
        let appearance = effectiveConfig(for: tabID).appearance
        viewModel.setDefaultFontSize(appearance.fontSize)
        let surfaceView = TerminalHostViewFactory.make(
            viewModel: viewModel,
            engine: engine,
            localizer: appLocalizer()
        )
        surfaceView.applyFont(family: appearance.fontFamily, size: appearance.fontSize)

        let surfaceID = try engine.createSurface(
            in: surfaceView,
            workingDirectory: workingDirectory,
            command: nil
        )
        viewModel.markRunning(surfaceID: surfaceID)
        surfaceView.configureSurfaceIfNeeded(bridge: engine, surfaceID: surfaceID)
        surfaceView.syncSizeWithTerminal()
        splitSurfaceViews[surfaceID] = surfaceView
        splitViewModels[surfaceID] = viewModel
        registerTerminalEngine(engine, tabID: tabID, surfaceID: surfaceID)
        wireSurfaceHandlers(
            for: surfaceID,
            tabID: tabID,
            in: surfaceView,
            initialWorkingDirectory: workingDirectory
        )
        startAutomaticSessionReplayIfNeeded(surfaceID: surfaceID, tabID: tabID)
        applyTerminalFont(
            family: appearance.fontFamily,
            size: appearance.fontSize,
            to: surfaceID
        )
        return (surfaceID, surfaceView)
    }

    private func tabConfigSurfaceID(
        for hostView: TerminalHostView,
        tabID: TabID
    ) -> SurfaceID? {
        if tabSurfaceViews[tabID] === hostView {
            return tabSurfaceMap[tabID]
        }
        return splitSurfaceViews.first(where: { $0.value === hostView })?.key
    }

    private static func tabConfigPanelUsesDirectory(_ type: PanelType) -> Bool {
        switch type {
        case .aiEditHistory, .templates, .macros, .dbCloud, .projectHome:
            return true
        default:
            return false
        }
    }

    func tabConfigAuthorizationWorkingDirectory(for tabID: TabID) -> URL? {
        if let primarySurfaceID = tabSurfaceMap[tabID],
           let surfaceDirectory = workingDirectory(for: primarySurfaceID) {
            return surfaceDirectory
        }
        return tabManager.tab(for: tabID)?.workingDirectory
    }
}
