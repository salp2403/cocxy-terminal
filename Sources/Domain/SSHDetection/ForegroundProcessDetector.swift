// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ForegroundProcessDetector.swift - Detects the foreground process of a terminal PTY.

import Foundation
import Darwin

// MARK: - Foreground Process Info

/// Information about the current foreground process in a terminal.
struct ForegroundProcessInfo: Equatable, Sendable {
    /// The process name (e.g., "zsh", "ssh", "node").
    let name: String

    /// The full command line, if available.
    let command: String?

    /// The process ID.
    let pid: Int32
}

// MARK: - Foreground Process Detector

/// Detects the foreground process of a terminal's PTY on macOS.
///
/// ## macOS Implementation
///
/// On macOS, there is no `/proc` filesystem. This implementation uses `sysctl` exclusively:
/// 1. `sysctl` with `KERN_PROC_ALL` to enumerate child processes of the shell PID.
/// 2. `sysctl` with `KERN_PROC_PID` to look up the process name via `kp_proc.p_comm`.
/// 3. `sysctl` with `KERN_PROCARGS2` to retrieve the full command line.
///
/// ## Usage
///
/// The detector is called periodically (e.g., every 2 seconds) to check
/// if the foreground process has changed. When a change is detected,
/// the tab's `processName` and `sshSession` are updated.
///
/// - SeeAlso: `SSHSessionDetector` for parsing SSH commands.
/// - SeeAlso: `Tab.processName` for the display field.
enum ForegroundProcessDetector {

    struct ProcessSnapshot: Equatable, Sendable {
        let pid: pid_t
        let parentPID: pid_t
        let processGroupID: pid_t
        let name: String
    }

    /// Detects the foreground process for the given PID.
    ///
    /// - Parameter pid: The PID to query (typically the shell's PID).
    /// - Returns: Process info, or nil if detection failed.
    static func detect(shellPID: pid_t, ptyMasterFD: Int32? = nil) -> ForegroundProcessInfo? {
        let snapshots = processSnapshots() ?? []
        return detect(
            shellPID: shellPID,
            ptyMasterFD: ptyMasterFD,
            expectedShellIdentity: nil,
            snapshots: snapshots
        )
    }

    static func detect(
        shellPID: pid_t,
        ptyMasterFD: Int32? = nil,
        expectedShellIdentity: TerminalProcessIdentity? = nil,
        snapshots: [ProcessSnapshot]
    ) -> ForegroundProcessInfo? {
        if let expectedShellIdentity,
           processIdentity(for: shellPID) != expectedShellIdentity {
            return nil
        }

        guard let snapshot = selectForegroundProcess(
            shellPID: shellPID,
            ptyMasterFD: ptyMasterFD,
            snapshots: snapshots
        ) else {
            return nil
        }

        let command = processCommand(for: snapshot.pid)

        return ForegroundProcessInfo(
            name: snapshot.name,
            command: command,
            pid: snapshot.pid
        )
    }

    static func selectForegroundProcess(
        shellPID: pid_t,
        ptyMasterFD: Int32? = nil,
        snapshots: [ProcessSnapshot]
    ) -> ProcessSnapshot? {
        let foregroundPGID = foregroundProcessGroupID(
            shellPID: shellPID,
            ptyMasterFD: ptyMasterFD
        )
        return selectForegroundProcess(
            shellPID: shellPID,
            foregroundProcessGroupID: foregroundPGID,
            snapshots: snapshots
        )
    }

    static func selectForegroundProcess(
        shellPID: pid_t,
        foregroundProcessGroupID: pid_t?,
        snapshots: [ProcessSnapshot]
    ) -> ProcessSnapshot? {
        guard !snapshots.isEmpty else {
            guard let name = processName(for: shellPID) else { return nil }
            return ProcessSnapshot(
                pid: shellPID,
                parentPID: 0,
                processGroupID: foregroundProcessGroupID ?? shellPID,
                name: name
            )
        }

        let descendantPIDs = descendantProcessIDs(of: shellPID, in: snapshots)
        var candidates = snapshots.filter { snapshot in
            snapshot.pid == shellPID || descendantPIDs.contains(snapshot.pid)
        }

        guard !candidates.isEmpty else {
            return snapshots.first(where: { $0.pid == shellPID })
        }

        if let foregroundProcessGroupID, foregroundProcessGroupID > 0 {
            let foregroundCandidates = candidates.filter {
                $0.processGroupID == foregroundProcessGroupID
            }
            if !foregroundCandidates.isEmpty {
                candidates = foregroundCandidates
            }
        }

        return preferredProcess(
            from: candidates,
            shellPID: shellPID,
            foregroundProcessGroupID: foregroundProcessGroupID
        )
    }

    /// Gets the process name for a PID using sysctl.
    static func processName(for pid: pid_t) -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }

        // Extract the process name from kp_proc.p_comm.
        let name = withUnsafePointer(to: &info.kp_proc.p_comm) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { charPtr in
                String(cString: charPtr)
            }
        }

        return name.isEmpty ? nil : name
    }

    /// Gets the full command line for a PID using procargs.
    static func processCommand(for pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0

        // First call: get the buffer size.
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        // Second call: get the data.
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        // Parse the buffer: first 4 bytes = argc, then exec path, then args.
        guard size > MemoryLayout<Int32>.size else { return nil }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0 else { return nil }

        // Skip argc (4 bytes) and the exec path (null-terminated).
        var offset = MemoryLayout<Int32>.size

        // Skip exec path.
        while offset < size && buffer[offset] != 0 { offset += 1 }
        // Skip null terminators between exec path and first arg.
        while offset < size && buffer[offset] == 0 { offset += 1 }

        // Collect args.
        var args: [String] = []
        var currentArg = ""
        var argsCollected = 0

        while offset < size && argsCollected < argc {
            if buffer[offset] == 0 {
                args.append(currentArg)
                currentArg = ""
                argsCollected += 1
            } else {
                currentArg.append(Character(UnicodeScalar(buffer[offset])))
            }
            offset += 1
        }

        return args.isEmpty ? nil : args.joined(separator: " ")
    }

    /// Gets child processes of a PID using sysctl.
    static func childProcesses(of parentPID: pid_t) -> [pid_t]? {
        guard let snapshots = processSnapshots() else { return nil }
        let children = snapshots
            .filter { $0.parentPID == parentPID }
            .map(\.pid)
        return children.isEmpty ? nil : children
    }

    static func processSnapshots() -> [ProcessSnapshot]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size: Int = 0

        // Get size.
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else { return nil }

        let count = size / MemoryLayout<kinfo_proc>.stride
        guard count > 0 else { return nil }

        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0) == 0 else { return nil }

        let actualCount = size / MemoryLayout<kinfo_proc>.stride

        var snapshots: [ProcessSnapshot] = []
        snapshots.reserveCapacity(actualCount)
        for i in 0..<actualCount {
            let pid = procs[i].kp_proc.p_pid
            let name = withUnsafePointer(to: &procs[i].kp_proc.p_comm) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { charPtr in
                    String(cString: charPtr)
                }
            }
            snapshots.append(ProcessSnapshot(
                pid: pid,
                parentPID: procs[i].kp_eproc.e_ppid,
                processGroupID: procs[i].kp_eproc.e_pgid,
                name: name.isEmpty ? String(pid) : name
            ))
        }

        return snapshots
    }

    private static func foregroundProcessGroupID(
        shellPID: pid_t,
        ptyMasterFD: Int32?
    ) -> pid_t? {
        if let ptyMasterFD, ptyMasterFD >= 0 {
            let pgid = tcgetpgrp(ptyMasterFD)
            if pgid > 0 {
                return pgid
            }
        }

        guard let bsdInfo = processBSDInfo(for: shellPID) else { return nil }
        let ttyForegroundPGID = pid_t(bsdInfo.e_tpgid)
        return ttyForegroundPGID > 0 ? ttyForegroundPGID : nil
    }

    private static func processBSDInfo(for pid: pid_t) -> proc_bsdinfo? {
        guard pid > 0 else { return nil }

        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout.size(ofValue: info))
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expectedSize)
        guard result == expectedSize else { return nil }
        return info
    }

    static func processIdentity(for pid: pid_t) -> TerminalProcessIdentity? {
        guard let info = processBSDInfo(for: pid) else { return nil }
        return TerminalProcessIdentity(
            pid: pid,
            startSeconds: UInt64(info.pbi_start_tvsec),
            startMicroseconds: UInt64(info.pbi_start_tvusec)
        )
    }

    private static func descendantProcessIDs(
        of ancestorPID: pid_t,
        in snapshots: [ProcessSnapshot]
    ) -> Set<pid_t> {
        let childrenByParent = Dictionary(grouping: snapshots, by: \.parentPID)
        var pending: [pid_t] = [ancestorPID]
        var descendants: Set<pid_t> = []

        while let current = pending.popLast() {
            for child in childrenByParent[current] ?? [] where descendants.insert(child.pid).inserted {
                pending.append(child.pid)
            }
        }

        return descendants
    }

    private static func preferredProcess(
        from candidates: [ProcessSnapshot],
        shellPID: pid_t,
        foregroundProcessGroupID: pid_t?
    ) -> ProcessSnapshot? {
        let nonShellCandidates = candidates.filter { $0.pid != shellPID }

        if let foregroundProcessGroupID,
           let leader = nonShellCandidates.first(where: { $0.pid == foregroundProcessGroupID }) {
            return leader
        }

        if let nonShell = nonShellCandidates.max(by: { $0.pid < $1.pid }) {
            return nonShell
        }

        return candidates.first(where: { $0.pid == shellPID })
    }
}
