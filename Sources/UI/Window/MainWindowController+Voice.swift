// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+Voice.swift - Voice input action wiring.

import AppKit
import SwiftUI

@MainActor
extension MainWindowController {
    @objc func startVoiceInputAction(_ sender: Any?) {
        guard voiceTriggerHandler?.isRunning != true else { return }
        voiceInputTask = Task { @MainActor [weak self] in
            await self?.startVoiceInput()
        }
    }

    func startVoiceInput() async {
        let handler = resolveVoiceTriggerHandler()
        showVoiceIndicator(handler)
        await handler.start(config: configService?.current.voice ?? .defaults)
        scheduleVoiceIndicatorDismissal(for: handler)
    }

    func resolveVoiceTriggerHandler() -> VoiceTriggerHandler {
        if let voiceTriggerHandler {
            return voiceTriggerHandler
        }

        let handler = VoiceTriggerHandler(
            sessionFactory: injectedVoiceSessionFactory ?? { statusDidChange, partialDidChange in
                VoiceSession(
                    statusDidChange: statusDidChange,
                    partialDidChange: partialDidChange
                )
            },
            transcriptConsumer: { [weak self] transcript in
                self?.applyVoiceTranscript(transcript)
            }
        )
        voiceTriggerHandler = handler
        return handler
    }

    func applyVoiceTranscript(_ transcript: VoiceTranscript) {
        let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if isAgentModeVisible {
            let viewModel = resolveAgentPanelViewModel()
            viewModel.promptDraft = mergedVoiceText(existing: viewModel.promptDraft, transcript: text)
            return
        }

        if isAuroraChromeActive, let controller = auroraChromeController {
            controller.setPaletteActions(buildAuroraPaletteActions())
            controller.showPalette()
            controller.paletteQuery = text
            if let host = controller.paletteHost {
                window?.makeFirstResponder(host)
            }
            return
        }

        if !isCommandPaletteVisible {
            showCommandPaletteOverlay()
        }
        commandPaletteViewModel?.query = text
    }

    private func mergedVoiceText(existing: String, transcript: String) -> String {
        let trimmedExisting = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExisting.isEmpty else { return transcript }
        return "\(trimmedExisting) \(transcript)"
    }

    private func showVoiceIndicator(_ handler: VoiceTriggerHandler) {
        guard let overlayContainer = overlayContainerView else { return }

        if voiceIndicatorHostingView == nil {
            let hostingView = NSHostingView(rootView: VoiceIndicator(handler: handler, localizer: appLocalizer()))
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            hostingView.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
            voiceIndicatorHostingView = hostingView
            overlayContainer.addSubview(hostingView)
        } else {
            voiceIndicatorHostingView?.rootView = VoiceIndicator(handler: handler, localizer: appLocalizer())
        }

        layoutVoiceIndicator()
    }

    private func layoutVoiceIndicator() {
        guard let overlayContainer = overlayContainerView,
              let hostingView = voiceIndicatorHostingView else { return }
        let width = min(360, max(240, overlayContainer.bounds.width - 48))
        let height: CGFloat = 44
        hostingView.frame = NSRect(
            x: (overlayContainer.bounds.width - width) * 0.5,
            y: max((statusBarHostingView?.frame.height ?? 24) + 16, 16),
            width: width,
            height: height
        )
    }

    private func scheduleVoiceIndicatorDismissal(for handler: VoiceTriggerHandler) {
        Task { @MainActor [weak self, weak handler] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard let self, let handler, self.voiceTriggerHandler === handler else { return }
            handler.reset()
            self.voiceIndicatorHostingView?.removeFromSuperview()
            self.voiceIndicatorHostingView = nil
        }
    }
}
