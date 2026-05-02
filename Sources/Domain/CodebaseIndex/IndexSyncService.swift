// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// IndexSyncService.swift - Incremental file-change sync for codebase indexing.

import Darwin
import Foundation

struct CodebaseIndexChangeSet: Sendable, Equatable {
    let changedFiles: [String]
    let removedFiles: [String]
    let snapshot: CodebaseMerkleSnapshot

    var isEmpty: Bool {
        changedFiles.isEmpty && removedFiles.isEmpty
    }
}

final class CodebaseIndexSyncService {
    typealias ChangeHandler = (CodebaseIndexChangeSet) -> Void

    private let workspace: AgentWorkspace
    private let builder: CodebaseMerkleTreeBuilder
    private let queue: DispatchQueue
    private let onChange: ChangeHandler
    private let lock = NSLock()

    private var currentSnapshot: CodebaseMerkleSnapshot?
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1

    init(
        workspace: AgentWorkspace,
        maxFileBytes: Int = 1_000_000,
        queue: DispatchQueue = DispatchQueue(label: "dev.cocxy.codebase-index.sync"),
        onChange: @escaping ChangeHandler = { _ in }
    ) {
        self.workspace = workspace
        self.builder = CodebaseMerkleTreeBuilder(workspace: workspace, maxFileBytes: maxFileBytes)
        self.queue = queue
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    @discardableResult
    func refresh() throws -> CodebaseIndexChangeSet {
        let nextSnapshot = try builder.snapshot()
        lock.lock()
        let previousSnapshot = currentSnapshot
        currentSnapshot = nextSnapshot
        lock.unlock()

        return CodebaseIndexChangeSet(
            changedFiles: nextSnapshot.changedFiles(comparedTo: previousSnapshot),
            removedFiles: previousSnapshot.map { nextSnapshot.removedFiles(comparedTo: $0) } ?? [],
            snapshot: nextSnapshot
        )
    }

    func prime() throws {
        _ = try refresh()
    }

    @discardableResult
    func handleFileSystemEvent() throws -> CodebaseIndexChangeSet {
        let changeSet = try refresh()
        if !changeSet.isEmpty {
            onChange(changeSet)
        }
        return changeSet
    }

    func start() throws {
        guard source == nil else { return }
        try prime()

        let descriptor = open(workspace.rootURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw CocoaError(.fileNoSuchFile)
        }
        fileDescriptor = descriptor

        let eventSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend],
            queue: queue
        )
        eventSource.setEventHandler { [weak self] in
            guard let self else { return }
            _ = try? self.handleFileSystemEvent()
        }
        eventSource.setCancelHandler {
            close(descriptor)
        }
        source = eventSource
        eventSource.resume()
    }

    func stop() {
        guard let source else { return }
        self.source = nil
        fileDescriptor = -1
        source.cancel()
    }
}
