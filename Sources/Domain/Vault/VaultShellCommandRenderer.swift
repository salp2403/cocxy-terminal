// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultShellCommandRenderer.swift - Safe shell text for terminal resume commands.

import Foundation

public enum VaultShellCommandRenderer {
    public static func command(for invocation: VaultResumeInvocation) -> String {
        ([invocation.executable] + invocation.arguments)
            .map(shellQuoted)
            .joined(separator: " ")
    }

    public static func commandLine(for invocation: VaultResumeInvocation) -> String {
        command(for: invocation) + "\r"
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
