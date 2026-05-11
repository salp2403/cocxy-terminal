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

        let tabKey = config.preserveDraftsPerTab ? tabID.map(Self.richInputDraftTabKey(_:)) : nil
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
        let frame = richInputFrame(in: overlayContainer.bounds)
        let richInputView = RichInputComposerView(
            viewModel: viewModel,
            onSubmit: { [weak self, weak surfaceView, weak viewModel] in
                guard let self, let surfaceView, let viewModel else { return }
                let payload = viewModel.terminalPayload()
                self.dismissRichInputComposer()
                if let tabKey {
                    self.richInputDraftStore.delete(tabID: tabKey)
                }
                guard !payload.isEmpty else { return }
                surfaceView.submitRichInputPayload(payload)
            },
            onCancel: cancelHandler,
            localizer: localizer,
            panelWidth: frame.width
        )

        let hostingView = FocusableHostingView(rootView: richInputView)
        hostingView.onCancelOperation = cancelHandler
        hostingView.wantsLayer = true
        hostingView.frame = frame
        hostingView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]

        overlayContainer.addSubview(hostingView)
        richInputViewModel = viewModel
        richInputHostingView = hostingView
        richInputCancelHandler = cancelHandler
        window?.makeFirstResponder(hostingView)
        return true
    }

    func cancelRichInputComposer() {
        richInputCancelHandler?()
    }

    func dismissRichInputComposer() {
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

    static func richInputDraftTabKey(_ tabID: TabID) -> String {
        tabID.rawValue.uuidString.lowercased()
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
}
