// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonSurface+Spawn.swift - PTY spawn helpers with scoped env mutation.

import CocxyCoreKit
import CocxyShared
#if canImport(Darwin)
import Darwin
#endif
import Foundation

extension PTYDaemonSurface {
    /// Forks a new PTY child shell. Mutates global cwd/env state under
    /// `spawnEnvironmentLock` and restores it before returning so the rest
    /// of the daemon process is undisturbed.
    static func spawnPTY(
        rows: UInt16,
        columns: UInt16,
        shell: String,
        workingDirectory: String
    ) -> OpaquePointer? {
        spawnEnvironmentLock.lock()
        defer { spawnEnvironmentLock.unlock() }

        let previousCwd = FileManager.default.currentDirectoryPath
        let previousTERM = getenvString("TERM")
        let previousCOLORTERM = getenvString("COLORTERM")
        let previousTermProgram = getenvString("TERM_PROGRAM")
        let previousCLICOLOR = getenvString("CLICOLOR")
        // Snapshot keys that the daemon strips so they can be restored after
        // spawn. Mirrors CocxyCoreBridge's policy: downstream agent TUIs
        // lose their brand colours when a host `NO_COLOR=1` reaches the
        // child shell. The shared list lives in TerminalSpawnEnvironment.
        let previousUnsetKeys: [String: String?] = TerminalSpawnEnvironment.keysToUnset
            .reduce(into: [:]) { result, key in
                result[key] = getenvString(key)
            }

        _ = FileManager.default.changeCurrentDirectoryPath(workingDirectory)
        setenv("TERM", "xterm-256color", 1)
        setenv("COLORTERM", "truecolor", 1)
        setenv("TERM_PROGRAM", "CocxyTerminal", 1)
        setenv("CLICOLOR", "1", 1)
        for key in TerminalSpawnEnvironment.keysToUnset {
            unsetenv(key)
        }

        defer {
            restoreEnv("TERM", previousTERM)
            restoreEnv("COLORTERM", previousCOLORTERM)
            restoreEnv("TERM_PROGRAM", previousTermProgram)
            restoreEnv("CLICOLOR", previousCLICOLOR)
            for (key, value) in previousUnsetKeys {
                restoreEnv(key, value)
            }
            _ = FileManager.default.changeCurrentDirectoryPath(previousCwd)
        }

        return shell.withCString { cocxycore_pty_spawn(rows, columns, $0) }
    }

    static func getenvString(_ key: String) -> String? {
        getenv(key).map { String(cString: $0) }
    }

    static func restoreEnv(_ key: String, _ value: String?) {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }
}
