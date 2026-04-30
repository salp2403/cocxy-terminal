// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonSurface+Keys.swift - Key encoding for the daemon surface.

import CocxyCoreKit
import CocxyShared
import Foundation

extension PTYDaemonSurface {
    /// Encodes a CocxyCore special key (arrows, function keys, etc.) and
    /// writes the resulting bytes to the attached PTY.
    func writeEncodedKey(_ key: UInt8, modifiers: UInt) -> Bool {
        terminalLock.withLock {
            var buffer = [UInt8](repeating: 0, count: 64)
            let count = cocxycore_terminal_encode_key(
                terminal,
                key,
                Self.cocxyModifiers(from: modifiers),
                &buffer,
                buffer.count
            )
            guard count > 0 else { return false }
            return buffer.withUnsafeBufferPointer { pointer in
                cocxycore_terminal_write_attached_pty(terminal, pointer.baseAddress, count) > 0
            }
        }
    }

    /// Encodes a Unicode codepoint for the active terminal mode and writes
    /// the resulting bytes to the attached PTY.
    func writeEncodedCharacter(_ codepoint: UInt32, modifiers: UInt) -> Bool {
        terminalLock.withLock {
            var buffer = [UInt8](repeating: 0, count: 64)
            let count = cocxycore_terminal_encode_char(
                terminal,
                codepoint,
                Self.cocxyModifiers(from: modifiers),
                &buffer,
                buffer.count
            )
            guard count > 0 else { return false }
            return buffer.withUnsafeBufferPointer { pointer in
                cocxycore_terminal_write_attached_pty(terminal, pointer.baseAddress, count) > 0
            }
        }
    }

    /// Maps Cocxy's modifier bitmask to CocxyCore's encoding.
    static func cocxyModifiers(from raw: UInt) -> UInt8 {
        var result: UInt8 = 0
        if raw & (1 << 0) != 0 { result |= 1 }
        if raw & (1 << 2) != 0 { result |= 2 }
        if raw & (1 << 1) != 0 { result |= 4 }
        if raw & (1 << 3) != 0 { result |= 8 }
        return result
    }

    /// Maps a macOS hardware key code to CocxyCore's special-key id, or
    /// `nil` when the key code is a regular printable character.
    static func specialKey(forMacKeyCode code: UInt16) -> UInt8? {
        switch code {
        case 126: return 0
        case 125: return 1
        case 124: return 2
        case 123: return 3
        case 115: return 4
        case 119: return 5
        case 114: return 6
        case 117: return 7
        case 116: return 8
        case 121: return 9
        case 122: return 10
        case 120: return 11
        case 99: return 12
        case 118: return 13
        case 96: return 14
        case 97: return 15
        case 98: return 16
        case 100: return 17
        case 101: return 18
        case 109: return 19
        case 103: return 20
        case 111: return 21
        case 51: return 22
        case 48: return 23
        case 36: return 24
        case 53: return 25
        default: return nil
        }
    }
}
