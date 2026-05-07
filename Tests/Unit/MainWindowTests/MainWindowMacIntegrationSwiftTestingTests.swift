// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Main window macOS integrations")
struct MainWindowMacIntegrationSwiftTestingTests {

    @Test("main window opts into Stage Manager friendly grouping and tiling")
    func mainWindowUsesStageManagerFriendlyBehaviors() throws {
        let controller = MainWindowController(bridge: MockTerminalEngine(), deferContentSetup: true)
        let window = try #require(controller.window)
        let behavior = window.collectionBehavior

        #expect(behavior.contains(.primary))
        #expect(behavior.contains(.managed))
        #expect(behavior.contains(.participatesInCycle))
        #expect(behavior.contains(.fullScreenPrimary))
        #expect(behavior.contains(.fullScreenAllowsTiling))
        #expect(window.tabbingMode == .preferred)
    }

    @Test("touch bar exposes contextual local terminal actions")
    func touchBarExposesContextualTerminalActions() throws {
        let controller = MainWindowController(bridge: MockTerminalEngine(), deferContentSetup: true)
        let touchBar = try #require(controller.makeTouchBar())

        #expect(touchBar.customizationIdentifier == CocxyTouchBarController.customizationIdentifier)
        #expect(touchBar.defaultItemIdentifiers == CocxyTouchBarController.defaultItemIdentifiers)
        for identifier in CocxyTouchBarController.defaultItemIdentifiers {
            #expect(touchBar.delegate?.touchBar?(touchBar, makeItemForIdentifier: identifier) != nil)
        }
    }

    @Test("touch bar buttons dispatch their configured local actions")
    func touchBarButtonsDispatchLocalActions() throws {
        var dispatchedActions: [String] = []
        let controller = CocxyTouchBarController(
            newTab: { dispatchedActions.append("new-tab") },
            commandPalette: { dispatchedActions.append("commands") },
            agentPanel: { dispatchedActions.append("agent") },
            search: { dispatchedActions.append("search") }
        )
        let touchBar = controller.makeTouchBar()

        let expectations: [(NSTouchBarItem.Identifier, String)] = [
            (CocxyTouchBarController.newTabIdentifier, "new-tab"),
            (CocxyTouchBarController.commandPaletteIdentifier, "commands"),
            (CocxyTouchBarController.agentPanelIdentifier, "agent"),
            (CocxyTouchBarController.searchIdentifier, "search")
        ]

        for (identifier, action) in expectations {
            let item = try #require(
                touchBar.delegate?.touchBar?(touchBar, makeItemForIdentifier: identifier) as? NSCustomTouchBarItem
            )
            let button = try #require(item.view as? NSButton)

            button.performClick(nil)
            #expect(dispatchedActions.last == action)
        }

        #expect(dispatchedActions == expectations.map(\.1))
    }

    @Test("app Info.plist opts into Continuity Camera device discovery with local privacy copy")
    func appInfoPlistOptsIntoContinuityCamera() throws {
        let plistURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        #expect(plist["NSCameraUseContinuityCameraDeviceType"] as? Bool == true)
        #expect(plist["CFBundleDevelopmentRegion"] as? String == "en")
        #expect(
            (plist["NSCameraUsageDescription"] as? String)?
                .contains("Continuity Camera") == true
        )
    }

    @Test("window imports Continuity Camera pasteboard images into local Agent attachments")
    func windowImportsContinuityCameraPasteboardImagesIntoAgentAttachments() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = MainWindowController(bridge: MockTerminalEngine())
        let viewModel = AgentPanelViewModel(
            configuration: AgentModeConfig(enabled: true, preferredProvider: .openai),
            runner: RecordingMacIntegrationAgentPromptRunner(),
            attachmentStorage: AgentAttachmentStorage(rootDirectory: root)
        )
        controller.agentPanelViewModel = viewModel
        let contentView = try #require(controller.window?.contentView)

        #expect(
            contentView.validRequestor(forSendType: nil, returnType: .png) != nil,
            "The root content view must participate in the AppKit import-from-device responder chain"
        )
        #expect(contentView.validRequestor(forSendType: nil, returnType: nil) == nil)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("cocxy-continuity-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(Self.pngData, forType: .png)

        let responderView = try #require(contentView as? ContinuityCameraImportResponderView)
        #expect(responderView.readSelectionFromPasteboard(pasteboard))
        let attachment = try #require(viewModel.imageAttachments.first)
        #expect(viewModel.imageAttachments.count == 1)
        #expect(attachment.displayName == "continuity-camera.png")
        #expect(FileManager.default.fileExists(atPath: attachment.filePath))
        let attributes = try FileManager.default.attributesOfItem(atPath: attachment.filePath)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-mac-integration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
    )!
}

private actor RecordingMacIntegrationAgentPromptRunner: AgentPromptRunning {
    func run(
        prompt: String,
        history: [AgentMessage],
        configuration: AgentModeConfig
    ) async throws -> AgentLoopResult {
        AgentLoopResult(messages: [], stopReason: .completed)
    }
}
