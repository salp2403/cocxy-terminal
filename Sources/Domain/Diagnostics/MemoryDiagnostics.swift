// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MemoryDiagnostics.swift - Local process memory diagnostics for debug surfaces.

import Darwin
import Foundation

struct MemoryDiagnosticsSnapshot: Sendable, Equatable {
    let residentBytes: UInt64
    let virtualBytes: UInt64
    let physicalFootprintBytes: UInt64?
    let capturedAt: Date

    var formattedResident: String {
        MemoryDiagnostics.formatBytes(residentBytes)
    }

    var formattedVirtual: String {
        MemoryDiagnostics.formatBytes(virtualBytes)
    }

    var formattedPhysicalFootprint: String {
        physicalFootprintBytes.map(MemoryDiagnostics.formatBytes) ?? "Unavailable"
    }
}

enum MemoryDiagnostics {

    static func current(capturedAt: Date = Date()) -> MemoryDiagnosticsSnapshot {
        let basic = readBasicInfo()
        let physicalFootprint = readPhysicalFootprint()
        return MemoryDiagnosticsSnapshot(
            residentBytes: basic?.residentSize ?? 0,
            virtualBytes: basic?.virtualSize ?? 0,
            physicalFootprintBytes: physicalFootprint,
            capturedAt: capturedAt
        )
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        let mib = value / 1_048_576.0
        let gib = value / 1_073_741_824.0
        if gib >= 1 {
            return String(format: "%.2f GiB", gib)
        }
        return String(format: "%.1f MiB", mib)
    }

    private static func readBasicInfo() -> BasicInfo? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    intPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return BasicInfo(
            residentSize: UInt64(info.resident_size),
            virtualSize: UInt64(info.virtual_size)
        )
    }

    private static func readPhysicalFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    intPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }
}

private extension MemoryDiagnostics {
    struct BasicInfo: Sendable, Equatable {
        let residentSize: UInt64
        let virtualSize: UInt64
    }
}
