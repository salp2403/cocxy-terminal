// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+RichInput.swift - Terminal rich input overlay lifecycle.

import AppKit
import SwiftUI

@MainActor
extension MainWindowController {
    func presentRichInputComposer(
        _ request: TerminalRichInputRequest,
        for surfaceView: CocxyCoreView,
        tabID: TabID? = nil
    ) -> Bool {
        guard let overlayContainer = overlayContainerView else { return false }

        dismissRichInputComposer()

        let tabKey = tabID.map(Self.richInputDraftTabKey(_:))
        let restoredDraft = tabKey.flatMap { try? richInputDraftStore.load(tabID: $0) }
        let viewModel: RichInputComposerViewModel
        if let restoredDraft {
            viewModel = RichInputComposerViewModel(draft: restoredDraft)
        } else {
            viewModel = RichInputComposerViewModel(text: request.text)
        }
        if !request.text.isEmpty {
            viewModel.text = request.text
        }
        viewModel.attachFiles(request.fileURLs)

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
            onCancel: { [weak self, weak viewModel] in
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
            },
            localizer: localizer,
            panelWidth: frame.width
        )

        let hostingView = NSHostingView(rootView: richInputView)
        hostingView.wantsLayer = true
        hostingView.frame = frame
        hostingView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]

        overlayContainer.addSubview(hostingView)
        richInputViewModel = viewModel
        richInputHostingView = hostingView
        window?.makeFirstResponder(hostingView)
        return true
    }

    func dismissRichInputComposer() {
        richInputHostingView?.removeFromSuperview()
        richInputHostingView = nil
        richInputViewModel = nil
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
