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
        prune(at: date)
        guard let sourceID = targetsBySourceID.first(where: { $0.value.record.id == id })?.key,
              var target = targetsBySourceID[sourceID],
              !target.isResolving,
              target.isCurrent() else {
            return false
        }
        target.isResolving = true
        targetsBySourceID[sourceID] = target

        let resolved = await target.resolve(decision)
        guard let current = targetsBySourceID[sourceID], current.record.id == id else {
            return resolved
        }
        if resolved || !current.isCurrent() {
            targetsBySourceID.removeValue(forKey: sourceID)
        } else {
            var retryable = current
            retryable.isResolving = false
            targetsBySourceID[sourceID] = retryable
        }
        publishRecords()
        return resolved
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
