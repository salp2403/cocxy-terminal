// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GlassSurfaceCoverageSwiftTestingTests.swift - Source-level coverage for plan panels.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Glass surface coverage")
struct GlassSurfaceCoverageSwiftTestingTests {
    @Test("plan surfaces use the shared glass primitive")
    func planSurfacesUseSharedGlassPrimitive() throws {
        for relativePath in Self.planSurfacePaths {
            let contents = try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath))
            #expect(
                contents.contains(".glassPanelBackground()")
                    || contents.contains("Design.GlassSurface"),
                "\(relativePath) should use the shared glass primitive"
            )
        }
    }

    @Test("UI sources no longer use old direct full-panel backgrounds")
    func uiSourcesDoNotUseDirectFullPanelBackgrounds() throws {
        let root = repositoryRoot().appendingPathComponent("Sources/UI", isDirectory: true)
        let swiftFiles = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []

        for file in swiftFiles where file.pathExtension == "swift" {
            let contents = try String(contentsOf: file)
            for marker in Self.legacyFullPanelBackgroundMarkers {
                #expect(
                    !contents.contains(marker),
                    "\(file.path) still uses legacy full-panel background marker \(marker)"
                )
            }
        }
    }

    private static let planSurfacePaths = [
        "Sources/UI/Activity/ActivityDashboardView.swift",
        "Sources/UI/Agent/AgentPanelView.swift",
        "Sources/UI/AIEditHistory/AIEditHistoryPanelView.swift",
        "Sources/UI/CodeReview/CodeReviewPanelView.swift",
        "Sources/UI/CodeReview/FileListView.swift",
        "Sources/UI/CodeReview/ReviewToolbarView.swift",
        "Sources/UI/DBCloudHelpers/DBCloudHelperPanelView.swift",
        "Sources/UI/GitHub/GitHubPaneView.swift",
        "Sources/UI/Macros/MacroSnippetPanelView.swift",
        "Sources/UI/Notebook/NotebookPanelView.swift",
        "Sources/UI/Onboarding/OnboardingFlowView.swift",
        "Sources/UI/PluginMarketplace/PluginMarketplaceView.swift",
        "Sources/UI/RemoteWorkspace/RemoteConnectionView.swift",
        "Sources/UI/RemoteWorkspace/RemoteProfileEditor.swift",
        "Sources/UI/RemoteWorkspace/SSHKeyManagerView.swift",
        "Sources/UI/SessionReplay/SessionReplayPanelView.swift",
        "Sources/UI/SmartRouting/SmartRoutingOverlayView.swift",
        "Sources/UI/Templates/ProjectTemplatePanelView.swift",
        "Sources/UI/Terminal/AgentProgressOverlay.swift",
        "Sources/UI/Welcome/WelcomeOverlayView.swift",
        "Sources/UI/Workflow/WorkflowPanelView.swift",
    ]

    private static let legacyFullPanelBackgroundMarkers = [
        ".background(Color(nsColor: CocxyColors.base))",
        ".background(Color(nsColor: CocxyColors.mantle))",
        ".background(.thickMaterial)",
        ".background(.ultraThinMaterial)",
    ]

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
