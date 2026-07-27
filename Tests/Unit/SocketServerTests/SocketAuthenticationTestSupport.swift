// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
@testable import CocxyTerminal

final class TestSocketAuthenticationStore: SocketAuthenticationStoring, @unchecked Sendable {
    private struct Entry {
        let token: String
        let record: SocketAuthenticationRecord
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var pathsByRecord: [SocketAuthenticationRecord: String] = [:]
    private(set) var deletedPaths: Set<String> = []
    var failSave = false

    func save(token: String, socketPath: String) throws -> SocketAuthenticationRecord {
        if failSave {
            throw TestSocketAuthenticationStoreError.saveRejected
        }
        let record = SocketAuthenticationRecord(
            account: UUID().uuidString,
            socketPath: socketPath
        )
        return lock.withLock {
            if let previous = entries[socketPath] {
                pathsByRecord.removeValue(forKey: previous.record)
            }
            entries[socketPath] = Entry(token: token, record: record)
            pathsByRecord[record] = socketPath
            deletedPaths.remove(socketPath)
            return record
        }
    }

    func delete(record: SocketAuthenticationRecord) throws {
        lock.withLock {
            guard let socketPath = pathsByRecord.removeValue(forKey: record),
                  entries[socketPath]?.record == record
            else {
                return
            }
            entries.removeValue(forKey: socketPath)
            deletedPaths.insert(socketPath)
        }
    }

    func token(for socketPath: String) -> String? {
        lock.withLock { entries[socketPath]?.token }
    }

    func wasDeleted(_ socketPath: String) -> Bool {
        lock.withLock { deletedPaths.contains(socketPath) }
    }
}

enum TestSocketAuthenticationStoreError: Error {
    case saveRejected
}
