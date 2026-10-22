// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorApprovalRegistry.swift - App-scoped pending approval rendezvous.

import Combine
import Foundation

struct MobileMirrorApprovalRecord: Equatable, Identifiable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case agentTool = "agent-tool"
        case orchestrationLease = "orchestration-lease"
    }

    let id: String
    let kind: Kind
    let sessionID: String
    let title: String
    let body: String
    let requiresResponse: Bool
    let expiresAt: Date?
}

enum MobileMirrorApprovalDecision: Equatable, Sendable {
    case approve(response: String?)
    case reject
}

@MainActor
final class MobileMirrorApprovalRegistry: ObservableObject {
    typealias CurrentPredicate = @MainActor () -> Bool
    typealias Resolver = @MainActor (MobileMirrorApprovalDecision) async -> Bool

    private struct Target {
        let record: MobileMirrorApprovalRecord
        let isCurrent: CurrentPredicate
        let resolve: Resolver
        var isResolving: Bool
    }

    @MainActor
    private final class ResolutionClaimGate {
        var isConsumed = false
    }

    @MainActor
    struct ResolutionClaim {
        let record: MobileMirrorApprovalRecord
        private let gate: ResolutionClaimGate
        fileprivate let executeResolution: @MainActor () async -> Bool
        fileprivate let cancelResolution: @MainActor () -> Void

        fileprivate init(
            record: MobileMirrorApprovalRecord,
            executeResolution: @escaping @MainActor () async -> Bool,
            cancelResolution: @escaping @MainActor () -> Void
        ) {
            self.record = record
            self.gate = ResolutionClaimGate()
            self.executeResolution = executeResolution
            self.cancelResolution = cancelResolution
        }

        func execute() async -> Bool {
            guard !gate.isConsumed else { return false }
            gate.isConsumed = true
            return await executeResolution()
        }

        func cancel() {
            guard !gate.isConsumed else { return }
            gate.isConsumed = true
            cancelResolution()
        }
    }

    @Published private(set) var records: [MobileMirrorApprovalRecord] = []
    private var targetsBySourceID: [String: Target] = [:]

    @discardableResult
    func register(
        sourceID: String,
        record: MobileMirrorApprovalRecord,
        isCurrent: @escaping CurrentPredicate,
        resolve: @escaping Resolver
    ) -> Bool {
        guard Self.isValid(sourceID: sourceID, record: record, at: Date()),
              isCurrent() else {
            remove(sourceID: sourceID)
            return false
        }
        guard targetsBySourceID[sourceID]?.isResolving != true,
              !targetsBySourceID.values.contains(where: {
                  $0.record.id == record.id && $0.isResolving
              }) else {
            return false
        }
        let duplicateSourceIDs = targetsBySourceID.compactMap { otherSourceID, target in
            otherSourceID != sourceID && target.record.id == record.id ? otherSourceID : nil
        }
        for otherSourceID in duplicateSourceIDs {
            targetsBySourceID.removeValue(forKey: otherSourceID)
        }
        targetsBySourceID[sourceID] = Target(
            record: record,
            isCurrent: isCurrent,
            resolve: resolve,
            isResolving: false
        )
        publishRecords()
        return true
    }

    func remove(sourceID: String) {
        guard targetsBySourceID.removeValue(forKey: sourceID) != nil else { return }
        publishRecords()
    }

    func currentRecords(at date: Date = Date()) -> [MobileMirrorApprovalRecord] {
        prune(at: date)
        return records
    }

    func resolve(
        id: String,
        decision: MobileMirrorApprovalDecision,
        at date: Date = Date()
    ) async -> Bool {
        guard let claim = claimResolution(id: id, decision: decision, at: date) else {
            return false
        }
        return await claim.execute()
    }

    func claimResolution(
        id: String,
        decision: MobileMirrorApprovalDecision,
        at date: Date = Date()
    ) -> ResolutionClaim? {
        prune(at: date)
        guard let sourceID = targetsBySourceID.first(where: { $0.value.record.id == id })?.key,
              var target = targetsBySourceID[sourceID],
              !target.isResolving,
              target.isCurrent() else {
            return nil
        }
        target.isResolving = true
        targetsBySourceID[sourceID] = target
        publishRecords()

        return ResolutionClaim(
            record: target.record,
            executeResolution: { [weak self] in
                let resolved = await target.resolve(decision)
                self?.finishResolution(
                    sourceID: sourceID,
                    recordID: id,
                    resolved: resolved
                )
                return resolved
            },
            cancelResolution: { [weak self] in
                self?.cancelResolution(sourceID: sourceID, recordID: id)
            }
        )
    }

    private func finishResolution(
        sourceID: String,
        recordID: String,
        resolved: Bool
    ) {
        guard let current = targetsBySourceID[sourceID],
              current.record.id == recordID,
              current.isResolving else { return }
        if resolved || !current.isCurrent() {
            targetsBySourceID.removeValue(forKey: sourceID)
        } else {
            var retryable = current
            retryable.isResolving = false
            targetsBySourceID[sourceID] = retryable
        }
        publishRecords()
    }

    private func cancelResolution(sourceID: String, recordID: String) {
        guard var current = targetsBySourceID[sourceID],
              current.record.id == recordID,
              current.isResolving else { return }
        if current.isCurrent() {
            current.isResolving = false
            targetsBySourceID[sourceID] = current
        } else {
            targetsBySourceID.removeValue(forKey: sourceID)
        }
        publishRecords()
    }

    private func prune(at date: Date) {
        let staleSourceIDs = targetsBySourceID.compactMap { sourceID, target in
            let expired = target.record.expiresAt.map { $0 <= date } ?? false
            return expired || !target.isCurrent() ? sourceID : nil
        }
        guard !staleSourceIDs.isEmpty else { return }
        for sourceID in staleSourceIDs {
            targetsBySourceID.removeValue(forKey: sourceID)
        }
        publishRecords()
    }

    private func publishRecords() {
        let updated = targetsBySourceID.values
            .filter { !$0.isResolving }
            .map(\.record)
            .sorted { $0.id < $1.id }
        if updated != records {
            records = updated
        }
    }

    private static func isValid(
        sourceID: String,
        record: MobileMirrorApprovalRecord,
        at date: Date
    ) -> Bool {
        !sourceID.isEmpty
            && sourceID.utf8.count <= 256
            && !record.id.isEmpty
            && record.id.utf8.count <= 128
            && UUID(uuidString: record.sessionID) != nil
            && !record.title.isEmpty
            && record.title.utf8.count <= 1_024
            && record.body.utf8.count <= 64 * 1_024
            && (record.expiresAt.map { $0 > date } ?? true)
    }
}
