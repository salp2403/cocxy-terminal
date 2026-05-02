// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Testing
import CocxyCoreKit

@Suite("CocxyCore search enhancements", .serialized)
struct CocxyCoreSearchEnhancementsSwiftTestingTests {

    @Test("vendored CocxyCore exposes global search and regex captures")
    func vendoredCocxyCoreExposesGlobalSearchAndCaptures() throws {
        let terminal = try #require(cocxycore_terminal_create(3, 48))
        defer { cocxycore_terminal_destroy(terminal) }

        let row = "cc6_swift_user=ana cc6_swift_id=73"
        feed(row, into: terminal)

        let pattern = "cc6_swift_user=([a-z]+) cc6_swift_id=([0-9]+)"
        let handle = try #require(pattern.withCString { pointer in
            cocxycore_search_global_create(pointer, true)
        })
        defer { cocxycore_search_destroy(handle) }

        var resultBuffer = [CChar](repeating: 0, count: 1024)
        let resultLength = cocxycore_search_global_results(handle, &resultBuffer, resultBuffer.count)
        let json = string(from: resultBuffer, count: resultLength)
        #expect(json.contains("\"terminal_id\":"))
        #expect(json.contains("\"row\":0"))
        #expect(json.contains("\"start_col\":0"))
        #expect(json.contains("\"end_col\":33"))

        var captures = [cocxycore_search_capture](
            repeating: cocxycore_search_capture(capture_index: 0, start: 0, length: 0),
            count: 4
        )
        let captureCount = cocxycore_search_get_captures(handle, 0, &captures, captures.count)
        #expect(captureCount == 2)
        #expect(captures[0].capture_index == 1)
        #expect(captures[0].start == 15)
        #expect(captures[0].length == 3)
        #expect(captures[1].capture_index == 2)
        #expect(captures[1].start == 32)
        #expect(captures[1].length == 2)
    }

    @Test("vendored CocxyCore persists saved searches through local file")
    func vendoredCocxyCorePersistsSavedSearches() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let searchesPath = directory.appendingPathComponent("searches.toml").path
        let setenvResult = searchesPath.withCString { path in
            setenv("COCXYCORE_SEARCHES_PATH", path, 1)
        }
        #expect(setenvResult == 0)
        defer { unsetenv("COCXYCORE_SEARCHES_PATH") }

        do {
            let terminal = try #require(cocxycore_terminal_create(2, 24))
            defer { cocxycore_terminal_destroy(terminal) }
            #expect(cocxycore_search_save(terminal, "swift_cc6_errors", "error|fail", true))
        }

        do {
            let terminal = try #require(cocxycore_terminal_create(2, 24))
            defer { cocxycore_terminal_destroy(terminal) }

            var listBuffer = [CChar](repeating: 0, count: 1024)
            let listLength = cocxycore_search_list_saved(terminal, &listBuffer, listBuffer.count)
            let list = string(from: listBuffer, count: listLength)
            #expect(list.contains("\"name\":\"swift_cc6_errors\""))
            #expect(list.contains("\"pattern\":\"error|fail\""))
            #expect(list.contains("\"is_regex\":true"))

            #expect(cocxycore_search_delete_saved(terminal, "swift_cc6_errors"))

            let afterDeleteLength = cocxycore_search_list_saved(terminal, &listBuffer, listBuffer.count)
            let afterDelete = string(from: listBuffer, count: afterDeleteLength)
            #expect(!afterDelete.contains("swift_cc6_errors"))
        }
    }
}

private func feed(_ text: String, into terminal: OpaquePointer) {
    let bytes = Array(text.utf8)
    cocxycore_terminal_feed(terminal, bytes, bytes.count)
}

private func string(from buffer: [CChar], count: Int) -> String {
    String(decoding: buffer.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
