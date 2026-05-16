// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GlassSurfaceCoverageSwiftTestingTests.swift - Source-level coverage for plan panels.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Glass surface coverage")
struct GlassSurfaceCoverageSwiftTestingTests {
    @Test("plan surfaces use the shared glass primitive")
    func planSurfacesUseSharedGlassPrimitive() throws {
        #expect(Self.planSurfacePaths.count >= 24)

        for relativePath in Self.planSurfacePaths {
            let contents = try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath))
            #expect(
                contents.contains(".glassPanelBackground(")
                    || contents.contains("Design.PanelGlassBackground(")
                    || contents.contains("Design.GlassSurface(")
                    || contents.contains("GlassSurface("),
                "\(relativePath) should use the shared glass primitive"
            )
        }
    }

    @Test("AppKit plan surfaces use the shared glass backing")
    func appKitPlanSurfacesUseSharedGlassBacking() throws {
        for relativePath in Self.appKitPlanSurfacePaths {
            let contents = try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath))
            #expect(
                contents.contains("installAppKitGlassPanelBackground("),
                "\(relativePath) should use the shared AppKit glass backing"
            )
        }
    }

    @Test("panel-like UI surfaces are covered or explicitly scoped out")
    func panelLikeUISurfacesHaveExplicitGlassDecision() throws {
        let discovered = try discoveredPanelCandidatePaths()
        let covered = Set(Self.planSurfacePaths)
            .union(Self.appKitPlanSurfacePaths)
            .union(Self.scopedNonGlassSurfacePaths.keys)
        let uncovered = discovered.subtracting(covered).sorted()

        #expect(
            uncovered.isEmpty,
            Comment(rawValue: "Panel-like UI surfaces need glass coverage or a scoped non-glass rationale: \(uncovered.joined(separator: ", "))")
        )
        #expect(Self.scopedNonGlassSurfacePaths.values.allSatisfy { !$0.isEmpty })
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
        "Sources/UI/Browser/BrowserBookmarksView.swift",
        "Sources/UI/Browser/BrowserDevToolsView.swift",
        "Sources/UI/Browser/BrowserDownloadsView.swift",
        "Sources/UI/Browser/BrowserHistoryView.swift",
        "Sources/UI/Browser/BrowserPanelView.swift",
        "Sources/UI/CodeReview/CodeReviewPanelView.swift",
        "Sources/UI/CodeReview/CodeReviewAgentActivityView.swift",
        "Sources/UI/CodeReview/CodeReviewGitWorkflowPanel.swift",
        "Sources/UI/CodeReview/FileListView.swift",
        "Sources/UI/CodeReview/ReviewToolbarView.swift",
        "Sources/UI/CommandPalette/CommandPaletteView.swift",
        "Sources/UI/DBCloudHelpers/DBCloudHelperPanelView.swift",
        "Sources/UI/Design/AuroraCommandPaletteView.swift",
        "Sources/UI/Design/AuroraSidebarView.swift",
        "Sources/UI/Design/AuroraStatusBarView.swift",
        "Sources/UI/Design/AuroraTweaksPanel.swift",
        "Sources/UI/Dashboard/DashboardPanelView.swift",
        "Sources/UI/GitHub/GitHubPaneView.swift",
        "Sources/UI/Macros/MacroSnippetPanelView.swift",
        "Sources/UI/Notes/NotesOverlayView.swift",
        "Sources/UI/Notebook/NotebookPanelView.swift",
        "Sources/UI/NotificationPanel/NotificationPanelView.swift",
        "Sources/UI/Onboarding/OnboardingFlowView.swift",
        "Sources/UI/PluginMarketplace/PluginMarketplaceView.swift",
        "Sources/UI/Preferences/PreferencesView.swift",
        "Sources/UI/RemoteWorkspace/RemoteConnectionView.swift",
        "Sources/UI/RemoteWorkspace/RemoteProfileEditor.swift",
        "Sources/UI/RemoteWorkspace/SSHKeyManagerView.swift",
        "Sources/UI/SessionReplay/SessionReplayPanelView.swift",
        "Sources/UI/SmartRouting/SmartRoutingOverlayView.swift",
        "Sources/UI/StatusBar/StatusBarView.swift",
        "Sources/UI/Subagent/SubagentPanelView.swift",
        "Sources/UI/Templates/ProjectTemplatePanelView.swift",
        "Sources/UI/Terminal/AgentProgressOverlay.swift",
        "Sources/UI/Timeline/TimelineView.swift",
        "Sources/UI/Vault/VaultSidebarView.swift",
        "Sources/UI/Welcome/WelcomeOverlayView.swift",
        "Sources/UI/Worktree/WorktreeAdvancedModal.swift",
        "Sources/UI/Worktree/WorktreeBatchCleanupSheet.swift",
        "Sources/UI/Workflow/WorkflowPanelView.swift",
    ]

    private static let appKitPlanSurfacePaths = [
        "Sources/UI/Markdown/MarkdownContentView.swift",
    ]

    private static let scopedNonGlassSurfacePaths = [
        "Sources/UI/Markdown/MarkdownSidebarView.swift":
            "Child AppKit sidebar inside MarkdownContentView; parent installs the shared glass backing.",
        "Sources/UI/Markdown/MarkdownStatusBarView.swift":
            "Child AppKit status strip inside MarkdownContentView; parent installs the shared glass backing.",
        "Sources/UI/QuickTerminal/QuickTerminalPanel.swift":
            "NSPanel shell owns terminal contrast/performance background outside the SwiftUI glass primitive.",
        "Sources/UI/RichInput/RichInputPanel.swift":
            "NSPanel shell owns its translucent backgroundColor outside the SwiftUI glass primitive; the hosted RichInputComposerView renders the composer chrome.",
        "Sources/UI/Terminal/Block/TerminalBlockOverlayView.swift":
            "Transparent AppKit overlay drawn on top of terminal cells; per-row rails/buttons are not standalone panels.",
        "Sources/UI/UXPolish/ShortcutHintsOverlayView.swift":
            "Non-interactive shortcut-hint overlay that draws per-chip thin material pills; it is decorative (allowsHitTesting=false, accessibilityHidden) rather than a standalone panel surface.",
    ]

    private static let legacyFullPanelBackgroundMarkers = [
        ".background(Color(nsColor: CocxyColors.base))",
        ".background(Color(nsColor: CocxyColors.mantle))",
        ".background(.thickMaterial)",
        ".background(.ultraThinMaterial)",
        ".background(Color(nsColor: CocxyColors.mantle).opacity(0.98))",
        ".background(Color(nsColor: CocxyColors.surface0).opacity(0.9))",
        "Color(nsColor: CocxyColors.mantle)\n                VisualEffectBackground(",
    ]

    private static let panelCandidateNameMarkers = [
        "DashboardView",
        "OverlayView",
        "PaletteView",
        "PanelView",
        "Panel",
        "PreferencesView",
        "ProjectTemplatePanelView",
        "RemoteConnectionView",
        "RemoteProfileEditor",
        "SidebarView",
        "SSHKeyManagerView",
        "StatusBarView",
        "TimelineView",
        "WelcomeOverlayView",
    ]

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func discoveredPanelCandidatePaths() throws -> Set<String> {
        let root = repositoryRoot()
        let uiRoot = root.appendingPathComponent("Sources/UI", isDirectory: true)
        let urls = FileManager.default.enumerator(
            at: uiRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []

        var paths = Set<String>()
        for url in urls where url.pathExtension == "swift" {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let fileName = url.lastPathComponent
            if fileName.hasSuffix("ViewModel.swift")
                || fileName.hasSuffix("Background.swift")
                || fileName.hasSuffix("BackgroundView.swift")
                || fileName.hasSuffix("Button.swift") {
                continue
            }
            guard Self.panelCandidateNameMarkers.contains(where: { fileName.contains($0) }) else {
                continue
            }
            paths.insert(relativePath(for: url, from: root))
        }
        return paths
    }

    private func relativePath(for fileURL: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return filePath
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }
}
