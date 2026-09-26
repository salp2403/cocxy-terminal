// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorTLSKeychainOwnership.swift - Relay key ownership across app and boot sessions.

import Darwin
import Foundation

enum MobileMirrorTLSKeychainOwnership {
    static let keyTagPrefix = "dev.cocxy.mobile.tls."

    enum Owner: Equatable {
        case session(bootIdentifier: String, processIdentifier: pid_t)
        case legacyProcess(processIdentifier: pid_t)
        case legacy
    }

    /// Validity of the certificate paired with a tagged key. Tags written before
    /// boot sessions carry no boot identity, so their certificate is the only
    /// record of when they were created.
    struct Timeline: Equatable {
        /// Every relay certificate is back-dated by this interval.
        static let certificateBackdate: TimeInterval = 300

        let notBefore: Date
        let notAfter: Date

        /// Latest instant the identity can have been created; UTCTime keeps
        /// whole seconds, so the back-dated start is at most one second early.
        var latestCreation: Date {
            notBefore.addingTimeInterval(Self.certificateBackdate + 1)
        }

        func ownerCannotBeRunning(bootTime: Date?, now: Date) -> Bool {
            if notAfter <= now { return true }
            guard let bootTime else { return false }
            return latestCreation < bootTime
        }
    }

    static func currentBootSessionIdentifier() -> String? {
        guard let identity = try? LaunchdBootIdentity.current(),
              let sessionUUID = identity.sessionUUID else {
            return nil
        }
        return sessionUUID
    }

    static func storageIdentifier(
        bootSessionIdentifier: String,
        ownerProcessIdentifier: pid_t,
        identityIdentifier: UUID
    ) -> String? {
        guard ownerProcessIdentifier > 0,
              let bootUUID = UUID(uuidString: bootSessionIdentifier) else {
            return nil
        }
        return [
            "v3",
            bootUUID.uuidString.lowercased(),
            String(ownerProcessIdentifier),
            identityIdentifier.uuidString.lowercased(),
        ].joined(separator: ".")
    }

    static func owner(from tag: String) -> Owner? {
        guard tag.hasPrefix(keyTagPrefix) else { return nil }
        let components = tag.dropFirst(keyTagPrefix.count).split(separator: ".")
        if components.count == 4,
           components[0] == "v3",
           let bootUUID = UUID(uuidString: String(components[1])),
           let processIdentifier = pid_t(components[2]),
           processIdentifier > 0,
           UUID(uuidString: String(components[3])) != nil {
            return .session(
                bootIdentifier: bootUUID.uuidString.lowercased(),
                processIdentifier: processIdentifier
            )
        }
        if components.count == 3,
           components[0] == "v2",
           let processIdentifier = pid_t(components[1]),
           processIdentifier > 0,
           UUID(uuidString: String(components[2])) != nil {
            return .legacyProcess(processIdentifier: processIdentifier)
        }
        if components.count == 1, UUID(uuidString: String(components[0])) != nil {
            return .legacy
        }
        return nil
    }

    static func shouldRemove(
        owner: Owner,
        timeline: Timeline?,
        currentBootSessionIdentifier: String?,
        bootTime: Date?,
        now: Date,
        processIsAlive: (pid_t) -> Bool,
        processStartTime: (pid_t) -> Date?
    ) -> Bool {
        switch owner {
        case let .session(bootIdentifier, processIdentifier):
            guard let currentBootSessionIdentifier else { return false }
            return bootIdentifier != currentBootSessionIdentifier.lowercased()
                || !processIsAlive(processIdentifier)
        case let .legacyProcess(processIdentifier):
            guard processIsAlive(processIdentifier) else { return true }
            guard let timeline else { return false }
            if timeline.ownerCannotBeRunning(bootTime: bootTime, now: now) { return true }
            guard let startedAt = processStartTime(processIdentifier) else { return false }
            return startedAt > timeline.latestCreation
        case .legacy:
            // Without a certificate the key cannot back a TLS identity for anyone.
            guard let timeline else { return true }
            return timeline.ownerCannotBeRunning(bootTime: bootTime, now: now)
        }
    }

    static func currentBootTime() -> Date? {
        guard let boot = try? LaunchdBootIdentity.currentLegacyBootTime(),
              let seconds = boot.legacySeconds,
              let microseconds = boot.legacyMicroseconds else {
            return nil
        }
        return Date(
            timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(microseconds) / 1_000_000
        )
    }

    static func processStartTime(_ processIdentifier: pid_t) -> Date? {
        guard processIdentifier > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var managementInformationBase: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processIdentifier]
        guard sysctl(
            &managementInformationBase,
            u_int(managementInformationBase.count),
            &info,
            &size,
            nil,
            0
        ) == 0, size == MemoryLayout<kinfo_proc>.stride,
              info.kp_proc.p_pid == processIdentifier else {
            return nil
        }
        let start = info.kp_proc.p_un.__p_starttime
        guard start.tv_sec > 0 else { return nil }
        return Date(
            timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000
        )
    }
}
