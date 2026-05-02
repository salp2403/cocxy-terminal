// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TreeSitterRuntimeAdapter.swift - Tree-sitter C ABI bridge for SyntaxTreeRuntime.

import Darwin
import CocxyTreeSitterABI
import Foundation

struct TreeSitterRawPoint: Equatable {
    var row: UInt32
    var column: UInt32

    var bytePoint: SyntaxBytePoint {
        SyntaxBytePoint(line: Int(row), byteColumn: Int(column))
    }
}

struct TreeSitterRawNode: Equatable {
    var context0: UInt32
    var context1: UInt32
    var context2: UInt32
    var context3: UInt32
    var id: UnsafeRawPointer?
    var tree: UnsafeRawPointer?

    static var invalid: TreeSitterRawNode {
        TreeSitterRawNode(
            context0: 0,
            context1: 0,
            context2: 0,
            context3: 0,
            id: nil,
            tree: nil
        )
    }
}

struct TreeSitterRuntimeAdapter {
    struct Functions {
        var createParser: () -> UnsafeMutableRawPointer?
        var deleteParser: (UnsafeMutableRawPointer) -> Void
        var languageFromEntryPoint: (UnsafeMutableRawPointer) -> UnsafeRawPointer?
        var setLanguage: (UnsafeMutableRawPointer, UnsafeRawPointer) -> Bool
        var parseString: (UnsafeMutableRawPointer, UnsafeRawPointer?, UnsafePointer<CChar>, UInt32) -> UnsafeMutableRawPointer?
        var editTree: (UnsafeMutableRawPointer, CocxyTreeSitterInputEdit) -> Void
        var rootNode: (UnsafeMutableRawPointer) -> TreeSitterRawNode
        var deleteTree: (UnsafeMutableRawPointer) -> Void
        var nodeType: (TreeSitterRawNode) -> String
        var nodeIsNamed: (TreeSitterRawNode) -> Bool
        var nodeChildCount: (TreeSitterRawNode) -> UInt32
        var nodeStartPoint: (TreeSitterRawNode) -> TreeSitterRawPoint
        var nodeEndPoint: (TreeSitterRawNode) -> TreeSitterRawPoint
    }

    typealias LookupSymbol = (String) -> UnsafeMutableRawPointer?

    private typealias CParserNew = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias CParserDelete = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias CLanguageEntryPoint = @convention(c) () -> UnsafeRawPointer?
    private typealias CParserSetLanguage = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Bool
    private typealias CParserParseString =
        @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafePointer<CChar>?, UInt32)
            -> UnsafeMutableRawPointer?
    private typealias CTreeEdit = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CocxyTreeSitterInputEdit>?) -> Void
    private typealias CTreeRootNode = @convention(c) (UnsafeMutableRawPointer?) -> CocxyTreeSitterNode
    private typealias CTreeDelete = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias CNodeType = @convention(c) (CocxyTreeSitterNode) -> UnsafePointer<CChar>?
    private typealias CNodeIsNamed = @convention(c) (CocxyTreeSitterNode) -> Bool
    private typealias CNodeChildCount = @convention(c) (CocxyTreeSitterNode) -> UInt32
    private typealias CNodePoint = @convention(c) (CocxyTreeSitterNode) -> CocxyTreeSitterPoint

    private let functions: Functions
    private let retainedObjects: [AnyObject]

    init(functions: Functions, retainedObjects: [AnyObject] = []) {
        self.functions = functions
        self.retainedObjects = retainedObjects
    }

    static func resolve(
        lookupSymbol: LookupSymbol = defaultLookupSymbol,
        retainedObjects: [AnyObject] = []
    ) -> TreeSitterRuntimeAdapter? {
        guard let parserNewSymbol = lookupSymbol("ts_parser_new") else { return nil }
        guard let parserDeleteSymbol = lookupSymbol("ts_parser_delete") else { return nil }
        guard let parserSetLanguageSymbol = lookupSymbol("ts_parser_set_language") else { return nil }
        guard let parserParseStringSymbol = lookupSymbol("ts_parser_parse_string") else { return nil }
        guard let treeEditSymbol = lookupSymbol("ts_tree_edit") else { return nil }
        guard let treeRootNodeSymbol = lookupSymbol("ts_tree_root_node") else { return nil }
        guard let treeDeleteSymbol = lookupSymbol("ts_tree_delete") else { return nil }
        guard let nodeTypeSymbol = lookupSymbol("ts_node_type") else { return nil }
        guard let nodeIsNamedSymbol = lookupSymbol("ts_node_is_named") else { return nil }
        guard let nodeChildCountSymbol = lookupSymbol("ts_node_child_count") else { return nil }
        guard let nodeStartPointSymbol = lookupSymbol("ts_node_start_point") else { return nil }
        guard let nodeEndPointSymbol = lookupSymbol("ts_node_end_point") else { return nil }

        let parserNew = unsafeBitCast(parserNewSymbol, to: CParserNew.self)
        let parserDelete = unsafeBitCast(parserDeleteSymbol, to: CParserDelete.self)
        let parserSetLanguage = unsafeBitCast(parserSetLanguageSymbol, to: CParserSetLanguage.self)
        let parserParseString = unsafeBitCast(parserParseStringSymbol, to: CParserParseString.self)
        let treeEdit = unsafeBitCast(treeEditSymbol, to: CTreeEdit.self)
        let treeRootNode = unsafeBitCast(treeRootNodeSymbol, to: CTreeRootNode.self)
        let treeDelete = unsafeBitCast(treeDeleteSymbol, to: CTreeDelete.self)
        let nodeType = unsafeBitCast(nodeTypeSymbol, to: CNodeType.self)
        let nodeIsNamed = unsafeBitCast(nodeIsNamedSymbol, to: CNodeIsNamed.self)
        let nodeChildCount = unsafeBitCast(nodeChildCountSymbol, to: CNodeChildCount.self)
        let nodeStartPoint = unsafeBitCast(nodeStartPointSymbol, to: CNodePoint.self)
        let nodeEndPoint = unsafeBitCast(nodeEndPointSymbol, to: CNodePoint.self)

        return TreeSitterRuntimeAdapter(functions: Functions(
            createParser: {
                parserNew()
            },
            deleteParser: { parser in
                parserDelete(parser)
            },
            languageFromEntryPoint: { entryPoint in
                let languageEntryPoint = unsafeBitCast(entryPoint, to: CLanguageEntryPoint.self)
                return languageEntryPoint()
            },
            setLanguage: { parser, language in
                parserSetLanguage(parser, language)
            },
            parseString: { parser, oldTree, bytes, byteLength in
                parserParseString(parser, oldTree, bytes, byteLength)
            },
            editTree: { tree, edit in
                var mutableEdit = edit
                treeEdit(tree, &mutableEdit)
            },
            rootNode: { tree in
                TreeSitterRawNode(cNode: treeRootNode(tree))
            },
            deleteTree: { tree in
                treeDelete(tree)
            },
            nodeType: { node in
                guard let cString = nodeType(node.cNode) else { return "unknown" }
                return String(cString: cString)
            },
            nodeIsNamed: { node in
                nodeIsNamed(node.cNode)
            },
            nodeChildCount: { node in
                nodeChildCount(node.cNode)
            },
            nodeStartPoint: { node in
                TreeSitterRawPoint(cPoint: nodeStartPoint(node.cNode))
            },
            nodeEndPoint: { node in
                TreeSitterRawPoint(cPoint: nodeEndPoint(node.cNode))
            }
        ), retainedObjects: retainedObjects)
    }

    static func defaultLookupSymbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let processHandle = dlopen(nil, RTLD_LAZY) else { return nil }
        return dlsym(processHandle, name)
    }

    func runtime() -> SyntaxTreeRuntime {
        SyntaxTreeRuntime(
            createParser: functions.createParser,
            deleteParser: functions.deleteParser,
            setLanguage: { parser, languageEntryPoint in
                guard let language = functions.languageFromEntryPoint(languageEntryPoint) else {
                    return false
                }
                return functions.setLanguage(parser, language)
            },
            parseString: { parser, text in
                Self.parseString(text, parser: parser, oldTree: nil, functions: functions)
            },
            parseStringWithOldTree: { parser, oldTree, text in
                Self.parseString(text, parser: parser, oldTree: oldTree, functions: functions)
            },
            rootNode: { tree, text, _ in
                let rawNode = functions.rootNode(tree)
                guard rawNode.id != nil else { return nil }

                let pointConverter = SyntaxPointConverter(text: text)
                let startPoint = pointConverter.syntaxPoint(from: functions.nodeStartPoint(rawNode).bytePoint)
                let endPoint = pointConverter.syntaxPoint(from: functions.nodeEndPoint(rawNode).bytePoint)

                return SyntaxNode(
                    kind: functions.nodeType(rawNode),
                    range: SyntaxPointRange(start: startPoint, end: endPoint),
                    isNamed: functions.nodeIsNamed(rawNode),
                    childCount: Int(functions.nodeChildCount(rawNode))
                )
            },
            deleteTree: functions.deleteTree,
            editTree: { tree, edit in
                functions.editTree(tree, edit.cInputEdit)
            },
            retainedObjects: retainedObjects
        )
    }

    private static func parseString(
        _ text: String,
        parser: UnsafeMutableRawPointer,
        oldTree: UnsafeMutableRawPointer?,
        functions: Functions
    ) -> UnsafeMutableRawPointer? {
        let byteLength = text.utf8.count
        guard byteLength <= Int(UInt32.max) else { return nil }

        if let treeHandle = text.utf8.withContiguousStorageIfAvailable({ buffer -> UnsafeMutableRawPointer? in
            guard let baseAddress = buffer.baseAddress else {
                return text.withCString { bytes in
                    functions.parseString(parser, oldTree.map { UnsafeRawPointer($0) }, bytes, UInt32(byteLength))
                }
            }
            let bytes = UnsafeRawPointer(baseAddress).assumingMemoryBound(to: CChar.self)
            return functions.parseString(parser, oldTree.map { UnsafeRawPointer($0) }, bytes, UInt32(byteLength))
        }) {
            return treeHandle
        }

        return text.withCString { bytes in
            functions.parseString(parser, oldTree.map { UnsafeRawPointer($0) }, bytes, UInt32(byteLength))
        }
    }
}

extension TreeSitterRawPoint {
    init(cPoint: CocxyTreeSitterPoint) {
        self.init(row: cPoint.row, column: cPoint.column)
    }
}

extension TreeSitterRawNode {
    init(cNode: CocxyTreeSitterNode) {
        self.init(
            context0: cNode.context.0,
            context1: cNode.context.1,
            context2: cNode.context.2,
            context3: cNode.context.3,
            id: cNode.id,
            tree: cNode.tree
        )
    }

    var cNode: CocxyTreeSitterNode {
        CocxyTreeSitterNode(
            context: (context0, context1, context2, context3),
            id: id,
            tree: tree
        )
    }
}

extension SyntaxInputEdit {
    var cInputEdit: CocxyTreeSitterInputEdit {
        CocxyTreeSitterInputEdit(
            start_byte: UInt32(startByte),
            old_end_byte: UInt32(oldEndByte),
            new_end_byte: UInt32(newEndByte),
            start_point: startPoint.cPoint,
            old_end_point: oldEndPoint.cPoint,
            new_end_point: newEndPoint.cPoint
        )
    }
}

extension SyntaxBytePoint {
    var cPoint: CocxyTreeSitterPoint {
        CocxyTreeSitterPoint(row: UInt32(line), column: UInt32(byteColumn))
    }
}

extension SyntaxTreeRuntime {
    static func treeSitterOrUnavailable() -> SyntaxTreeRuntime {
        treeSitterOrUnavailable(symbolProvider: .bundledOrProcess())
    }

    static func treeSitterOrUnavailable(
        lookupSymbol: @escaping TreeSitterRuntimeAdapter.LookupSymbol
    ) -> SyntaxTreeRuntime {
        treeSitterOrUnavailable(symbolProvider: TreeSitterSymbolProvider(lookupSymbol: lookupSymbol))
    }

    static func treeSitterOrUnavailable(symbolProvider: TreeSitterSymbolProvider) -> SyntaxTreeRuntime {
        TreeSitterRuntimeAdapter
            .resolve(
                lookupSymbol: symbolProvider.lookupSymbol,
                retainedObjects: symbolProvider.retainedObjects
            )?
            .runtime() ?? SyntaxTreeRuntime()
    }
}
