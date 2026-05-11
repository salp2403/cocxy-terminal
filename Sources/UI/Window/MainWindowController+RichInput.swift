// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+RichInput.swift - Terminal rich input overlay lifecycle.

import AppKit
import SwiftUI

@MainActor
extension MainWindowController {
    @discardableResult
    func toggleRichInputComposer() -> Bool {
        if richInputHostingView != nil {
            cancelRichInputComposer()
            return true
        }

        return showRichInputComposer()
    }

    @discardableResult
    func showRichInputComposer(tabID: TabID? = nil) -> Bool {
        let wasVisible = richInputHostingView != nil
        if let tabID {
            guard focusTab(id: tabID) else { return false }
            if wasVisible {
                dismissRichInputComposer()
            }
        }
        if richInputHostingView != nil {
            return true
        }
        guard (configService?.current.richInput.enabled ?? RichInputConfig.defaults.enabled),
              let surfaceView = activeTerminalSurfaceView as? CocxyCoreView else {
            return false
        }

        return presentRichInputComposer(
            TerminalRichInputRequest(text: ""),
            for: surfaceView,
            tabID: surfaceView.terminalViewModel?.surfaceID.flatMap(tabID(for:))
        )
    }

    @objc func toggleRichInputComposerAction(_ sender: Any?) {
        _ = toggleRichInputComposer()
    }

    func presentRichInputComposer(
        _ request: TerminalRichInputRequest,
        for surfaceView: CocxyCoreView,
        tabID: TabID? = nil
    ) -> Bool {
        guard let overlayContainer = overlayContainerView else { return false }
        let config = configService?.current.richInput ?? .defaults
        guard config.enabled else { return false }

        dismissRichInputComposer()

        let contentFrame = richInputFrame(in: overlayContainer.bounds)
        let tabKey = config.preserveDraftsPerTab ? richInputDraftKey(for: tabID) : nil
        let restoredDraft = tabKey.flatMap { try? richInputDraftStore.load(tabID: $0) }
        let attachmentStore = RichInputAttachmentStore(
            ttlDays: config.attachmentsCacheTTLDays,
            maxSizeBytes: config.attachmentsMaxSizeMB * 1024 * 1024
        )
        let viewModel: RichInputComposerViewModel
        if let restoredDraft {
            viewModel = RichInputComposerViewModel(
                draft: restoredDraft,
                attachmentStore: attachmentStore
            )
        } else {
            viewModel = RichInputComposerViewModel(
                text: request.text,
                attachmentStore: attachmentStore
            )
        }
        if !request.text.isEmpty {
            viewModel.text = request.text
        }
        viewModel.attachFiles(request.fileURLs)

        let cancelHandler: () -> Void = { [weak self, weak viewModel] in
            guard let self else { return }
            if let tabKey, let viewModel {
                let draft = viewModel.draft(tabID: tabKey, previous: restoredDraft)
                if draft.isEmpty {
                    self.richInputDraftStore.delete(tabID: tabKey)
                } else {
                    try? self.richInputDraftStore.save(draft)
                }
            }
            self.dismissRichInputComposer()
        }

        let localizer = appLocalizer()
        let richInputView = RichInputComposerView(
            viewModel: viewModel,
            onSubmit: { [weak self, weak surfaceView, weak viewModel] in
                guard let self, let surfaceView, let viewModel else { return }
                let payload = viewModel.terminalPayload(
                    imageTransportMode: self.richInputImageTransportMode(for: surfaceView)
                )
                self.dismissRichInputComposer()
                if let tabKey {
                    self.richInputDraftStore.delete(tabID: tabKey)
                }
                guard !payload.isEmpty else { return }
                if let tabID {
                    self.dispatchRichInputSubmitEvents(
                        tabID: tabID,
                        text: viewModel.text,
                        attachmentCount: viewModel.attachments.count
                    )
                }
                surfaceView.submitRichInputPayload(payload)
            },
            onCancel: cancelHandler,
            localizer: localizer,
            panelWidth: contentFrame.width
        )

        let hostingView = FocusableHostingView(rootView: richInputView)
        hostingView.onCancelOperation = cancelHandler
        hostingView.wantsLayer = true
        let panelFrame = richInputPanelFrame(
            contentFrame,
            in: overlayContainer,
            parentWindow: window
        )
        let panel = RichInputPanel(
            hostedView: hostingView,
            frame: panelFrame,
            localizer: localizer
        )
        panel.onClose = { [weak self] in
            self?.richInputCancelHandler?()
        }
        richInputViewModel = viewModel
        richInputHostingView = hostingView
        richInputPanel = panel
        richInputCancelHandler = cancelHandler
        panel.show(attachedTo: window)
        return true
    }

    private func richInputImageTransportMode(
        for surfaceView: CocxyCoreView
    ) -> RichInputImageTransportMode {
        guard let surfaceID = surfaceView.terminalViewModel?.surfaceID,
              richInputSurfaceSupportsInlineImages(surfaceID)
        else {
            return .filePaths
        }
        return .osc1337InlineFile
    }

    private func richInputSurfaceSupportsInlineImages(_ surfaceID: SurfaceID) -> Bool {
        if let agentName = injectedPerSurfaceStore?.state(for: surfaceID).detectedAgent?.name,
           Self.richInputAgentSupportsInlineImages(agentName) {
            return true
        }

        if surfaceLooksLikeActiveAgent(surfaceID) {
            return true
        }

        guard let bridge = cocxyCoreBridge(forSurface: surfaceID),
              bridge.semanticDiagnostics(for: surfaceID)?.state == CocxyCoreSemanticState.commandRunning,
              let command = bridge.semanticBlocks(for: surfaceID, limit: 8)
                .first(where: { $0.blockType == CocxyCoreSemanticBlockType.commandInput })?
                .detail,
              let agentName = AgentConfigService.agentIdentifier(
                matchingLaunchLine: command,
                compiledConfigs: Self.richInputAgentLaunchConfigs
              )
        else {
            return false
        }

        return Self.richInputAgentSupportsInlineImages(agentName)
    }

    private static let richInputAgentLaunchConfigs = AgentConfigService
        .defaultAgentConfigs()
        .map(AgentConfigService.compile)

    private static func richInputAgentSupportsInlineImages(_ agentName: String) -> Bool {
        switch agentName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "claude", "claude-code", "claude code", "codex", "gemini", "gemini-cli":
            return true
        default:
            return false
        }
    }

    func cancelRichInputComposer() {
        richInputCancelHandler?()
    }

    func dismissRichInputComposer() {
        let panel = richInputPanel
        richInputPanel = nil
        panel?.onClose = nil
        panel?.closeWithoutCallback()
        richInputHostingView?.removeFromSuperview()
        richInputHostingView = nil
        richInputViewModel = nil
        richInputCancelHandler = nil
    }

    func shouldAutoShowRichInput(for request: TerminalRichInputRequest) -> Bool {
        let config = configService?.current.richInput ?? .defaults
        guard config.enabled else { return false }
        if !request.fileURLs.isEmpty { return config.autoShowOnMultilinePaste }
        guard request.text.contains("\n") else { return false }
        return config.autoShowOnMultilinePaste
    }

    func immediateRichInputPayload(
        for request: TerminalRichInputRequest,
        surfaceView: CocxyCoreView
    ) -> RichInputTerminalPayload? {
        let config = configService?.current.richInput ?? .defaults
        guard config.enabled,
              request.fileURLs.isEmpty == false,
              let surfaceID = surfaceView.terminalViewModel?.surfaceID,
              richInputSurfaceSupportsInlineImages(surfaceID)
        else {
            return nil
        }

        let attachmentStore = RichInputAttachmentStore(
            ttlDays: config.attachmentsCacheTTLDays,
            maxSizeBytes: config.attachmentsMaxSizeMB * 1024 * 1024
        )
        let viewModel = RichInputComposerViewModel(
            text: request.text,
            attachmentStore: attachmentStore
        )
        viewModel.attachFiles(request.fileURLs)
        let payload = viewModel.terminalPayload(imageTransportMode: .osc1337InlineFile)
        return payload.isEmpty ? nil : payload
    }

    static func richInputDraftTabKey(_ tabID: TabID) -> String {
        tabID.rawValue.uuidString.lowercased()
    }

    static func richInputDraftKey(_ draftID: UUID) -> String {
        draftID.uuidString.lowercased()
    }

    private func richInputDraftKey(for tabID: TabID?) -> String? {
        guard let tabID else { return nil }
        if let draftID = tabManager.tab(for: tabID)?.richInputDraftID {
            return Self.richInputDraftKey(draftID)
        }

        let legacyKey = Self.richInputDraftTabKey(tabID)
        let draftID: UUID
        if (try? richInputDraftStore.load(tabID: legacyKey)) != nil {
            draftID = tabID.rawValue
        } else {
            draftID = UUID()
        }
        tabManager.updateTab(id: tabID) { tab in
            tab.richInputDraftID = draftID
        }
        return Self.richInputDraftKey(draftID)
    }

    private func richInputFrame(in bounds: NSRect) -> NSRect {
        let statusHeight = statusBarHostingView?.frame.height ?? 24
        let horizontalMargin: CGFloat = 20
        let width = min(620, max(320, bounds.width - horizontalMargin * 2))
        let height = min(292, max(220, bounds.height - statusHeight - 32))
        return NSRect(
            x: max(horizontalMargin, (bounds.width - width) / 2),
            y: statusHeight + 16,
            width: width,
            height: height
        )
    }

    private func richInputPanelFrame(
        _ contentFrame: NSRect,
        in overlayContainer: NSView,
        parentWindow: NSWindow?
    ) -> NSRect {
        guard let parentWindow else { return contentFrame }
        let windowFrame = overlayContainer.convert(contentFrame, to: nil)
        let screenOrigin = parentWindow.convertPoint(toScreen: windowFrame.origin)
        return NSRect(origin: screenOrigin, size: contentFrame.size)
    }
}
