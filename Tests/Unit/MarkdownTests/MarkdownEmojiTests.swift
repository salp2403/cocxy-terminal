// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal
@testable import CocxyMarkdownLib

@Suite("MarkdownEmoji")
struct MarkdownEmojiTests {
    private let parser = MarkdownInlineParser()

    @Test("known shortcode resolves to emoji")
    func knownShortcodeResolves() {
        #expect(MarkdownEmoji.resolve("rocket") == "🚀")
    }

    @Test("unknown shortcode remains unresolved")
    func unknownShortcodeReturnsNil() {
        #expect(MarkdownEmoji.resolve("totally_unknown") == nil)
    }

    @Test("parser converts known shortcode into text emoji")
    func parserConvertsKnownShortcode() {
        #expect(parser.parse(":rocket: launch") == [.text("🚀 launch")])
    }

    @Test("parser leaves unknown shortcode literal")
    func parserLeavesUnknownShortcodeLiteral() {
        #expect(parser.parse(":unknown:") == [.text(":unknown:")])
    }

    @Test("emoji table covers representative 200+ shortcode set")
    func emojiTableCoverage() {
        let required: [(String, String)] = [
            ("rocket", "🚀"),
            ("heart_eyes", "😍"),
            ("ok_hand", "👌"),
            ("dog", "🐶"),
            ("pizza", "🍕"),
            ("soccer", "⚽"),
            ("airplane", "✈️"),
            ("gear", "⚙️"),
            ("flag_us", "🇺🇸"),
            ("broken_heart", "💔"),
            ("rainbow", "🌈"),
            ("trophy", "🏆"),
        ]

        #expect(MarkdownEmoji.count >= 200)

        for (code, emoji) in required {
            #expect(MarkdownEmoji.resolve(code) == emoji, "Missing shortcode :\(code):")
        }
    }
}
