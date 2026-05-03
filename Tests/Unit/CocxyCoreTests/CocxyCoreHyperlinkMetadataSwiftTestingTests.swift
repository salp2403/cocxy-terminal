// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
import CocxyCoreKit

@Suite("CocxyCore Hyperlink Metadata")
struct CocxyCoreHyperlinkMetadataSwiftTestingTests {

    @Test("vendored CocxyCore exposes OSC 8 hyperlink metadata")
    func vendoredCocxyCoreExposesHyperlinkMetadata() throws {
        let terminal = try #require(cocxycore_terminal_create(4, 40))
        defer { cocxycore_terminal_destroy(terminal) }

        feed(
            "\u{001B}]8;id=docs;https://cocxy.dev/docs\u{0007}Click\u{001B}]8;;\u{0007}",
            into: terminal
        )

        var metadata = cocxycore_hyperlink_metadata()
        #expect(cocxycore_terminal_get_hyperlink_at(terminal, 0, 0, &metadata))
        #expect(string(from: metadata.uri, length: metadata.uri_len) == "https://cocxy.dev/docs")
        #expect(string(from: metadata.params, length: metadata.params_len) == "id=docs")
        #expect(metadata.row == 0)
        #expect(metadata.column == 0)
        #expect(metadata.length == 5)
        #expect(cocxycore_terminal_get_hyperlink_at(terminal, 0, 5, &metadata) == false)

        #expect(cocxycore_terminal_iterate_hyperlinks(terminal, nil, 0) == 1)

        var buffer = [cocxycore_hyperlink_metadata](
            repeating: cocxycore_hyperlink_metadata(),
            count: 2
        )
        let total = cocxycore_terminal_iterate_hyperlinks(terminal, &buffer, buffer.count)
        #expect(total == 1)
        #expect(string(from: buffer[0].uri, length: buffer[0].uri_len) == "https://cocxy.dev/docs")
    }
}

private func feed(_ text: String, into terminal: OpaquePointer) {
    let bytes = Array(text.utf8)
    cocxycore_terminal_feed(terminal, bytes, bytes.count)
}

private func string(from pointer: UnsafePointer<CChar>?, length: Int) -> String {
    guard let pointer, length > 0 else { return "" }
    let buffer = UnsafeBufferPointer(start: pointer, count: length)
    return String(decoding: buffer.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
