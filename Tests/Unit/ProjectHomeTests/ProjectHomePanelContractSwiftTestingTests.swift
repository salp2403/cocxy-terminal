// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectHomePanelContractSwiftTestingTests.swift - Persisted project home panel contract coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Project home panel contract")
@MainActor
struct ProjectHomePanelContractSwiftTestingTests {
    @Test("project home metadata uses the existing file path field and round-trips")
    func metadataUsesExistingFilePathAndRoundTrips() throws {
        let projectRoot = URL(fileURLWithPath: "/tmp/cocxy-project-home", isDirectory: true)
        let panelInfo = PanelInfo.projectHome(projectRoot: projectRoot)

        #expect(PanelType.projectHome.rawValue == "project-home")
        #expect(panelInfo.type == .projectHome)
        #expect(panelInfo.filePath == projectRoot)
        #expect(panelInfo.initialURL == nil)
        #expect(panelInfo.subagentId == nil)
        #expect(panelInfo.sessionId == nil)

        let data = try JSONEncoder().encode(panelInfo)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(PanelInfo.self, from: data)
        #expect(payload["type"] as? String == "project-home")
        #expect(payload["filePath"] != nil)
        #expect(payload["projectRoot"] == nil)
        #expect(decoded == panelInfo)
    }

    @Test("legacy panel metadata decodes without project-specific fields")
    func legacyMetadataDecodesWithoutProjectSpecificFields() throws {
        let data = Data(#"{"type":"terminal"}"#.utf8)

        let decoded = try JSONDecoder().decode(PanelInfo.self, from: data)

        #expect(decoded == .terminal)
    }

    @Test("session restoration preserves project root and panel title")
    func sessionRestorationPreservesProjectMetadata() throws {
        let projectRoot = URL(fileURLWithPath: "/tmp/cocxy-project-home", isDirectory: true)
        let tab = TabState(
            id: TabID(),
            title: "Project",
            workingDirectory: projectRoot,
            splitTree: .leaf(workingDirectory: projectRoot, command: nil),
            paneStates: [
                SplitPaneState(
                    panelInfo: .projectHome(projectRoot: projectRoot),
                    title: "Project Home"
                )
            ]
        )
        let persisted = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(TabState.self, from: persisted)
        let window = WindowState(
            frame: CodableRect(x: 100, y: 100, width: 1_000, height: 700),
            isFullScreen: false,
            tabs: [decoded],
            activeTabIndex: 0
        )

        let restored = SessionRestorer.restoreWindow(
            from: window,
            screenBounds: CodableRect(x: 0, y: 0, width: 1_920, height: 1_080)
        )
        let pane = restored.restoredTabs.first?.paneStates.first

        #expect(pane?.panelInfo.type == .projectHome)
        #expect(pane?.panelInfo.filePath == projectRoot)
        #expect(pane?.title == "Project Home")
    }

    @Test("project home labels and symbol use their source fallbacks")
    func labelsAndSymbolUseSourceFallbacks() throws {
        let localizer = AppLocalizer(
            languagePreference: .english,
            bundle: try #require(localizationBundle())
        )
        let tab = PanelTabInfo(
            leafID: UUID(),
            contentID: UUID(),
            panelType: .projectHome,
            title: "Project Home",
            isFocused: true
        )

        #expect(MainWindowController.localizedPanelTitle(.projectHome, using: localizer) == "Project Home")
        #expect(
            WorkspaceToolbarController.localizedPanelTitle(
                for: .projectHome,
                index: 4,
                using: localizer
            ) == "Project Home"
        )
        #expect(tab.symbolName == "house")

        let closeCopy = MainWindowController.localizedFocusedPaneCloseCopy(
            localizer: localizer,
            paneType: .projectHome,
            remainingPaneCount: 1
        )
        #expect(closeCopy.informativeText.contains("project home panel"))
    }

    private func localizationBundle() -> Bundle? {
        Bundle(url: repositoryRoot().appendingPathComponent("Resources/Localization", isDirectory: true))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
