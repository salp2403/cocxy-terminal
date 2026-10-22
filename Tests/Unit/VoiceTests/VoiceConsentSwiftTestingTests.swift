// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("Voice consent coordinator")
@MainActor
struct VoiceConsentSwiftTestingTests {
    @Test("only enabled unacknowledged Voice can claim a presentation")
    func presentationEligibility() {
        let coordinator = VoiceConsentCoordinator()

        #expect(coordinator.claimPresentation(for: .defaults))
        #expect(!coordinator.claimPresentation(for: .defaults))
        #expect(coordinator.presentationCount == 1)
    }

    @Test("disabled or previously acknowledged Voice never presents")
    func acknowledgedAndDisabledVoiceDoNotPresent() {
        let acknowledged = VoiceConsentCoordinator()
        let disabled = VoiceConsentCoordinator()

        #expect(!acknowledged.claimPresentation(for: VoiceConfig(consentPrompted: true)))
        #expect(!disabled.claimPresentation(for: VoiceConfig(enabled: false)))
        #expect(acknowledged.presentationCount == 0)
        #expect(disabled.presentationCount == 0)
    }
}
