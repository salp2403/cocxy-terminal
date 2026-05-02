// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
import CocxyCoreKit
import Darwin

@Suite("CocxyCore block API", .serialized)
struct CocxyCoreBlockAPISwiftTestingTests {

    @Test("vendored CocxyCore exposes block iterator metadata JSON and callbacks")
    func vendoredCocxyCoreExposesBlockAPI() throws {
        let terminal = try #require(cocxycore_terminal_create(24, 80))
        defer { cocxycore_terminal_destroy(terminal) }

        #expect(cocxycore_terminal_enable_semantic(terminal, 8) == true)

        BlockCallbackCapture.reset()
        cocxycore_block_set_event_callback(terminal, { kind, blockID, _ in
            BlockCallbackCapture.record(kind: kind.rawValue, blockID: blockID)
        }, nil)

        let detail = "swift block"
        try injectPluginBlock(detail: detail, row: 5, into: terminal)

        #expect(BlockCallbackCapture.kinds.contains(1))
        #expect(BlockCallbackCapture.kinds.contains(3))
        #expect(BlockCallbackCapture.ids.allSatisfy { $0 != 0 })

        let iterator = try #require(cocxycore_block_iterator_create(terminal))
        defer { cocxycore_block_iterator_destroy(iterator) }

        #expect(cocxycore_block_iterator_next(iterator) == true)
        let blockID = cocxycore_block_iterator_current_id(iterator)
        #expect(blockID != 0)
        #expect(cocxycore_block_iterator_next(iterator) == false)

        var metadata = cocxycore_block_metadata()
        #expect(cocxycore_block_get_metadata(terminal, blockID, &metadata) == true)
        #expect(metadata.id == blockID)
        #expect(metadata.block_type == 3)
        #expect(metadata.exit_code == -1)
        #expect(metadata.start_row == 5)
        #expect(metadata.end_row == 5)
        #expect(metadata.command_len == detail.utf8.count)
        #expect(String(cString: try #require(metadata.command)) == detail)
        #expect(metadata.pwd == nil)

        let required = cocxycore_block_serialize_json(terminal, blockID, nil, 0)
        #expect(required > 0)
        var buffer = [CChar](repeating: 0, count: required)
        let written = cocxycore_block_serialize_json(terminal, blockID, &buffer, buffer.count)
        #expect(written == required)
        let json = String(decoding: buffer.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        #expect(json.contains("\"id\":"))
        #expect(json.contains("\"block_type\":3"))
        #expect(json.contains("\"command\":\"swift block\""))
        #expect(json.contains("\"pwd\":null"))
    }

    @Test("vendored CocxyCore exposes structured stream block output helpers")
    func vendoredCocxyCoreExposesStructuredStreamOutputHelpers() throws {
        let terminal = try #require(cocxycore_terminal_create(24, 80))
        defer { cocxycore_terminal_destroy(terminal) }

        #expect(cocxycore_terminal_enable_semantic(terminal, 32) == true)

        for index in 0..<6 {
            let sequence = "\u{001B}]133;A\u{0007}\u{001B}]133;C\u{0007}line-\(index)\r\n\u{001B}]133;D;0\u{0007}"
            let bytes = Array(sequence.utf8)
            cocxycore_terminal_feed(terminal, bytes, bytes.count)
        }

        var lastFive = [CChar](repeating: 0, count: 256)
        let lastFiveLen = cocxycore_get_last_n_block_outputs(
            terminal,
            5,
            &lastFive,
            lastFive.count,
            true
        )
        #expect(lastFiveLen > 0)
        #expect(string(from: lastFive, count: lastFiveLen) == "line-1\nline-2\nline-3\nline-4\nline-5")

        let iterator = try #require(cocxycore_block_iterator_create(terminal))
        defer { cocxycore_block_iterator_destroy(iterator) }

        var lastOutputBlockID: UInt64 = 0
        while cocxycore_block_iterator_next(iterator) {
            let blockID = cocxycore_block_iterator_current_id(iterator)
            var metadata = cocxycore_block_metadata()
            if cocxycore_block_get_metadata(terminal, blockID, &metadata),
               metadata.block_type == 2 {
                lastOutputBlockID = blockID
            }
        }

        #expect(lastOutputBlockID != 0)

        var oneBlock = [CChar](repeating: 0, count: 64)
        let oneBlockLen = cocxycore_block_get_output(
            terminal,
            lastOutputBlockID,
            &oneBlock,
            oneBlock.count,
            true
        )
        #expect(string(from: oneBlock, count: oneBlockLen) == "line-5")
    }

    @Test("vendored CocxyCore preserves OSC 133 command payload metadata")
    func vendoredCocxyCorePreservesOSC133CommandPayloadMetadata() throws {
        let terminal = try #require(cocxycore_terminal_create(24, 80))
        defer { cocxycore_terminal_destroy(terminal) }

        #expect(cocxycore_terminal_enable_semantic(terminal, 8) == true)

        let sequence = "\u{001B}]133;A\u{0007}" +
            "\u{001B}]133;B\u{0007}" +
            "\u{001B}]133;C;echo swift-payload\u{0007}" +
            "swift-payload\r\n" +
            "\u{001B}]133;D;0\u{0007}"
        let bytes = Array(sequence.utf8)
        cocxycore_terminal_feed(terminal, bytes, bytes.count)

        let iterator = try #require(cocxycore_block_iterator_create(terminal))
        defer { cocxycore_block_iterator_destroy(iterator) }

        var outputBlockID: UInt64 = 0
        while cocxycore_block_iterator_next(iterator) {
            let blockID = cocxycore_block_iterator_current_id(iterator)
            var metadata = cocxycore_block_metadata()
            if cocxycore_block_get_metadata(terminal, blockID, &metadata),
               metadata.block_type == 2 {
                outputBlockID = blockID
                break
            }
        }

        #expect(outputBlockID != 0)

        var metadata = cocxycore_block_metadata()
        #expect(cocxycore_block_get_metadata(terminal, outputBlockID, &metadata) == true)
        #expect(metadata.command_len == "echo swift-payload".utf8.count)
        #expect(String(cString: try #require(metadata.command)) == "echo swift-payload")
    }

    @Test("vendored CocxyCore decodes encoded multiline OSC 133 command payload metadata")
    func vendoredCocxyCoreDecodesEncodedMultilineOSC133CommandPayloadMetadata() throws {
        let terminal = try #require(cocxycore_terminal_create(24, 80))
        defer { cocxycore_terminal_destroy(terminal) }

        #expect(cocxycore_terminal_enable_semantic(terminal, 8) == true)

        let expectedCommand = "for x in alpha beta; do\n  echo multi-$x\ndone"
        let sequence = "\u{001B}]133;A\u{0007}" +
            "\u{001B}]133;B\u{0007}" +
            "\u{001B}]133;C;cocxy-percent-v1:for x in alpha beta; do%0A  echo multi-$x%0Adone\u{0007}" +
            "multi-alpha\r\n" +
            "multi-beta\r\n" +
            "\u{001B}]133;D;0\u{0007}"
        let bytes = Array(sequence.utf8)
        cocxycore_terminal_feed(terminal, bytes, bytes.count)

        let iterator = try #require(cocxycore_block_iterator_create(terminal))
        defer { cocxycore_block_iterator_destroy(iterator) }

        var outputBlockID: UInt64 = 0
        while cocxycore_block_iterator_next(iterator) {
            let blockID = cocxycore_block_iterator_current_id(iterator)
            var metadata = cocxycore_block_metadata()
            if cocxycore_block_get_metadata(terminal, blockID, &metadata),
               metadata.block_type == 2 {
                outputBlockID = blockID
                break
            }
        }

        #expect(outputBlockID != 0)

        var metadata = cocxycore_block_metadata()
        #expect(cocxycore_block_get_metadata(terminal, outputBlockID, &metadata) == true)
        #expect(metadata.command_len == expectedCommand.utf8.count)
        #expect(String(cString: try #require(metadata.command)) == expectedCommand)
    }

    @Test("vendored CocxyCore exposes CC-5 plugin extension symbols")
    func vendoredCocxyCoreExposesPluginExtensions() throws {
        let terminal = try #require(cocxycore_terminal_create(24, 80))
        defer { cocxycore_terminal_destroy(terminal) }

        PluginExtensionCapture.reset()

        #expect(cocxycore_terminal_enable_semantic(terminal, 8) == true)
        try injectPluginBlock(detail: "swift secret command", row: 7, into: terminal)

        let iterator = try #require(cocxycore_block_iterator_create(terminal))
        defer { cocxycore_block_iterator_destroy(iterator) }
        #expect(cocxycore_block_iterator_next(iterator) == true)
        let blockID = cocxycore_block_iterator_current_id(iterator)
        #expect(blockID != 0)

        let blockHandle = cocxycore_plugin_register_block_intercept(terminal, { blockID, _ in
            PluginExtensionCapture.blockInterceptCalls += 1
            return cocxycore_block_intercept_result(
                modified_command: PluginExtensionCapture.replacementCommand,
                prevent_default_render: blockID != 0
            )
        }, nil)
        #expect(blockHandle != 0)

        var preventDefaultRender = false
        var commandBuffer = [CChar](repeating: 0, count: 64)
        let commandLen = cocxycore_plugin_apply_block_intercepts(
            terminal,
            blockID,
            &commandBuffer,
            commandBuffer.count,
            &preventDefaultRender
        )
        #expect(commandLen == PluginExtensionCapture.replacementText.utf8.count)
        #expect(preventDefaultRender == true)
        #expect(string(from: commandBuffer, count: commandLen) == PluginExtensionCapture.replacementText)

        var metadata = cocxycore_block_metadata()
        #expect(cocxycore_block_get_metadata(terminal, blockID, &metadata) == true)
        #expect(String(cString: try #require(metadata.command)) == PluginExtensionCapture.replacementText)
        #expect(PluginExtensionCapture.blockInterceptCalls >= 2)

        let oscHandle = cocxycore_plugin_register_osc_handler(terminal, 90000, 90010, { code, payload, len, _ in
            PluginExtensionCapture.oscCalls += 1
            PluginExtensionCapture.lastOscCode = code
            if let payload {
                let bytes = UnsafeBufferPointer(start: payload, count: len)
                PluginExtensionCapture.lastOscPayload = String(
                    decoding: bytes.map { UInt8(bitPattern: $0) },
                    as: UTF8.self
                )
            } else {
                PluginExtensionCapture.lastOscPayload = ""
            }
            return true
        }, nil)
        #expect(oscHandle != 0)

        let osc = "\u{001B}]90005;swift-private\u{0007}"
        let oscBytes = Array(osc.utf8)
        cocxycore_terminal_feed(terminal, oscBytes, oscBytes.count)
        #expect(PluginExtensionCapture.oscCalls == 1)
        #expect(PluginExtensionCapture.lastOscCode == 90005)
        #expect(PluginExtensionCapture.lastOscPayload == "swift-private")

        #expect(cocxycore_plugin_register_osc_handler(terminal, 89999, 90000, nil, nil) == 0)
        #expect(cocxycore_plugin_register_theme_generator(terminal, nil, nil) == 0)
        #expect(cocxycore_plugin_apply_theme_generator(terminal, 9999) == false)

        cocxycore_plugin_unregister(terminal, blockHandle)
        preventDefaultRender = true
        #expect(cocxycore_plugin_apply_block_intercepts(
            terminal,
            blockID,
            &commandBuffer,
            commandBuffer.count,
            &preventDefaultRender
        ) == 0)
        #expect(preventDefaultRender == false)

        cocxycore_plugin_unregister(terminal, oscHandle)
        cocxycore_terminal_feed(terminal, oscBytes, oscBytes.count)
        #expect(PluginExtensionCapture.oscCalls == 1)
    }
}

private enum BlockCallbackCapture {
    static var kinds: [UInt32] = []
    static var ids: [UInt64] = []

    static func reset() {
        kinds.removeAll()
        ids.removeAll()
    }

    static func record(kind: UInt32, blockID: UInt64) {
        kinds.append(kind)
        ids.append(blockID)
    }
}

private enum PluginExtensionCapture {
    static let replacementText = "swift [redacted]"
    static let replacementCommand: UnsafePointer<CChar> = {
        guard let ptr = strdup(replacementText) else {
            preconditionFailure("strdup failed for static plugin replacement text")
        }
        return UnsafePointer(ptr)
    }()

    static var blockInterceptCalls = 0
    static var oscCalls = 0
    static var lastOscCode: UInt32 = 0
    static var lastOscPayload = ""

    static func reset() {
        blockInterceptCalls = 0
        oscCalls = 0
        lastOscCode = 0
        lastOscPayload = ""
    }
}

private func injectPluginBlock(detail: String, row: UInt32, into terminal: OpaquePointer) throws {
    let bytes = Array(detail.utf8)
    bytes.withUnsafeBufferPointer { buffer in
        var event = cocxycore_semantic_event(
            event_type: 6,
            source: 5,
            exit_code: -1,
            row: row,
            block_id: 0,
            confidence: 1.0,
            timestamp: 0,
            detail_ptr: buffer.baseAddress,
            detail_len: UInt16(bytes.count),
            _pad: 0,
            stream_id: 0
        )
        #expect(cocxycore_terminal_inject_semantic_event(terminal, &event) == true)
    }
}

private func string(from buffer: [CChar], count: Int) -> String {
    String(decoding: buffer.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
