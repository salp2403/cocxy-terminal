// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalSpawnEnvironment.swift - Shared environment policy for PTY spawning.

import Foundation

/// Environment variables inherited from the host process that must NOT leak
/// into PTY child shells.
///
/// Some interactive CLI agents propagate `NO_COLOR=1` to disable colours in
/// their own host-side rendering. If Cocxy forwards that variable to user
/// shells unchanged, downstream agent TUIs intentionally drop their brand
/// or accent colours even though the terminal supports truecolor. Both the
/// in-process bridge and the out-of-process daemon helper strip these keys
/// before spawning so the host inheritance stays transparent to the user.
public enum TerminalSpawnEnvironment {
    /// Keys that must be unset in the child PTY environment.
    public static let keysToUnset: Set<String> = ["NO_COLOR"]
}
