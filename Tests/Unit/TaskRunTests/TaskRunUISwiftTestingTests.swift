// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import SwiftUI
import Testing
@testable import CocxyTerminal

@Suite("TaskRun UI")
@MainActor
struct TaskRunUISwiftTestingTests {
    @Test("embedded launch surface constructs with project-bound actions")
    func embeddedLaunchConstructs() {
        let model = ProjectFanOutFlowViewModel(
            projectID: ProjectID(rawValue: "/tmp/repo"),
            projectRoot: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
            availableBaseRefs: ["HEAD"],
            defaultBaseRef: "HEAD",
            defaultAgentNames: ["codex"],
            actions: ProjectFanOutActions(
                launch: { _ in throw TaskRunExecutionError.targetUnavailable },
                loadSnapshot: { _ in throw TaskRunError.runNotFound("missing") },
                launchCollisions: { _, _ in
                    TaskLaunchCollisionAnalysis(inferredPaths: [], report: .empty)
                },
                preparePromotion: { _, _ in throw TaskRunError.runNotFound("missing") },
                executePromotion: { _ in throw TaskRunError.runNotFound("missing") },
                recycle: { _, _ in throw TaskRunError.runNotFound("missing") },
                cancel: { _ in throw TaskRunError.runNotFound("missing") },
                forget: { _ in throw TaskRunError.runNotFound("missing") }
            )
        )
        model.showLaunch()

        _ = ProjectFanOutFlowView(
            viewModel: model,
            localizer: AppLocalizer(languagePreference: .english)
        ).body

        var mode = DiffViewerMode.unified
        _ = DiffViewerView(
            diffs: [],
            mode: Binding(get: { mode }, set: { mode = $0 }),
            onStage: { _, _, _ in },
            showsStagingControls: false
        ).body
    }

    @Test("both palette presentations discover parallel task actions")
    func paletteActionsAreDiscoverable() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let engine = controller.createWiredCommandPaletteEngine()
        let actionIDs = Set(engine.allActions.map(\.id))

        #expect(actionIDs.contains("taskRun.fanOut"))
        #expect(actionIDs.contains("taskRun.compare"))
        #expect(actionIDs.contains("navigation.jumpProject"))

        let auroraIDs = Set(controller.buildAuroraPaletteActions().map(\.id))
        #expect(auroraIDs.contains("taskRun.fanOut"))
        #expect(auroraIDs.contains("taskRun.compare"))
        #expect(auroraIDs.contains("navigation.jumpProject"))
    }
}
