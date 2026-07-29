// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonSurface+Keys.swift - Key encoding for the daemon surface.

import CocxyCoreKit
import CocxyShared
import Foundation

extension PTYDaemonSurface {
    /// Encodes a CocxyCore special key (arrows, function keys, etc.) and
    /// writes the resulting bytes to the attached PTY.
    func writeEncodedKey(
        _ key: UInt8,
        modifiers: UInt,
        eventType: UInt8,
        shiftedCodepoint: UInt32,
        baseLayoutCodepoint: UInt32,
        associatedText: [UInt32]
    ) -> Bool {
        terminalLock.withLock {
            clearPreeditForPressLocked(eventType: eventType)
            var buffer = [UInt8](repeating: 0, count: 256)
            let count = associatedText.withUnsafeBufferPointer { associatedBuffer in
                cocxycore_terminal_encode_key_event(
                    terminal,
                    key,
                    Self.cocxyModifiers(from: modifiers),
                    eventType,
                    shiftedCodepoint,
                    baseLayoutCodepoint,
                    associatedBuffer.baseAddress,
                    associatedBuffer.count,
                    &buffer,
                    buffer.count
                )
            }
            guard count > 0 else { return false }
            return writeEncodedBytesLocked(Array(buffer.prefix(count)))
        }
    }

    /// Encodes a Unicode codepoint for the active terminal mode and writes
    /// the resulting bytes to the attached PTY.
    func writeEncodedCharacter(
        _ codepoint: UInt32,
        characters: String,
        modifiers: UInt,
        eventType: UInt8,
        shiftedCodepoint: UInt32,
        baseLayoutCodepoint: UInt32,
        associatedText: [UInt32]
    ) -> Bool {
        terminalLock.withLock {
            clearPreeditForPressLocked(eventType: eventType)
            var buffer = [UInt8](repeating: 0, count: 256)
            let count = associatedText.withUnsafeBufferPointer { associatedBuffer in
                cocxycore_terminal_encode_char_event(
                    terminal,
                    codepoint,
                    Self.cocxyModifiers(from: modifiers),
                    eventType,
                    shiftedCodepoint,
                    baseLayoutCodepoint,
                    associatedBuffer.baseAddress,
                    associatedBuffer.count,
                    &buffer,
                    buffer.count
                )
            }
            guard count > 0 else { return false }
            var encodedBytes = Array(buffer.prefix(count))
            if eventType != 3 {
                let scalars = characters.unicodeScalars.map(\.value)
                let hasControl = modifiers & (1 << 1) != 0
                let hasSuper = modifiers & (1 << 3) != 0
                let remainderStart: Int?
                if hasControl || hasSuper {
                    remainderStart = 1
                } else if scalars.count > 8 {
                    remainderStart = 8
                } else {
                    remainderStart = nil
                }
                if let remainderStart, scalars.count > remainderStart {
                    for scalar in scalars.dropFirst(remainderStart) {
                        if let unicodeScalar = UnicodeScalar(scalar) {
                            encodedBytes.append(contentsOf: String(unicodeScalar).utf8)
                        }
                    }
                }
            }
            return writeEncodedBytesLocked(encodedBytes)
        }
    }

    /// Maps Cocxy's modifier bitmask to CocxyCore's encoding.
    static func cocxyModifiers(from raw: UInt) -> UInt16 {
        var result: UInt16 = 0
        if raw & (1 << 0) != 0 { result |= 1 }
        if raw & (1 << 2) != 0 { result |= 2 }
        if raw & (1 << 1) != 0 { result |= 4 }
        if raw & (1 << 3) != 0 { result |= 8 }
        if raw & (1 << 4) != 0 { result |= 16 }
        if raw & (1 << 5) != 0 { result |= 32 }
        if raw & (1 << 6) != 0 { result |= 64 }
        if raw & (1 << 7) != 0 { result |= 128 }
        return result
    }

    private func clearPreeditForPressLocked(eventType: UInt8) {
        guard eventType != 3, cocxycore_terminal_preedit_active(terminal) else { return }
        cocxycore_terminal_preedit_clear(terminal)
    }

    private func writeEncodedBytesLocked(_ bytes: [UInt8]) -> Bool {
        guard bytes.isEmpty == false else { return false }
        return bytes.withUnsafeBufferPointer { pointer in
            cocxycore_terminal_write_attached_pty(
                terminal,
                pointer.baseAddress,
                pointer.count
            ) > 0
        }
    }
}
