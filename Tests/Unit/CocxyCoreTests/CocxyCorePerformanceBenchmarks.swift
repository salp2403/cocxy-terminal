// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Darwin
import Testing
import CocxyCoreKit
@testable import CocxyTerminal

@Suite("CocxyCore performance benchmarks", .serialized)
@MainActor
struct CocxyCorePerformanceBenchmarks {

    @Test("surface creation stays within the startup budget")
    func surfaceCreationStartupBudget() throws {
        let bridge = try makeBridge()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let surfaceID = try bridge.createSurface(
            in: view,
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
            command: "/bin/cat"
        )
        let elapsed = secondsSince(startedAt)
        defer { bridge.destroySurface(surfaceID) }

        #expect(
            elapsed < 0.25,
            Comment("Measured CocxyCore surface creation time: \(formatSeconds(elapsed))")
        )
    }

    @Test("echo latency stays within the responsiveness budget")
    func echoLatencyStaysInteractive() async throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createBenchmarkSurface(using: bridge, command: "/bin/cat")
        defer { bridge.destroySurface(surfaceID) }

        let recorder = OutputRecorder()
        bridge.setOutputHandler(for: surfaceID) { data in
            recorder.append(data)
        }

        let warmup = "__COCXYCORE_WARMUP__"
        bridge.sendText("\(warmup)\n", to: surfaceID)
        try await waitUntil {
            recorder.output.contains(warmup)
        }

        let marker = "__COCXYCORE_ECHO__\(UUID().uuidString)"
        let startedAt = DispatchTime.now().uptimeNanoseconds
        bridge.sendText("\(marker)\n", to: surfaceID)

        try await waitUntil(pollNanoseconds: 1_000_000) {
            recorder.output.contains(marker)
        }

        let latency = secondsSince(startedAt)
        #expect(
            latency < 0.25,
            Comment("Measured CocxyCore echo latency: \(formatMilliseconds(latency))")
        )
    }

    @Test("bulk terminal output sustains healthy throughput")
    func outputThroughputRemainsHealthy() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxycore-throughput-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pythonURL = tempDir.appendingPathComponent("throughput.py")
        let python = """
        import os
        import time

        size = 100_000_000
        chunk = b"A" * 1_048_576
        remaining = size
        fd = os.open("/dev/null", os.O_WRONLY)
        start = time.perf_counter()
        try:
            while remaining > 0:
                piece = chunk if remaining >= len(chunk) else b"A" * remaining
                os.write(fd, piece)
                remaining -= len(piece)
        finally:
            os.close(fd)

        elapsed = time.perf_counter() - start
        print(f"THROUGHPUT_MBPS={size / elapsed / 1_048_576:.2f}")
        """
        try python.write(to: pythonURL, atomically: true, encoding: String.Encoding.utf8)

        let scriptURL = tempDir.appendingPathComponent("throughput.zsh")
        let script = """
        #!/bin/zsh
        exec python3 \(benchmarkShellQuote(pythonURL.path))
        """
        try script.write(to: scriptURL, atomically: true, encoding: String.Encoding.utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let bridge = try makeBridge()
        let (surfaceID, _) = try createBenchmarkSurface(using: bridge, command: scriptURL.path)
        defer { bridge.destroySurface(surfaceID) }

        let recorder = OutputRecorder()
        bridge.setOutputHandler(for: surfaceID) { data in
            recorder.append(data)
        }

        try await waitUntil(timeoutNanoseconds: 5_000_000_000, pollNanoseconds: 1_000_000) {
            recorder.output.contains("THROUGHPUT_MBPS=")
        }

        let line = try #require(
            recorder.output
                .split(whereSeparator: \.isNewline)
                .last(where: { $0.contains("THROUGHPUT_MBPS=") })
        )
        let throughputValue = try #require(Double(line.replacingOccurrences(of: "THROUGHPUT_MBPS=", with: "")))

        #expect(
            throughputValue >= 1_000.0,
            Comment("Measured CocxyCore throughput: \(String(format: "%.2f", throughputValue)) MB/s")
        )
    }

    @Test("frame preparation remains below the frame-time budget")
    func framePreparationMeetsBudget() throws {
        let renderer = try MetalTerminalRenderer()
        let terminal = try makeBenchmarkTerminal(rows: 40, cols: 120)
        defer { cocxycore_terminal_destroy(terminal) }

        renderer.updateViewportSize(
            CGSize(width: 1440, height: 900),
            scale: 2.0,
            paddingX: 8,
            paddingY: 4
        )

        _ = renderer.prepareFrameResources(terminal: terminal)

        let iterations = 40
        let startedAt = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            #expect(renderer.prepareFrameResources(terminal: terminal) == true)
        }
        let elapsed = secondsSince(startedAt)
        let averageFrameTime = elapsed / Double(iterations)

        #expect(
            averageFrameTime < 0.016,
            Comment("Measured average CocxyCore frame preparation time: \(formatMilliseconds(averageFrameTime))")
        )
    }

    // Expected RSS breakdown for a full CocxyCore surface:
    //   Scrollback ring buffer  ~24 MB  (10K rows × 80 cols × ~32 B/cell)
    //   Glyph atlas bitmap       ~4 MB  (2048×2048 R8)
    //   Metal shader pipelines   ~8 MB  (3 compiled pipeline states)
    //   CoreText font shaper     ~3 MB  (font tables + glyph cache)
    //   PTY + process + IO       ~2 MB  (kernel resources)
    //   Driver/framework overhead ~5 MB  (Metal driver, CAMetalLayer, CVDisplayLink)
    //   Semantic + process track  ~1 MB
    //   ≈ 47-68 MB depending on driver state and system load.
    //   Threshold set at 72 MB to absorb normal RSS measurement variance
    //   while still catching double-allocation regressions (~130+ MB).
    private static let memoryDeltaThresholdMB: Double = 72.0

    @Test("idle CocxyCore surface memory delta stays bounded")
    func idleSurfaceMemoryDeltaStaysBounded() throws {
        let rssBefore = currentResidentSize()

        let bridge = try makeBridge()
        let viewModel = TerminalViewModel(engine: bridge)
        let view = CocxyCoreView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 960, height: 540)
        _ = view.layer

        let surfaceID = try bridge.createSurface(
            in: view,
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
            command: "/bin/cat"
        )
        defer { bridge.destroySurface(surfaceID) }

        viewModel.markRunning(surfaceID: surfaceID)
        view.configureSurfaceIfNeeded(bridge: bridge, surfaceID: surfaceID)

        let rssAfter = currentResidentSize()
        let deltaBytes = rssAfter >= rssBefore ? rssAfter - rssBefore : 0
        let deltaMB = Double(deltaBytes) / 1_048_576.0

        #expect(
            deltaMB < Self.memoryDeltaThresholdMB,
            Comment("Measured idle CocxyCore RSS delta: \(String(format: "%.2f", deltaMB)) MB")
        )
    }
}

@MainActor
private func createBenchmarkSurface(
    using bridge: CocxyCoreBridge,
    command: String
) throws -> (SurfaceID, NSView) {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
    let surfaceID = try bridge.createSurface(
        in: view,
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
        command: command
    )
    return (surfaceID, view)
}

private func makeBenchmarkTerminal(
    rows: UInt16,
    cols: UInt16,
    prefill: Bool = true
) throws -> OpaquePointer {
    let terminal = try #require(cocxycore_terminal_create(rows, cols))

    cocxycore_terminal_enable_scrollback(terminal, 10_000)

    let fontConfigured = "Menlo".withCString { family in
        cocxycore_terminal_set_font(terminal, family, 14, 2.0, true)
    }
    #expect(fontConfigured == true)

    cocxycore_terminal_set_theme(
        terminal,
        235, 235, 235,
        30, 30, 30,
        255, 255, 255
    )

    if prefill {
        let rowText = String(repeating: "benchmark-cell ", count: 12)
        let content = Array(repeating: rowText, count: Int(rows)).joined(separator: "\r\n") + "\r\n"
        let bytes = Array(content.utf8)
        cocxycore_terminal_feed(terminal, bytes, bytes.count)
    }

    return terminal
}

private func secondsSince(_ startedAt: UInt64) -> Double {
    nanosecondsToSeconds(DispatchTime.now().uptimeNanoseconds - startedAt)
}

private func nanosecondsToSeconds(_ value: UInt64) -> Double {
    Double(value) / 1_000_000_000.0
}

private func formatSeconds(_ value: Double) -> String {
    String(format: "%.3f s", value)
}

private func formatMilliseconds(_ value: Double) -> String {
    String(format: "%.2f ms", value * 1_000.0)
}

private func benchmarkShellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func currentResidentSize() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)

    let result: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPointer in
        infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
            task_info(
                mach_task_self_,
                task_flavor_t(MACH_TASK_BASIC_INFO),
                intPointer,
                &count
            )
        }
    }

    guard result == KERN_SUCCESS else { return 0 }
    return UInt64(info.resident_size)
}

private final class OutputRecorder: @unchecked Sendable {
    private(set) var output = ""

    func append(_ data: Data) {
        output.append(String(decoding: data, as: UTF8.self))
    }
}
