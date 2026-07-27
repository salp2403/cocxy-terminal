// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalProcessBoundary.swift - POSIX safety at terminal process boundaries.

import Darwin
import Foundation

public enum TerminalProcessBoundary {
    public static func setCloseOnExec(_ descriptor: Int32) -> Bool {
        let flags = fcntl(descriptor, F_GETFD)
        guard flags >= 0 else { return false }
        return fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC) == 0
    }

    public static func setNoSigPipe(_ descriptor: Int32) -> Bool {
        fcntl(descriptor, F_SETNOSIGPIPE, 1) == 0
    }

    public static func setNonBlocking(_ descriptor: Int32) -> Bool {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0 else { return false }
        return fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0
    }

    public static func writeAll(
        _ data: Data,
        to descriptor: Int32,
        maximumWaitMilliseconds: Int32 = 0
    ) -> Bool {
        guard data.isEmpty == false else { return true }
        let waitMilliseconds = max(0, maximumWaitMilliseconds)
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let deadline = startedAt &+ UInt64(waitMilliseconds) * 1_000_000

        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return false }
            var offset = 0
            while offset < rawBuffer.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if result > 0 {
                    offset += result
                    continue
                }
                if result == -1, errno == EINTR {
                    continue
                }
                if result == -1, (errno == EAGAIN || errno == EWOULDBLOCK),
                   waitUntilWritable(descriptor, deadline: deadline) {
                    continue
                }
                return false
            }
            return true
        }
    }

    private static func waitUntilWritable(_ descriptor: Int32, deadline: UInt64) -> Bool {
        var pollDescriptor = pollfd(
            fd: descriptor,
            events: Int16(POLLOUT | POLLHUP | POLLERR),
            revents: 0
        )
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard deadline > now else { return false }
            let remainingNanoseconds = deadline - now
            let remainingMilliseconds = Int32(
                min(UInt64(Int32.max), max(1, remainingNanoseconds / 1_000_000))
            )
            pollDescriptor.revents = 0
            let result = Darwin.poll(&pollDescriptor, 1, remainingMilliseconds)
            if result > 0 {
                return pollDescriptor.revents & Int16(POLLOUT) != 0
            }
            if result == -1, errno == EINTR { continue }
            return false
        }
    }

    /// Terminates a direct `forkpty` child and reaps it within a bounded wait.
    /// The process group is signalled as well so child TUIs and pagers do not
    /// survive their owning terminal surface.
    public static func terminateAndReapPTYChild(_ pid: Int32) -> Bool {
        guard pid > 0 else { return true }
        if waitForReap(pid, attempts: 1, delayMicroseconds: 0) { return true }

        signalProcessAndGroup(pid, signal: SIGHUP)
        if waitForReap(pid, attempts: 21, delayMicroseconds: 10_000) { return true }

        signalProcessAndGroup(pid, signal: SIGTERM)
        if waitForReap(pid, attempts: 31, delayMicroseconds: 10_000) { return true }

        signalProcessAndGroup(pid, signal: SIGKILL)
        return waitForReap(pid, attempts: 101, delayMicroseconds: 10_000)
    }

    private enum WaitState {
        case running
        case reaped
        case failed
    }

    private static func waitForReap(
        _ pid: Int32,
        attempts: Int,
        delayMicroseconds: useconds_t
    ) -> Bool {
        for attempt in 0..<max(1, attempts) {
            switch waitState(pid) {
            case .reaped:
                return true
            case .failed:
                return false
            case .running:
                if delayMicroseconds > 0, attempt + 1 < attempts {
                    usleep(delayMicroseconds)
                }
            }
        }
        return false
    }

    private static func waitState(_ pid: Int32) -> WaitState {
        var status: Int32 = 0
        while true {
            let result = Darwin.waitpid(pid, &status, WNOHANG)
            if result == pid { return .reaped }
            if result == 0 { return .running }
            if result == -1, errno == EINTR { continue }
            if result == -1, errno == ECHILD { return .reaped }
            return .failed
        }
    }

    private static func signalProcessAndGroup(_ pid: Int32, signal: Int32) {
        _ = Darwin.kill(-pid, signal)
        _ = Darwin.kill(pid, signal)
    }
}
