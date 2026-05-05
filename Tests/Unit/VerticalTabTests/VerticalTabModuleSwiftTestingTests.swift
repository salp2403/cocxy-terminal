// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VerticalTabModuleSwiftTestingTests.swift - Focused contracts for Aurora vertical tab modules.

import CoreGraphics
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Vertical tab modules")
struct VerticalTabModuleSwiftTestingTests {

    @Test("drag payload parser round-trips session and pane payloads")
    func dragPayloadParserRoundTripsKnownPayloads() {
        let session = Design.VerticalTabDragPayload.session("tab-1")
        let pane = Design.VerticalTabDragPayload.pane("pane-2")

        #expect(session.encodedValue == "session:tab-1")
        #expect(pane.encodedValue == "pane:pane-2")
        #expect(Design.VerticalTabDragPayload(encodedValue: session.encodedValue) == session)
        #expect(Design.VerticalTabDragPayload(encodedValue: pane.encodedValue) == pane)
        #expect(Design.VerticalTabDragPayload(encodedValue: "session:") == nil)
        #expect(Design.VerticalTabDragPayload(encodedValue: "unknown:tab-1") == nil)
    }

    @Test("drag handler routes session reorders and pane transfers without accepting self drops")
    func dragHandlerRoutesPayloads() {
        var reordered: [String] = []
        var transferred: [String] = []
        let handler = Design.VerticalTabDragHandler(
            currentSessionID: "target",
            onMoveSessionBefore: { reordered.append($0) },
            onMovePaneToSession: { transferred.append($0) }
        )

        #expect(handler.handle(.session("source")) == true)
        #expect(handler.handle(.pane("pane-id")) == true)
        #expect(handler.handle(.session("target")) == false)
        #expect(reordered == ["source"])
        #expect(transferred == ["pane-id"])
    }

    @Test("control bar labels expose density and primary info options")
    func controlBarLabelsExposeExpectedOptions() {
        #expect(AuroraSidebarDisplayMode.detailed.verticalTabShortLabel == "D")
        #expect(AuroraSidebarDisplayMode.summary.verticalTabShortLabel == "S")
        #expect(AuroraSidebarDisplayMode.compact.verticalTabShortLabel == "C")
        #expect(AuroraSidebarPrimaryInfo.state.verticalTabShortLabel == "State")
        #expect(AuroraSidebarPrimaryInfo.directory.verticalTabMenuLabel == "Directory")
        #expect(AuroraSidebarPrimaryInfo.command.verticalTabSystemImage == "terminal")
    }

    @Test("compact mode traits hide dense row affordances but preserve tight vertical spacing")
    func compactModeTraitsHideDenseAffordances() {
        let compact = Design.VerticalTabCompactMode(mode: .compact)
        let summary = Design.VerticalTabCompactMode(mode: .summary)

        #expect(compact.rowSpacing == 0)
        #expect(compact.showsPrimaryMetadata == false)
        #expect(compact.showsPaneMatrix == false)
        #expect(compact.showsCloseButton == false)
        #expect(summary.showsPrimaryMetadata == true)
        #expect(summary.showsPaneMatrix == true)
        #expect(summary.verticalPadding > compact.verticalPadding)
    }

    @Test("summary mode uses the selected primary info with state fallback")
    func summaryModeUsesSelectedPrimaryInfo() {
        let session = Design.AuroraSession(
            id: "s",
            name: "editor",
            agent: .shell,
            state: .waiting,
            panes: [
                Design.AuroraPane(id: "p", name: "zsh", agent: .shell, state: .waiting),
            ],
            workingDirectory: "/tmp/project",
            foregroundProcessName: "vim"
        )

        let directory = Design.VerticalTabSummaryMode(session: session, primaryInfo: .directory)
        let command = Design.VerticalTabSummaryMode(session: session, primaryInfo: .command)

        #expect(directory.metadataLine == "/tmp/project")
        #expect(command.metadataLine == "waiting · 1 pane")
        #expect(command.state == .waiting)
    }

    @Test("summary mode localizes state fallback metadata for visible sidebar rows")
    func summaryModeLocalizesStateFallbackMetadata() throws {
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: try localizationBundle())
        let session = Design.AuroraSession(
            id: "s-localized",
            name: "shell",
            agent: .shell,
            state: .idle,
            panes: [
                Design.AuroraPane(id: "p1", name: "zsh", agent: .shell, state: .idle),
                Design.AuroraPane(id: "p2", name: "logs", agent: .shell, state: .idle),
            ]
        )

        let summary = Design.VerticalTabSummaryMode(
            session: session,
            primaryInfo: .command,
            localizer: spanish
        )

        #expect(summary.metadataLine == "inactivo · 2 paneles")
        #expect(summary.state == Design.AgentStateRole.idle)
    }

    @Test("hover sidecar placement stays outside the sidebar and inside the overlay")
    func hoverSidecarPlacementStaysInBounds() {
        let tooltip = Design.AuroraSidebarTooltipSnapshot(
            session: Design.AuroraSession(
                id: "s",
                name: "build",
                agent: .claude,
                state: .working,
                panes: [
                    Design.AuroraPane(id: "p", name: "Claude", agent: .claude, state: .working),
                ]
            ),
            workspaceName: "cocxy",
            workspaceBranch: "main",
            rowFrame: CGRect(x: 0, y: 42, width: 220, height: 28)
        )

        let placement = Design.VerticalTabHoverSidecarPlacement.placement(
            for: tooltip,
            sidebarFrame: CGRect(x: 0, y: 0, width: 240, height: 620),
            containerSize: CGSize(width: 920, height: 620)
        )

        #expect(placement.width >= 260)
        #expect(placement.width <= 360)
        #expect(placement.x > 240)
        #expect(placement.x + placement.width * 0.5 <= 908)
        #expect(placement.y >= 170)
        #expect(placement.y <= 450)
    }

    private func localizationBundle() throws -> Bundle {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return try #require(Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true)))
    }
}
