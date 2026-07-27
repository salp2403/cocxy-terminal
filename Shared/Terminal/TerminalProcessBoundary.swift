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

    /// Grace granted to the child at each escalation step before the next
    /// signal is sent.
    ///
    /// The budgets are wall-clock, not attempt counts. `usleep` guarantees a
    /// floor and never a ceiling: on an idle Apple silicon Mac a
    /// `usleep(10_000)` costs ~17 ms because the sleep is coalesced onto the
    /// ~60 Hz timer, and once the process is demoted to background QoS the
    /// same call costs ~127 ms. A ladder counted in attempts therefore has no
    /// bounded duration at all, and callers that judge its outcome against a
    /// deadline of their own — `PTYDaemonSurface.close(waitForCleanup:)` does
    /// exactly that — start reporting a successful teardown as a failure the
    /// moment the machine is loaded. Polling until a deadline keeps the
    /// escalation at the intended 200/300/1000 ms regardless of timer slack.
    public static let hangupReapBudget: TimeInterval = 0.2
    public static let terminateReapBudget: TimeInterval = 0.3
    public static let killReapBudget: TimeInterval = 1.0

    /// Upper bound on `terminateAndReapPTYChild`, beyond which only a single
    /// poll interval of overshoot per escalation step is possible.
    public static let terminationBudget: TimeInterval =
        hangupReapBudget + terminateReapBudget + killReapBudget

    private static let reapPollIntervalMicroseconds: useconds_t = 10_000

    /// Terminates a direct `forkpty` child and reaps it within a bounded wait.
    /// The process group is signalled as well so child TUIs and pagers do not
    /// survive their owning terminal surface.
    /// - Parameter drainPendingOutput: Invoked on every poll while the child
    ///   is still running. A caller that owns the child's PTY must pass a
    ///   non-blocking drain here: once its own reader is gone, a child blocked
    ///   writing into a full PTY buffer can never finish exiting, so waiting
    ///   without draining deadlocks against the caller itself.
    public static func terminateAndReapPTYChild(
        _ pid: Int32,
        drainPendingOutput: (() -> Void)? = nil
    ) -> Bool {
        guard pid > 0 else { return true }
        if waitForReap(pid, within: 0, drainPendingOutput) { return true }

        signalProcessAndGroup(pid, signal: SIGHUP)
        if waitForReap(pid, within: hangupReapBudget, drainPendingOutput) { return true }

        signalProcessAndGroup(pid, signal: SIGTERM)
        if waitForReap(pid, within: terminateReapBudget, drainPendingOutput) { return true }

        signalProcessAndGroup(pid, signal: SIGKILL)
        return waitForReap(pid, within: killReapBudget, drainPendingOutput)
    }

    private enum WaitState {
        case running
        case reaped
        case failed
    }

    /// Polls `waitpid` until the child is reaped or `budget` elapses. A zero
    /// budget performs a single poll without sleeping.
    private static func waitForReap(
        _ pid: Int32,
        within budget: TimeInterval,
        _ drainPendingOutput: (() -> Void)?
    ) -> Bool {
        let deadline = DispatchTime.now() + budget
        while true {
            drainPendingOutput?()
            switch waitState(pid) {
            case .reaped:
                return true
            case .failed:
                return false
            case .running:
                guard DispatchTime.now() < deadline else { return false }
                usleep(reapPollIntervalMicroseconds)
            }
        }
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

    /// Signals the process group first so child TUIs and pagers go with the
    /// shell, then the process itself. Both results are discarded on purpose:
    /// the group call legitimately fails with `EPERM`/`ESRCH` once the group
    /// has drained, and `waitState` is the authority on whether the child is
    /// actually gone.
    private static func signalProcessAndGroup(_ pid: Int32, signal: Int32) {
        _ = Darwin.kill(-pid, signal)
        _ = Darwin.kill(pid, signal)
    }
}
