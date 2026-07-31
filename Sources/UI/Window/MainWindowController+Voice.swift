// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+Voice.swift - Voice input action wiring.

import AppKit
import SwiftUI

@MainActor
extension MainWindowController {
    @objc func startVoiceInputAction(_ sender: Any?) {
        guard voiceTriggerHandler?.isRunning != true else { return }
        presentVoiceConsentIfNeeded()
        voiceInputTask = Task { @MainActor [weak self] in
            await self?.startVoiceInput()
        }
    }

    func startVoiceInput() async {
        presentVoiceConsentIfNeeded()
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

        if let surfaceID = activeTerminalSurfaceView?.terminalViewModel?.surfaceID,
           injectedPerSurfaceStore?.state(for: surfaceID).hasAgent == true {
            let shouldSubmit = configService?.current.voice.autoSendToAgent
                ?? VoiceConfig.defaults.autoSendToAgent
            terminalEngine(for: surfaceID).sendText(
                shouldSubmit ? text + "\r" : text,
                to: surfaceID
            )
            return
        }

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

    func presentVoiceConsentIfNeeded() {
        guard voiceConsentBannerHostingView == nil,
              let overlayContainer = overlayContainerView,
              let configService,
              voiceConsentCoordinator.claimPresentation(for: configService.current.voice) else {
            return
        }

        voiceConsentErrorMessage = nil
        let hostingView = NSHostingView(rootView: makeVoiceConsentBanner())
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        voiceConsentBannerHostingView = hostingView
        overlayContainer.addSubview(hostingView)
        layoutVoiceConsentBanner()
    }

    func updateVoiceConsentPresentation(for config: VoiceConfig) {
        guard config.enabled, !config.consentPrompted else {
            dismissVoiceConsentBanner()
            return
        }
        presentVoiceConsentIfNeeded()
    }

    func resolveVoiceConsent(keepEnabled: Bool) {
        guard let configService else { return }
        do {
            try configService.updateVoiceConsent(
                enabled: keepEnabled ? nil : false,
                consentPrompted: true
            )
            dismissVoiceConsentBanner()
        } catch {
            voiceConsentErrorMessage = VoiceConsentBanner.localizedSaveFailed(using: appLocalizer())
            voiceConsentBannerHostingView?.rootView = makeVoiceConsentBanner()
            layoutVoiceConsentBanner()
        }
    }

    func layoutVoiceConsentBanner() {
        guard let overlayContainer = overlayContainerView,
              let hostingView = voiceConsentBannerHostingView else { return }
        let width = min(680, max(420, overlayContainer.bounds.width - 48))
        let height: CGFloat = voiceConsentErrorMessage == nil ? 134 : 154
        hostingView.frame = NSRect(
            x: (overlayContainer.bounds.width - width) * 0.5,
            y: max(16, overlayContainer.bounds.height - height - 16),
            width: width,
            height: height
        )
    }

    private func makeVoiceConsentBanner() -> VoiceConsentBanner {
        VoiceConsentBanner(
            localizer: appLocalizer(),
            errorMessage: voiceConsentErrorMessage,
            onKeepEnabled: { [weak self] in
                self?.resolveVoiceConsent(keepEnabled: true)
            },
            onDisable: { [weak self] in
                self?.resolveVoiceConsent(keepEnabled: false)
            },
            onOpenPreferences: { [weak self] in
                self?.openPreferences(section: .voice)
            }
        )
    }

    private func dismissVoiceConsentBanner() {
        voiceConsentBannerHostingView?.removeFromSuperview()
        voiceConsentBannerHostingView = nil
        voiceConsentErrorMessage = nil
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
