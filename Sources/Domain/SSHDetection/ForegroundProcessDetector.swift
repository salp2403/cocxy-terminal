// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ForegroundProcessDetector.swift - Detects the foreground process of a terminal PTY.

import Foundation

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

    /// Detects the foreground process for the given PID.
    ///
    /// - Parameter pid: The PID to query (typically the shell's PID).
    /// - Returns: Process info, or nil if detection failed.
    static func detect(shellPID: pid_t) -> ForegroundProcessInfo? {
        // Get the foreground process group of the shell's controlling terminal.
        // On macOS, we use sysctl to find child processes.
        guard let childPIDs = childProcesses(of: shellPID) else { return nil }

        // The foreground process is typically the last child.
        // If no children, the shell itself is the foreground process.
        let targetPID = childPIDs.last ?? shellPID

        guard let name = processName(for: targetPID) else { return nil }

        let command = processCommand(for: targetPID)

        return ForegroundProcessInfo(
            name: name,
            command: command,
            pid: targetPID
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
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size: Int = 0

        // Get size.
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else { return nil }

        let count = size / MemoryLayout<kinfo_proc>.stride
        guard count > 0 else { return nil }

        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0) == 0 else { return nil }

        let actualCount = size / MemoryLayout<kinfo_proc>.stride

        var children: [pid_t] = []
        for i in 0..<actualCount {
            if procs[i].kp_eproc.e_ppid == parentPID {
                children.append(procs[i].kp_proc.p_pid)
            }
        }

        return children.isEmpty ? nil : children
    }
}
