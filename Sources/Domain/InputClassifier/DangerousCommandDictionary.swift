// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

public struct DangerousCommandDictionary: Sendable, Equatable {
    public static let `default` = DangerousCommandDictionary()

    public init() {}

    public func match(_ input: String) -> DangerousCommandMatch? {
        let normalized = ShellInputRecognizer.normalized(input).lowercased()
        guard !normalized.isEmpty else { return nil }

        let checks: [DangerousCommandMatch?] = [
            rootDeletionMatch(in: normalized),
            diskEraseMatch(in: normalized),
            rawDiskWriteMatch(in: normalized),
            filesystemCreationMatch(in: normalized),
            forkBombMatch(in: normalized),
            barePrivilegeShellMatch(in: normalized),
        ]

        return checks
            .compactMap { $0 }
            .max { $0.severity < $1.severity }
    }

    private func rootDeletionMatch(in input: String) -> DangerousCommandMatch? {
        let tokens = tokenize(input)
        guard let rmIndex = tokens.firstIndex(where: { $0 == "rm" || $0.hasSuffix("/rm") }) else {
            return nil
        }

        let trailing = tokens.dropFirst(rmIndex + 1)
        let flags = trailing
            .prefix { $0.hasPrefix("-") }
            .joined()
        guard flags.contains("r"), flags.contains("f") else {
            return nil
        }

        let targets = trailing.drop { $0.hasPrefix("-") }
        let rootTargets: Set<String> = ["/", "/*", "/.", "/..", "~", "~/", "~/*", "$home", "$home/"]
        guard targets.contains(where: { rootTargets.contains($0) }) else {
            return nil
        }

        return DangerousCommandMatch(
            severity: .critical,
            reason: "Recursive forced deletion targets the root filesystem or home directory.",
            matchedPattern: "rm -rf root"
        )
    }

    private func diskEraseMatch(in input: String) -> DangerousCommandMatch? {
        guard input.contains("diskutil erasedisk") || input.contains("diskutil erasevolume") else {
            return nil
        }
        return DangerousCommandMatch(
            severity: .critical,
            reason: "Disk erase command can destroy a full volume.",
            matchedPattern: "diskutil erase"
        )
    }

    private func rawDiskWriteMatch(in input: String) -> DangerousCommandMatch? {
        guard input.contains("dd "), input.contains("of=/dev/disk") || input.contains("of=/dev/rdisk") else {
            return nil
        }
        return DangerousCommandMatch(
            severity: .critical,
            reason: "Raw disk write can overwrite a physical disk.",
            matchedPattern: "dd of=/dev/disk"
        )
    }

    private func filesystemCreationMatch(in input: String) -> DangerousCommandMatch? {
        let tokens = tokenize(input)
        guard tokens.contains(where: { token in
            token == "mkfs" || token.hasPrefix("mkfs.") || token.hasPrefix("newfs")
        }) else {
            return nil
        }
        return DangerousCommandMatch(
            severity: .high,
            reason: "Filesystem creation command can destroy existing data on a device.",
            matchedPattern: "mkfs/newfs"
        )
    }

    private func forkBombMatch(in input: String) -> DangerousCommandMatch? {
        guard input.contains(":(){") || input.contains(":(){ :|:& };:") else {
            return nil
        }
        return DangerousCommandMatch(
            severity: .critical,
            reason: "Fork bomb pattern can exhaust local process resources.",
            matchedPattern: "fork bomb"
        )
    }

    private func barePrivilegeShellMatch(in input: String) -> DangerousCommandMatch? {
        let normalized = ShellInputRecognizer.normalized(input)
        guard normalized == "sudo su" || normalized == "sudo -s" || normalized == "sudo -i" else {
            return nil
        }
        return DangerousCommandMatch(
            severity: .medium,
            reason: "Interactive privileged shell should be confirmed before execution.",
            matchedPattern: "sudo shell"
        )
    }

    private func tokenize(_ input: String) -> [String] {
        input
            .replacingOccurrences(of: "&&", with: " ")
            .replacingOccurrences(of: "||", with: " ")
            .replacingOccurrences(of: ";", with: " ")
            .split(separator: " ")
            .map {
                String($0).trimmingCharacters(
                    in: CharacterSet(charactersIn: "\"'")
                )
            }
    }
}
