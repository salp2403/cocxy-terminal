// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TreeSitterHighlightQueryAdapter.swift - Tree-sitter query cursor bridge for highlights.scm captures.

import Darwin
import CocxyTreeSitterABI
import Foundation

enum TreeSitterHighlightQueryAdapterError: Error, Equatable {
    case languageUnavailable(languageID: String)
    case queryCompilationFailed(languageID: String, offset: UInt32, errorType: UInt32)
    case cursorAllocationFailed(languageID: String)
    case treeClosed(languageID: String)
    case missingRootNode(languageID: String)
}

struct TreeSitterRawQueryCapture: Equatable {
    var node: TreeSitterRawNode
    var index: UInt32
}

struct TreeSitterHighlightQueryAdapter {
    struct Functions {
        var languageFromEntryPoint: (UnsafeMutableRawPointer) -> UnsafeRawPointer?
        var createQuery: (
            UnsafeRawPointer,
            UnsafePointer<CChar>,
            UInt32,
            UnsafeMutablePointer<UInt32>,
            UnsafeMutablePointer<CocxyTreeSitterQueryError>
        ) -> UnsafeMutableRawPointer?
        var deleteQuery: (UnsafeMutableRawPointer) -> Void
        var createCursor: () -> UnsafeMutableRawPointer?
        var deleteCursor: (UnsafeMutableRawPointer) -> Void
        var exec: (UnsafeMutableRawPointer, UnsafeMutableRawPointer, TreeSitterRawNode) -> Void
        var setByteRange: ((UnsafeMutableRawPointer, UInt32, UInt32) -> Bool)? = nil
        var setContainingByteRange: ((UnsafeMutableRawPointer, UInt32, UInt32) -> Bool)? = nil
        var setMatchLimit: ((UnsafeMutableRawPointer, UInt32) -> Void)? = nil
        var nextCapture: (UnsafeMutableRawPointer) -> TreeSitterRawQueryCapture?
        var captureName: (UnsafeMutableRawPointer, UInt32) -> String?
        var rootNode: (UnsafeMutableRawPointer) -> TreeSitterRawNode
        var nodeStartPoint: (TreeSitterRawNode) -> TreeSitterRawPoint
        var nodeEndPoint: (TreeSitterRawNode) -> TreeSitterRawPoint
    }

    typealias LookupSymbol = (String) -> UnsafeMutableRawPointer?

    private typealias CLanguageEntryPoint = @convention(c) () -> UnsafeRawPointer?
    private typealias CQueryNew = @convention(c) (
        UnsafeRawPointer?,
        UnsafePointer<CChar>?,
        UInt32,
        UnsafeMutablePointer<UInt32>?,
        UnsafeMutablePointer<CocxyTreeSitterQueryError>?
    ) -> UnsafeMutableRawPointer?
    private typealias CQueryDelete = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias CQueryCaptureName =
        @convention(c) (UnsafeMutableRawPointer?, UInt32, UnsafeMutablePointer<UInt32>?) -> UnsafePointer<CChar>?
    private typealias CQueryCursorNew = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias CQueryCursorDelete = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias CQueryCursorExec =
        @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, CocxyTreeSitterNode) -> Void
    private typealias CQueryCursorSetByteRange = @convention(c) (UnsafeMutableRawPointer?, UInt32, UInt32) -> Bool
    private typealias CQueryCursorSetMatchLimit = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> Void
    private typealias CQueryCursorNextCapture = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<CocxyTreeSitterQueryMatch>?,
        UnsafeMutablePointer<UInt32>?
    ) -> Bool
    private typealias CTreeRootNode = @convention(c) (UnsafeMutableRawPointer?) -> CocxyTreeSitterNode
    private typealias CNodePoint = @convention(c) (CocxyTreeSitterNode) -> CocxyTreeSitterPoint

    private let functions: Functions
    private let retainedObjects: [AnyObject]
    private let queryCache: TreeSitterHighlightQueryCache

    init(
        functions: Functions,
        retainedObjects: [AnyObject] = [],
        queryCache: TreeSitterHighlightQueryCache = TreeSitterHighlightQueryCache()
    ) {
        self.functions = functions
        self.retainedObjects = retainedObjects
        self.queryCache = queryCache
    }

    static func resolve(
        lookupSymbol: LookupSymbol = TreeSitterRuntimeAdapter.defaultLookupSymbol,
        retainedObjects: [AnyObject] = []
    ) -> TreeSitterHighlightQueryAdapter? {
        guard let queryNewSymbol = lookupSymbol("ts_query_new") else { return nil }
        guard let queryDeleteSymbol = lookupSymbol("ts_query_delete") else { return nil }
        guard let queryCaptureNameSymbol = lookupSymbol("ts_query_capture_name_for_id") else { return nil }
        guard let cursorNewSymbol = lookupSymbol("ts_query_cursor_new") else { return nil }
        guard let cursorDeleteSymbol = lookupSymbol("ts_query_cursor_delete") else { return nil }
        guard let cursorExecSymbol = lookupSymbol("ts_query_cursor_exec") else { return nil }
        let cursorSetByteRangeSymbol = lookupSymbol("ts_query_cursor_set_byte_range")
        let cursorSetContainingByteRangeSymbol = lookupSymbol("ts_query_cursor_set_containing_byte_range")
        let cursorSetMatchLimitSymbol = lookupSymbol("ts_query_cursor_set_match_limit")
        guard let cursorNextCaptureSymbol = lookupSymbol("ts_query_cursor_next_capture") else { return nil }
        guard let treeRootNodeSymbol = lookupSymbol("ts_tree_root_node") else { return nil }
        guard let nodeStartPointSymbol = lookupSymbol("ts_node_start_point") else { return nil }
        guard let nodeEndPointSymbol = lookupSymbol("ts_node_end_point") else { return nil }

        let queryNew = unsafeBitCast(queryNewSymbol, to: CQueryNew.self)
        let queryDelete = unsafeBitCast(queryDeleteSymbol, to: CQueryDelete.self)
        let queryCaptureName = unsafeBitCast(queryCaptureNameSymbol, to: CQueryCaptureName.self)
        let cursorNew = unsafeBitCast(cursorNewSymbol, to: CQueryCursorNew.self)
        let cursorDelete = unsafeBitCast(cursorDeleteSymbol, to: CQueryCursorDelete.self)
        let cursorExec = unsafeBitCast(cursorExecSymbol, to: CQueryCursorExec.self)
        let cursorSetByteRange = cursorSetByteRangeSymbol.map {
            unsafeBitCast($0, to: CQueryCursorSetByteRange.self)
        }
        let cursorSetContainingByteRange = cursorSetContainingByteRangeSymbol.map {
            unsafeBitCast($0, to: CQueryCursorSetByteRange.self)
        }
        let cursorSetMatchLimit = cursorSetMatchLimitSymbol.map {
            unsafeBitCast($0, to: CQueryCursorSetMatchLimit.self)
        }
        let cursorNextCapture = unsafeBitCast(cursorNextCaptureSymbol, to: CQueryCursorNextCapture.self)
        let treeRootNode = unsafeBitCast(treeRootNodeSymbol, to: CTreeRootNode.self)
        let nodeStartPoint = unsafeBitCast(nodeStartPointSymbol, to: CNodePoint.self)
        let nodeEndPoint = unsafeBitCast(nodeEndPointSymbol, to: CNodePoint.self)

        return TreeSitterHighlightQueryAdapter(functions: Functions(
            languageFromEntryPoint: { entryPoint in
                let languageEntryPoint = unsafeBitCast(entryPoint, to: CLanguageEntryPoint.self)
                return languageEntryPoint()
            },
            createQuery: { language, source, length, errorOffset, errorType in
                queryNew(language, source, length, errorOffset, errorType)
            },
            deleteQuery: { query in
                queryDelete(query)
            },
            createCursor: {
                cursorNew()
            },
            deleteCursor: { cursor in
                cursorDelete(cursor)
            },
            exec: { cursor, query, rootNode in
                cursorExec(cursor, query, rootNode.cNode)
            },
            setByteRange: cursorSetByteRange.map { setByteRange in
                { cursor, startByte, endByte in
                    setByteRange(cursor, startByte, endByte)
                }
            },
            setContainingByteRange: cursorSetContainingByteRange.map { setContainingByteRange in
                { cursor, startByte, endByte in
                    setContainingByteRange(cursor, startByte, endByte)
                }
            },
            setMatchLimit: cursorSetMatchLimit.map { setMatchLimit in
                { cursor, limit in
                    setMatchLimit(cursor, limit)
                }
            },
            nextCapture: { cursor in
                var match = CocxyTreeSitterQueryMatch(
                    id: 0,
                    pattern_index: 0,
                    capture_count: 0,
                    captures: nil
                )
                var captureIndex: UInt32 = 0
                guard cursorNextCapture(cursor, &match, &captureIndex),
                      let captures = match.captures,
                      captureIndex < UInt32(match.capture_count) else {
                    return nil
                }
                return TreeSitterRawQueryCapture(cCapture: captures[Int(captureIndex)])
            },
            captureName: { query, index in
                var length: UInt32 = 0
                guard let cString = queryCaptureName(query, index, &length) else {
                    return nil
                }
                let bytes = UnsafeBufferPointer(start: cString, count: Int(length))
                    .map { UInt8(bitPattern: $0) }
                return String(decoding: bytes, as: UTF8.self)
            },
            rootNode: { tree in
                TreeSitterRawNode(cNode: treeRootNode(tree))
            },
            nodeStartPoint: { node in
                TreeSitterRawPoint(cPoint: nodeStartPoint(node.cNode))
            },
            nodeEndPoint: { node in
                TreeSitterRawPoint(cPoint: nodeEndPoint(node.cNode))
            }
        ), retainedObjects: retainedObjects)
    }

    static func resolveBundledOrProcess(
        symbolProvider: TreeSitterSymbolProvider = .bundledOrProcess()
    ) -> TreeSitterHighlightQueryAdapter? {
        TreeSitterHighlightQueryAdapter.resolve(
            lookupSymbol: symbolProvider.lookupSymbol,
            retainedObjects: symbolProvider.retainedObjects
        )
    }

    func warmQuery(
        bundle: SyntaxGrammarBundle,
        querySource: SyntaxHighlightQuerySource
    ) throws {
        let languageID = bundle.language.languageID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let language = functions.languageFromEntryPoint(bundle.library.languageEntryPoint) else {
            throw TreeSitterHighlightQueryAdapterError.languageUnavailable(languageID: languageID)
        }
        _ = try queryCache.compiledQuery(
            language: language,
            source: querySource,
            languageID: languageID,
            functions: functions,
            retainedObjects: retainedObjects + [bundle.library]
        )
    }

    func collectCaptures(
        for tree: SyntaxTree,
        bundle: SyntaxGrammarBundle,
        querySource: SyntaxHighlightQuerySource,
        buffer: EditorBuffer,
        byteRange: Range<Int>? = nil
    ) throws -> [SyntaxQueryCapture] {
        let languageID = bundle.language.languageID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let language = functions.languageFromEntryPoint(bundle.library.languageEntryPoint) else {
            throw TreeSitterHighlightQueryAdapterError.languageUnavailable(languageID: languageID)
        }

        let queryHandle = try queryCache.compiledQuery(
            language: language,
            source: querySource,
            languageID: languageID,
            functions: functions,
            retainedObjects: retainedObjects + [bundle.library]
        ).handle

        guard let cursor = functions.createCursor() else {
            throw TreeSitterHighlightQueryAdapterError.cursorAllocationFailed(languageID: languageID)
        }
        defer { functions.deleteCursor(cursor) }

        guard let captures = try tree.withTreeHandle({ treeHandle in
            try collectCaptures(
                treeHandle: treeHandle,
                queryHandle: queryHandle,
                cursor: cursor,
                languageID: languageID,
                buffer: buffer,
                byteRange: byteRange
            )
        }) else {
            throw TreeSitterHighlightQueryAdapterError.treeClosed(languageID: languageID)
        }
        return captures
    }

    private func collectCaptures(
        treeHandle: UnsafeMutableRawPointer,
        queryHandle: UnsafeMutableRawPointer,
        cursor: UnsafeMutableRawPointer,
        languageID: String,
        buffer: EditorBuffer,
        byteRange: Range<Int>?
    ) throws -> [SyntaxQueryCapture] {
        let rootNode = functions.rootNode(treeHandle)
        guard rootNode.id != nil else {
            throw TreeSitterHighlightQueryAdapterError.missingRootNode(languageID: languageID)
        }

        functions.setMatchLimit?(cursor, 4_096)
        if let byteRange,
           let startByte = UInt32(exactly: byteRange.lowerBound),
           let endByte = UInt32(exactly: byteRange.upperBound) {
            _ = functions.setByteRange?(cursor, startByte, endByte)
            _ = functions.setContainingByteRange?(cursor, startByte, endByte)
        }
        functions.exec(cursor, queryHandle, rootNode)

        let pointConverter = SyntaxPointConverter(text: buffer.text)
        var captures: [SyntaxQueryCapture] = []
        while let capture = functions.nextCapture(cursor) {
            guard let captureName = functions.captureName(queryHandle, capture.index) else {
                continue
            }
            captures.append(SyntaxQueryCapture(
                captureName: captureName,
                range: SyntaxPointRange(
                    start: pointConverter.syntaxPoint(from: functions.nodeStartPoint(capture.node).bytePoint),
                    end: pointConverter.syntaxPoint(from: functions.nodeEndPoint(capture.node).bytePoint)
                )
            ))
        }
        return captures
    }
}

final class TreeSitterHighlightQueryCache {
    private struct Key: Hashable {
        var languageID: String
        var query: String
    }

    private let lock = NSLock()
    private var queries: [Key: TreeSitterCompiledHighlightQuery] = [:]

    func compiledQuery(
        language: UnsafeRawPointer,
        source: SyntaxHighlightQuerySource,
        languageID: String,
        functions: TreeSitterHighlightQueryAdapter.Functions,
        retainedObjects: [AnyObject]
    ) throws -> TreeSitterCompiledHighlightQuery {
        let key = Key(languageID: languageID, query: source.query)
        lock.lock()
        defer { lock.unlock() }

        if let query = queries[key] {
            return query
        }

        let handle = try Self.createQuery(
            language: language,
            source: source,
            languageID: languageID,
            functions: functions
        )
        let query = TreeSitterCompiledHighlightQuery(
            handle: handle,
            deleteQuery: functions.deleteQuery,
            retainedObjects: retainedObjects
        )
        queries[key] = query
        return query
    }

    private static func createQuery(
        language: UnsafeRawPointer,
        source: SyntaxHighlightQuerySource,
        languageID: String,
        functions: TreeSitterHighlightQueryAdapter.Functions
    ) throws -> UnsafeMutableRawPointer {
        let byteLength = source.query.utf8.count
        guard byteLength <= Int(UInt32.max) else {
            throw TreeSitterHighlightQueryAdapterError.queryCompilationFailed(
                languageID: languageID,
                offset: UInt32.max,
                errorType: UInt32(CocxyTreeSitterQueryErrorSyntax.rawValue)
            )
        }

        var errorOffset: UInt32 = 0
        var errorType = CocxyTreeSitterQueryErrorNone
        let queryHandle = source.query.withCString { cString in
            functions.createQuery(language, cString, UInt32(byteLength), &errorOffset, &errorType)
        }
        guard let queryHandle else {
            throw TreeSitterHighlightQueryAdapterError.queryCompilationFailed(
                languageID: languageID,
                offset: errorOffset,
                errorType: UInt32(errorType.rawValue)
            )
        }
        return queryHandle
    }
}

final class TreeSitterCompiledHighlightQuery {
    let handle: UnsafeMutableRawPointer
    private let deleteQuery: (UnsafeMutableRawPointer) -> Void
    private let retainedObjects: [AnyObject]

    init(
        handle: UnsafeMutableRawPointer,
        deleteQuery: @escaping (UnsafeMutableRawPointer) -> Void,
        retainedObjects: [AnyObject]
    ) {
        self.handle = handle
        self.deleteQuery = deleteQuery
        self.retainedObjects = retainedObjects
    }

    deinit {
        deleteQuery(handle)
    }
}

private extension TreeSitterRawQueryCapture {
    init(cCapture: CocxyTreeSitterQueryCapture) {
        self.init(
            node: TreeSitterRawNode(cNode: cCapture.node),
            index: cCapture.index
        )
    }
}
