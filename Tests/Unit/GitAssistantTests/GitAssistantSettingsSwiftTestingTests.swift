import Testing
@testable import CocxyTerminal

@Suite("GitAssistantSettings")
struct GitAssistantSettingsSwiftTestingTests {
    @Test("defaults are local-first and automatic generation is opt-in")
    func defaultsAreLocalFirst() {
        let defaults = GitAssistantSettings.defaults

        #expect(defaults.enabled)
        #expect(defaults.defaultProvider == .foundationModelsOnDevice)
        #expect(defaults.promptStyle == .conventional)
        #expect(defaults.maxDiffLines == 4_000)
        #expect(!defaults.autoGeneratePRBodyOnCreate)
        #expect(!defaults.autoGenerateCommitMessageOnStage)
    }

    @Test("max diff lines are clamped to a safe prompt budget")
    func maxDiffLinesClamped() {
        #expect(GitAssistantSettings(maxDiffLines: -10).maxDiffLines == GitAssistantSettings.minMaxDiffLines)
        #expect(GitAssistantSettings(maxDiffLines: 999_999).maxDiffLines == GitAssistantSettings.maxMaxDiffLines)
    }
}
