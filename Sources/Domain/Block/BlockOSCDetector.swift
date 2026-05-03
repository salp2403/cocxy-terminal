// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BlockOSCDetector.swift - Incremental OSC 133 parser for command block boundaries.

import Foundation

enum BlockOSCEvent: Equatable, Sendable {
    case promptStarted
    case commandStarted
    case commandExecuted(command: String?)
    case commandFinished(exitCode: Int?)
}

final class BlockOSCDetector: @unchecked Sendable {
    private enum ParserState {
        case normal
        case escapeReceived
        case readingOSC
        case oscEscapeReceived
    }

    private static let maxOSCBufferSize = 65_536
    private static let encodedCommandPrefix = "cocxy-percent-v1:"

    private var parserState: ParserState = .normal
    private var oscBuffer: [UInt8] = []
    private let lock = NSLock()
    private let onEvent: @Sendable (BlockOSCEvent) -> Void

    init(onEvent: @escaping @Sendable (BlockOSCEvent) -> Void = { _ in }) {
        self.onEvent = onEvent
    }

    @discardableResult
    func processBytes(_ data: Data) -> [BlockOSCEvent] {
        let events: [BlockOSCEvent]
        lock.lock()
        events = processLocked(data)
        lock.unlock()

        for event in events {
            onEvent(event)
        }
        return events
    }

    private func processLocked(_ data: Data) -> [BlockOSCEvent] {
        var events: [BlockOSCEvent] = []

        for byte in data {
            switch parserState {
            case .normal:
                if byte == 0x1B {
                    parserState = .escapeReceived
                }

            case .escapeReceived:
                if byte == 0x5D {
                    parserState = .readingOSC
                    oscBuffer.removeAll(keepingCapacity: true)
                } else if byte != 0x1B {
                    parserState = .normal
                }

            case .readingOSC:
                if byte == 0x07 {
                    appendCurrentPayloadEvent(to: &events)
                    resetParser()
                } else if byte == 0x1B {
                    parserState = .oscEscapeReceived
                } else {
                    oscBuffer.append(byte)
                    if oscBuffer.count > Self.maxOSCBufferSize {
                        resetParser()
                    }
                }

            case .oscEscapeReceived:
                if byte == 0x5C {
                    appendCurrentPayloadEvent(to: &events)
                    resetParser()
                } else if byte == 0x5D {
                    oscBuffer.removeAll(keepingCapacity: true)
                    parserState = .readingOSC
                } else if byte != 0x1B {
                    resetParser()
                }
            }
        }

        return events
    }

    private func appendCurrentPayloadEvent(to events: inout [BlockOSCEvent]) {
        guard let event = event(from: oscBuffer) else { return }
        events.append(event)
    }

    private func resetParser() {
        oscBuffer.removeAll(keepingCapacity: true)
        parserState = .normal
    }

    private func event(from bytes: [UInt8]) -> BlockOSCEvent? {
        guard let semicolonIndex = bytes.firstIndex(of: 0x3B) else { return nil }

        let codeBytes = Array(bytes[bytes.startIndex..<semicolonIndex])
        guard String(bytes: codeBytes, encoding: .utf8) == "133" else {
            return nil
        }

        let payloadBytes = Array(bytes[bytes.index(after: semicolonIndex)...])
        guard let payload = String(bytes: payloadBytes, encoding: .utf8),
              let subcommand = payload.first else {
            return nil
        }

        switch subcommand {
        case "A":
            return .promptStarted
        case "B":
            return .commandStarted
        case "C":
            return .commandExecuted(command: commandPayload(from: payload))
        case "D":
            return .commandFinished(exitCode: exitCode(from: payload))
        default:
            return nil
        }
    }

    private func commandPayload(from payload: String) -> String? {
        guard payload.hasPrefix("C;") else { return nil }
        let rawCommand = String(payload.dropFirst(2))
        guard !rawCommand.isEmpty else { return nil }
        guard rawCommand.hasPrefix(Self.encodedCommandPrefix) else {
            return rawCommand
        }

        let encoded = String(rawCommand.dropFirst(Self.encodedCommandPrefix.count))
        return Self.percentDecoded(encoded)
    }

    private func exitCode(from payload: String) -> Int? {
        let parts = payload.split(separator: ";", maxSplits: 2)
        guard parts.count >= 2 else { return nil }
        return Int(parts[1])
    }

    private static func percentDecoded(_ value: String) -> String {
        let scalars = Array(value.utf8)
        var output: [UInt8] = []
        output.reserveCapacity(scalars.count)

        var index = 0
        while index < scalars.count {
            if scalars[index] == 0x25,
               index + 2 < scalars.count,
               let high = hexValue(scalars[index + 1]),
               let low = hexValue(scalars[index + 2]) {
                output.append(high << 4 | low)
                index += 3
            } else {
                output.append(scalars[index])
                index += 1
            }
        }

        return String(decoding: output, as: UTF8.self)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57:
            return byte - 48
        case 65...70:
            return byte - 55
        case 97...102:
            return byte - 87
        default:
            return nil
        }
    }
}
