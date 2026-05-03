// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VimController.swift - Editor-only Vim state machine for Phase D.

import Foundation

enum VimMode: Equatable {
    case normal
    case insert
    case replace
    case visual
    case visualLine
    case visualBlock
    case commandLine
    case searchForward
    case searchBackward
}

private extension VimMode {
    var isVisual: Bool {
        switch self {
        case .visual, .visualLine, .visualBlock:
            return true
        case .normal, .insert, .replace, .commandLine, .searchForward, .searchBackward:
            return false
        }
    }
}

enum VimInput: Equatable {
    case character(String)
    case text(String)
    case enter
    case deleteBackward
    case escape
}

enum VimExCommand: Equatable {
    case write
    case quit
    case writeQuit
    case clearSearchHighlights
    case setSoftWrap(Bool)
    case toggleSoftWrap
    case reportSoftWrap
}

enum VimEditCommand: Equatable {
    case undo
    case redo
}

enum VimFileCommand: Equatable {
    case openFileAtMark(url: URL, offset: Int, lineWise: Bool)
}

private enum VimSubstitutionScope: Equatable {
    case currentLine
    case document
}

private struct VimSubstitutionCommand: Equatable {
    var scope: VimSubstitutionScope
    var pattern: String
    var replacement: String
    var replaceAllMatchesPerLine: Bool
}

private enum VimTextObjectScope: Equatable {
    case inner
    case around
}

private enum VimRegisterSource: Equatable {
    case yank
    case delete
}

enum VimSystemRegister: Hashable {
    case clipboard
    case primarySelection
}

struct VimSystemRegisterAccess {
    var read: (VimSystemRegister) -> String?
    var write: (String, VimSystemRegister) -> Void

    static var disabled: VimSystemRegisterAccess {
        VimSystemRegisterAccess(
            read: { _ in nil },
            write: { _, _ in }
        )
    }
}

private enum VimMarkOperation: Equatable {
    case set
    case jumpExact
    case jumpLine
}

private struct VimStoredMark: Equatable {
    var documentID: UUID
    var fileURL: URL?
    var offset: Int
}

private struct VimFindCommand: Equatable {
    var command: Character
    var target: Character
}

private struct VimPendingFindMotion: Equatable {
    var command: Character
    var count: Int
    var operatorCharacter: Character?
}

private enum VimRepeatCommand: Equatable {
    case deleteCharacters(count: Int)
    case deleteBackwardCharacters(count: Int)
    case deleteLines(count: Int)
    case deleteMotion(motion: Character, count: Int)
    case deleteFind(command: VimFindCommand, count: Int)
    case deleteTextObject(textObject: Character, scope: VimTextObjectScope, count: Int)
    case deleteVisualBlock(lineCount: Int, columnCount: Int)
    case replaceCharacters(count: Int, character: Character)
    case replaceText(String)
    case openLine(below: Bool, insertedText: String)
    case paste(text: String, after: Bool, count: Int)
    case insertText(String)
    case changeMotion(motion: Character, count: Int, insertedText: String)
    case changeFind(command: VimFindCommand, count: Int, insertedText: String)
    case changeTextObject(textObject: Character, scope: VimTextObjectScope, count: Int, insertedText: String)
    case changeLines(count: Int, insertedText: String)
}

private enum VimPendingChangeRepeat: Equatable {
    case motion(motion: Character, count: Int)
    case find(command: VimFindCommand, count: Int)
    case textObject(textObject: Character, scope: VimTextObjectScope, count: Int)
    case openLine(below: Bool)
    case linewise(count: Int)
}

private enum VimSearchDirection: Equatable {
    case forward
    case backward

    var reversed: VimSearchDirection {
        switch self {
        case .forward: return .backward
        case .backward: return .forward
        }
    }
}

private struct VimSearchState: Equatable {
    var query: String
    var direction: VimSearchDirection
}

private struct VimLineBounds {
    var start: Int
    var end: Int
    var contentsEnd: Int
}

private struct VimParagraphContentRange {
    var start: Int
    var end: Int
}

struct VimHandleResult: Equatable {
    var handled: Bool
    var exCommand: VimExCommand?
    var searchHighlightQuery: String?
    var editCommand: VimEditCommand?
    var fileCommand: VimFileCommand?
}

struct VimController: Equatable {
    private(set) var mode: VimMode = .normal
    private(set) var unnamedRegister = ""

    private var pendingCount = ""
    private var pendingOperator: Character?
    private var pendingPrefix: Character?
    private var pendingTextObjectOperator: Character?
    private var pendingTextObjectScope: VimTextObjectScope?
    private var pendingFindMotion: VimPendingFindMotion?
    private var pendingRegister: Character?
    private var pendingPrefixOperator: Character?
    private var isAwaitingRegisterName = false
    private var registers: [Character: String] = [:]
    private var isAwaitingMacroRegister = false
    private var isAwaitingMacroReplayRegister = false
    private var recordingMacroRegister: Character?
    private var recordingMacroInputs: [VimInput] = []
    private var macros: [Character: [VimInput]] = [:]
    private var isReplayingMacro = false
    private var lastMacroReplayRegister: Character?
    private var pendingMarkOperation: VimMarkOperation?
    private var marks: [Character: VimStoredMark] = [:]
    private var previousJumpMark: VimStoredMark?
    private var lastRepeatCommand: VimRepeatCommand?
    private var lastFindCommand: VimFindCommand?
    private var pendingInsertRepeatText: String?
    private var pendingReplaceRepeatText: String?
    private var pendingChangeRepeat: VimPendingChangeRepeat?
    private var pendingSingleReplace = false
    private var visualAnchor: Int?
    private var visualFocus: Int?
    private var commandLine = ""
    private var searchLine = ""
    private var lastSearch: VimSearchState?

    var commandLineText: String? {
        mode == .commandLine ? commandLine : nil
    }

    var searchLineText: String? {
        switch mode {
        case .searchForward, .searchBackward:
            return searchLine
        case .normal, .insert, .replace, .visual, .visualLine, .visualBlock, .commandLine:
            return nil
        }
    }

    var promptText: String? {
        switch mode {
        case .commandLine:
            return ":\(commandLine)"
        case .searchForward:
            return "/\(searchLine)"
        case .searchBackward:
            return "?\(searchLine)"
        case .normal, .insert, .replace, .visual, .visualLine, .visualBlock:
            return nil
        }
    }

    @discardableResult
    mutating func handle(
        _ input: VimInput,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess = .disabled
    ) -> VimHandleResult {
        if shouldStopMacroRecording(for: input) {
            stopMacroRecording()
            return VimHandleResult(handled: true)
        }

        let shouldRecord = shouldRecordMacroInput(input)
        let result = handleInput(input, session: &session, systemRegisters: systemRegisters)
        if shouldRecord, result.handled {
            recordingMacroInputs.append(input)
        }
        return result
    }

    @discardableResult
    private mutating func handleInput(
        _ input: VimInput,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) -> VimHandleResult {
        switch input {
        case .escape:
            if mode.isVisual {
                session.setSelection(.caret(at: visualAnchor ?? session.selection.primaryRange.location))
            }
            finishInsertRepeatIfNeeded()
            finishReplaceRepeatIfNeeded()
            mode = .normal
            pendingCount = ""
            pendingOperator = nil
            pendingPrefix = nil
            pendingTextObjectOperator = nil
            pendingTextObjectScope = nil
            pendingFindMotion = nil
            pendingRegister = nil
            pendingPrefixOperator = nil
            isAwaitingRegisterName = false
            isAwaitingMacroRegister = false
            isAwaitingMacroReplayRegister = false
            pendingMarkOperation = nil
            pendingSingleReplace = false
            visualAnchor = nil
            visualFocus = nil
            commandLine = ""
            searchLine = ""
            return VimHandleResult(handled: true)

        case .enter:
            switch mode {
            case .insert:
                appendPendingInsertRepeatText("\n")
                session.replaceSelection(with: "\n")
                return VimHandleResult(handled: true)
            case .replace:
                appendPendingReplaceRepeatText("\n")
                replaceTextAtCaret("\n", session: &session)
                return VimHandleResult(handled: true)
            case .commandLine:
                return executeCommandLine(session: &session)
            case .searchForward:
                return executeSearchLine(direction: .forward, session: &session)
            case .searchBackward:
                return executeSearchLine(direction: .backward, session: &session)
            case .normal, .visual, .visualLine, .visualBlock:
                _ = consumeCount()
                return VimHandleResult(handled: true)
            }

        case .deleteBackward:
            switch mode {
            case .commandLine:
                if !commandLine.isEmpty {
                    commandLine.removeLast()
                }
                return VimHandleResult(handled: true)
            case .searchForward, .searchBackward:
                if !searchLine.isEmpty {
                    searchLine.removeLast()
                }
                return VimHandleResult(handled: true)
            case .normal, .visual, .visualLine, .visualBlock:
                return VimHandleResult(handled: true)
            case .insert, .replace:
                pendingInsertRepeatText = nil
                pendingReplaceRepeatText = nil
                pendingChangeRepeat = nil
                return VimHandleResult(handled: false)
            }

        case let .text(text):
            switch mode {
            case .insert:
                appendPendingInsertRepeatText(text)
                session.replaceSelection(with: text)
            case .replace:
                appendPendingReplaceRepeatText(text)
                replaceTextAtCaret(text, session: &session)
            case .commandLine:
                commandLine.append(text)
            case .searchForward, .searchBackward:
                searchLine.append(text)
            case .normal, .visual, .visualLine, .visualBlock:
                break
            }
            return VimHandleResult(handled: true)

        case let .character(rawCharacter):
            guard let character = rawCharacter.first else {
                return VimHandleResult(handled: false)
            }
            if let pendingFindMotion, mode == .normal || mode.isVisual {
                self.pendingFindMotion = nil
                applyPendingFindMotion(
                    pendingFindMotion,
                    target: character,
                    session: &session,
                    systemRegisters: systemRegisters
                )
                return VimHandleResult(handled: true)
            }
            switch mode {
            case .insert:
                appendPendingInsertRepeatText(String(character))
                session.replaceSelection(with: String(character))
                return VimHandleResult(handled: true)
            case .replace:
                appendPendingReplaceRepeatText(String(character))
                replaceTextAtCaret(String(character), session: &session)
                return VimHandleResult(handled: true)
            case .commandLine:
                if character == "\r" || character == "\n" {
                    return executeCommandLine(session: &session)
                }
                commandLine.append(character)
                return VimHandleResult(handled: true)
            case .searchForward:
                if character == "\r" || character == "\n" {
                    return executeSearchLine(direction: .forward, session: &session)
                }
                searchLine.append(character)
                return VimHandleResult(handled: true)
            case .searchBackward:
                if character == "\r" || character == "\n" {
                    return executeSearchLine(direction: .backward, session: &session)
                }
                searchLine.append(character)
                return VimHandleResult(handled: true)
            case .normal:
                return handleNormal(character, session: &session, systemRegisters: systemRegisters)
            case .visual, .visualLine, .visualBlock:
                return handleVisual(character, session: &session, systemRegisters: systemRegisters)
            }
        }
    }

    private func shouldStopMacroRecording(for input: VimInput) -> Bool {
        guard recordingMacroRegister != nil,
              !isReplayingMacro,
              mode == .normal,
              pendingCount.isEmpty,
              pendingOperator == nil,
              pendingPrefix == nil,
              pendingTextObjectOperator == nil,
              pendingTextObjectScope == nil,
              pendingFindMotion == nil,
              pendingRegister == nil,
              !isAwaitingRegisterName,
              !isAwaitingMacroRegister,
              !isAwaitingMacroReplayRegister,
              pendingMarkOperation == nil,
              !pendingSingleReplace,
              case let .character(rawCharacter) = input
        else { return false }

        return rawCharacter.first == "q"
    }

    private func shouldRecordMacroInput(_ input: VimInput) -> Bool {
        guard recordingMacroRegister != nil,
              !isReplayingMacro,
              !isAwaitingMacroRegister
        else { return false }

        return true
    }

    private mutating func handleNormal(
        _ character: Character,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) -> VimHandleResult {
        if isAwaitingRegisterName {
            isAwaitingRegisterName = false
            if isSupportedRegister(character) {
                pendingRegister = character
            }
            return VimHandleResult(handled: true)
        }

        if isAwaitingMacroRegister {
            isAwaitingMacroRegister = false
            _ = consumeCount()
            startMacroRecording(register: character)
            return VimHandleResult(handled: true)
        }

        if isAwaitingMacroReplayRegister {
            isAwaitingMacroReplayRegister = false
            let count = consumeCount()
            let replayRegister = character == "@" ? lastMacroReplayRegister : character
            guard let replayRegister else {
                return VimHandleResult(handled: true)
            }
            replayMacro(
                register: replayRegister,
                count: count,
                session: &session,
                systemRegisters: systemRegisters
            )
            return VimHandleResult(handled: true)
        }

        if let pendingMarkOperation {
            self.pendingMarkOperation = nil
            _ = consumeCount()
            var fileCommand: VimFileCommand?
            if isSupportedMark(character, for: pendingMarkOperation) {
                fileCommand = applyMarkOperation(pendingMarkOperation, mark: character, session: &session)
            }
            return VimHandleResult(handled: true, fileCommand: fileCommand)
        }

        if pendingSingleReplace {
            pendingSingleReplace = false
            replaceCharactersAtCaret(
                count: consumeCount(),
                with: character,
                session: &session
            )
            return VimHandleResult(handled: true)
        }

        if character.isNumber, character != "0" || !pendingCount.isEmpty {
            pendingCount.append(character)
            return VimHandleResult(handled: true)
        }

        if let pendingTextObjectOperator {
            self.pendingTextObjectOperator = nil
            let textObjectScope = pendingTextObjectScope ?? .inner
            pendingTextObjectScope = nil
            if isSupportedTextObject(character) {
                applyTextObjectOperator(
                    pendingTextObjectOperator,
                    textObject: character,
                    scope: textObjectScope,
                    count: consumeCount(),
                    session: &session,
                    systemRegisters: systemRegisters
                )
            } else {
                _ = consumeCount()
            }
            return VimHandleResult(handled: true)
        }

        if let pendingOperator {
            self.pendingOperator = nil
            switch (pendingOperator, character) {
            case ("d", "d"):
                deleteLines(count: consumeCount(), session: &session, systemRegisters: systemRegisters)
                return VimHandleResult(handled: true)
            case ("y", "y"):
                yankLines(count: consumeCount(), session: &session, systemRegisters: systemRegisters)
                return VimHandleResult(handled: true)
            case ("c", "i"), ("d", "i"), ("y", "i"),
                 ("c", "a"), ("d", "a"), ("y", "a"):
                pendingTextObjectOperator = pendingOperator
                pendingTextObjectScope = character == "i" ? .inner : .around
                return VimHandleResult(handled: true)
            case ("d", let motion) where isFindMotionCommand(motion),
                 ("y", let motion) where isFindMotionCommand(motion),
                 ("c", let motion) where isFindMotionCommand(motion):
                pendingFindMotion = VimPendingFindMotion(
                    command: motion,
                    count: consumeCount(),
                    operatorCharacter: pendingOperator
                )
                return VimHandleResult(handled: true)
            case ("d", let motion) where isLinewiseOperatorMotion(motion),
                 ("y", let motion) where isLinewiseOperatorMotion(motion),
                 ("c", let motion) where isLinewiseOperatorMotion(motion):
                applyLinewiseOperator(
                    pendingOperator,
                    motion: motion,
                    count: consumeCount(),
                    session: &session,
                    systemRegisters: systemRegisters
                )
                return VimHandleResult(handled: true)
            case ("d", "g"), ("y", "g"), ("c", "g"),
                 ("d", "["), ("y", "["), ("c", "["),
                 ("d", "]"), ("y", "]"), ("c", "]"):
                pendingPrefix = character
                pendingPrefixOperator = pendingOperator
                return VimHandleResult(handled: true)
            case ("d", let motion) where isOperatorMotion(motion):
                applyOperator(
                    pendingOperator,
                    motion: motion,
                    count: consumeCount(),
                    session: &session,
                    systemRegisters: systemRegisters
                )
                return VimHandleResult(handled: true)
            case ("y", let motion) where isOperatorMotion(motion):
                applyOperator(
                    pendingOperator,
                    motion: motion,
                    count: consumeCount(),
                    session: &session,
                    systemRegisters: systemRegisters
                )
                return VimHandleResult(handled: true)
            case ("c", let motion) where isOperatorMotion(motion):
                applyOperator(
                    pendingOperator,
                    motion: motion,
                    count: consumeCount(),
                    session: &session,
                    systemRegisters: systemRegisters
                )
                return VimHandleResult(handled: true)
            default:
                _ = consumeCount()
                return VimHandleResult(handled: true)
            }
        }

        if let pendingPrefix {
            self.pendingPrefix = nil
            if let pendingPrefixOperator {
                self.pendingPrefixOperator = nil
                switch (pendingPrefix, character) {
                case ("g", "g"):
                    applyLinewiseOperator(
                        pendingPrefixOperator,
                        motion: "g",
                        count: consumeCount(),
                        session: &session,
                        systemRegisters: systemRegisters
                    )
                case ("[", "{"):
                    applyBraceBlockOperator(
                        pendingPrefixOperator,
                        backward: true,
                        count: consumeCount(),
                        session: &session,
                        systemRegisters: systemRegisters
                    )
                case ("]", "}"):
                    applyBraceBlockOperator(
                        pendingPrefixOperator,
                        backward: false,
                        count: consumeCount(),
                        session: &session,
                        systemRegisters: systemRegisters
                    )
                default:
                    _ = consumeCount()
                }
            } else {
                switch (pendingPrefix, character) {
                case ("g", "g"):
                    _ = consumeCount()
                    session.setSelection(.caret(at: 0))
                case ("[", "{"):
                    applyBraceBlockMotion(backward: true, count: consumeCount(), session: &session)
                case ("]", "}"):
                    applyBraceBlockMotion(backward: false, count: consumeCount(), session: &session)
                default:
                    _ = consumeCount()
                }
            }
            return VimHandleResult(handled: true)
        }

        switch character {
        case "u":
            _ = consumeCount()
            return VimHandleResult(handled: true, editCommand: .undo)
        case "\u{12}":
            _ = consumeCount()
            return VimHandleResult(handled: true, editCommand: .redo)
        case "\"":
            isAwaitingRegisterName = true
        case "q":
            _ = consumeCount()
            isAwaitingMacroRegister = true
        case "@":
            isAwaitingMacroReplayRegister = true
        case "i":
            _ = consumeCount()
            enterInsertMode(trackRepeat: true)
        case "R":
            _ = consumeCount()
            mode = .replace
            pendingReplaceRepeatText = ""
        case ":":
            _ = consumeCount()
            mode = .commandLine
            commandLine = ""
        case "/":
            _ = consumeCount()
            mode = .searchForward
            searchLine = ""
        case "?":
            _ = consumeCount()
            mode = .searchBackward
            searchLine = ""
        case "m":
            _ = consumeCount()
            pendingMarkOperation = .set
        case "`":
            _ = consumeCount()
            pendingMarkOperation = .jumpExact
        case "'":
            _ = consumeCount()
            pendingMarkOperation = .jumpLine
        case "a":
            let count = consumeCount()
            moveByCharacters(max(1, count), session: &session)
            enterInsertMode(trackRepeat: true)
        case "o":
            _ = consumeCount()
            openLine(below: true, session: &session)
            enterChangeInsertMode(.openLine(below: true))
        case "O":
            _ = consumeCount()
            openLine(below: false, session: &session)
            enterChangeInsertMode(.openLine(below: false))
        case "v":
            _ = consumeCount()
            enterVisualMode(.visual, session: &session)
        case "V":
            _ = consumeCount()
            enterVisualMode(.visualLine, session: &session)
        case "\u{16}":
            _ = consumeCount()
            enterVisualMode(.visualBlock, session: &session)
        case "h", "j", "k", "l", "0", "$", "w", "W", "b", "B", "%", "G":
            applyMotion(character, count: consumeCount(), session: &session)
        case "f", "F", "t", "T":
            pendingFindMotion = VimPendingFindMotion(
                command: character,
                count: consumeCount(),
                operatorCharacter: nil
            )
        case "g":
            pendingPrefix = "g"
        case "[", "]":
            pendingPrefix = character
        case "d", "y", "c":
            pendingOperator = character
        case "r":
            pendingSingleReplace = true
        case "x":
            deleteCharacters(count: consumeCount(), session: &session, systemRegisters: systemRegisters)
        case "X":
            deleteBackwardCharacters(count: consumeCount(), session: &session, systemRegisters: systemRegisters)
        case "p":
            pasteRegister(after: true, count: consumeCount(), session: &session, systemRegisters: systemRegisters)
        case "P":
            pasteRegister(after: false, count: consumeCount(), session: &session, systemRegisters: systemRegisters)
        case ".":
            repeatLastChange(count: consumeCount(), session: &session, systemRegisters: systemRegisters)
        case ";":
            repeatFindMotion(reversed: false, count: consumeCount(), session: &session)
        case ",":
            repeatFindMotion(reversed: true, count: consumeCount(), session: &session)
        case "n":
            _ = consumeCount()
            repeatSearch(reversed: false, session: &session)
        case "N":
            _ = consumeCount()
            repeatSearch(reversed: true, session: &session)
        default:
            _ = consumeCount()
        }
        return VimHandleResult(handled: true)
    }

    private mutating func executeCommandLine(session: inout EditorSession) -> VimHandleResult {
        let command = commandLine.trimmingCharacters(in: .whitespaces)
        commandLine = ""
        mode = .normal

        guard !command.isEmpty else {
            return VimHandleResult(handled: true)
        }

        switch command {
        case "w", "write":
            return VimHandleResult(handled: true, exCommand: .write)
        case "q", "quit":
            return VimHandleResult(handled: true, exCommand: .quit)
        case "wq":
            return VimHandleResult(handled: true, exCommand: .writeQuit)
        case "nohl", "nohlsearch":
            return VimHandleResult(handled: true, exCommand: .clearSearchHighlights)
        case "set wrap":
            return VimHandleResult(handled: true, exCommand: .setSoftWrap(true))
        case "set nowrap":
            return VimHandleResult(handled: true, exCommand: .setSoftWrap(false))
        case "set wrap!", "set invwrap":
            return VimHandleResult(handled: true, exCommand: .toggleSoftWrap)
        case "set wrap?":
            return VimHandleResult(handled: true, exCommand: .reportSoftWrap)
        default:
            if let substitution = parseSubstitutionCommand(command) {
                applySubstitution(substitution, session: &session)
            }
            return VimHandleResult(handled: true)
        }
    }

    private mutating func executeSearchLine(
        direction: VimSearchDirection,
        session: inout EditorSession
    ) -> VimHandleResult {
        let query = searchLine
        searchLine = ""
        mode = .normal

        guard !query.isEmpty else {
            return VimHandleResult(handled: true)
        }

        let search = VimSearchState(query: query, direction: direction)
        lastSearch = search
        applySearch(search, session: &session)
        return VimHandleResult(handled: true, searchHighlightQuery: query)
    }

    private mutating func repeatSearch(reversed: Bool, session: inout EditorSession) {
        guard var search = lastSearch else { return }
        if reversed {
            search.direction = search.direction.reversed
        }
        applySearch(search, session: &session)
    }

    private mutating func applySearch(_ search: VimSearchState, session: inout EditorSession) {
        guard let offset = searchOffset(
            query: search.query,
            direction: search.direction,
            from: session.selection.primaryRange.location,
            in: session.document.buffer
        ) else { return }

        session.setSelection(.caret(at: offset))
    }

    private func searchOffset(
        query: String,
        direction: VimSearchDirection,
        from offset: Int,
        in buffer: EditorBuffer
    ) -> Int? {
        let text = buffer.text as NSString
        let length = text.length
        guard length > 0, !query.isEmpty else { return nil }

        switch direction {
        case .forward:
            let start = min(length, max(0, offset + 1))
            if let match = findForward(query, in: text, range: NSRange(location: start, length: length - start)) {
                return match
            }
            guard start > 0 else { return nil }
            return findForward(query, in: text, range: NSRange(location: 0, length: start))
        case .backward:
            let end = min(length, max(0, offset))
            if let match = findBackward(query, in: text, range: NSRange(location: 0, length: end)) {
                return match
            }
            guard end < length else { return nil }
            return findBackward(query, in: text, range: NSRange(location: end, length: length - end))
        }
    }

    private func findForward(_ query: String, in text: NSString, range: NSRange) -> Int? {
        guard range.length > 0 else { return nil }
        let match = text.range(of: query, options: [], range: range)
        return match.location == NSNotFound ? nil : match.location
    }

    private func findBackward(_ query: String, in text: NSString, range: NSRange) -> Int? {
        guard range.length > 0 else { return nil }
        let match = text.range(of: query, options: [.backwards], range: range)
        return match.location == NSNotFound ? nil : match.location
    }

    private mutating func handleVisual(
        _ character: Character,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) -> VimHandleResult {
        if character.isNumber, character != "0" || !pendingCount.isEmpty {
            pendingCount.append(character)
            return VimHandleResult(handled: true)
        }

        switch character {
        case "h", "j", "k", "l", "0", "$", "w", "W", "b", "B", "%", "G":
            moveVisualFocus(character, count: consumeCount(), session: &session)
        case "f", "F", "t", "T":
            pendingFindMotion = VimPendingFindMotion(
                command: character,
                count: consumeCount(),
                operatorCharacter: nil
            )
        case ";":
            repeatFindMotion(reversed: false, count: consumeCount(), session: &session)
        case ",":
            repeatFindMotion(reversed: true, count: consumeCount(), session: &session)
        case "y":
            _ = consumeCount()
            yankVisualSelection(session: &session, systemRegisters: systemRegisters)
        case "d":
            _ = consumeCount()
            deleteVisualSelection(session: &session, systemRegisters: systemRegisters)
        default:
            _ = consumeCount()
        }
        return VimHandleResult(handled: true)
    }

    private mutating func enterVisualMode(_ visualMode: VimMode, session: inout EditorSession) {
        let bufferLength = session.document.buffer.utf16Length
        let maximumSelectableOffset = max(0, bufferLength - 1)
        let offset = min(
            max(0, session.selection.primaryRange.location),
            maximumSelectableOffset
        )
        mode = visualMode
        visualAnchor = offset
        visualFocus = offset
        updateVisualSelection(session: &session)
    }

    private mutating func moveVisualFocus(
        _ character: Character,
        count: Int,
        session: inout EditorSession
    ) {
        let buffer = session.document.buffer
        let currentFocus = visualFocus ?? session.selection.primaryRange.location
        let target = motionOffset(from: currentFocus, motion: character, count: count, in: buffer)
        visualFocus = min(max(0, target), max(0, buffer.utf16Length - 1))
        updateVisualSelection(session: &session)
    }

    private mutating func updateVisualSelection(session: inout EditorSession) {
        guard let selection = visualSelection(in: session.document.buffer) else {
            session.setSelection(.caret(at: visualAnchor ?? 0))
            return
        }
        session.setSelection(selection)
    }

    private func visualSelection(in buffer: EditorBuffer) -> EditorSelection? {
        guard buffer.utf16Length > 0,
              let anchor = visualAnchor,
              let focus = visualFocus
        else { return nil }

        if mode == .visualBlock {
            return visualBlockSelection(anchor: anchor, focus: focus, in: buffer)
        }

        guard let range = visualSelectionRange(anchor: anchor, focus: focus, in: buffer) else {
            return nil
        }
        return EditorSelection(ranges: [range])
    }

    private func visualSelectionRange(in buffer: EditorBuffer) -> EditorTextRange? {
        guard buffer.utf16Length > 0,
              let anchor = visualAnchor,
              let focus = visualFocus
        else { return nil }

        return visualSelectionRange(anchor: anchor, focus: focus, in: buffer)
    }

    private func visualSelectionRange(
        anchor: Int,
        focus: Int,
        in buffer: EditorBuffer
    ) -> EditorTextRange? {
        if mode == .visualLine {
            return visualLineSelectionRange(anchor: anchor, focus: focus, in: buffer)
        }

        let maximumSelectableOffset = buffer.utf16Length - 1
        let safeAnchor = min(max(0, anchor), maximumSelectableOffset)
        let safeFocus = min(max(0, focus), maximumSelectableOffset)
        let start = min(safeAnchor, safeFocus)
        let endInclusive = max(safeAnchor, safeFocus)
        return EditorTextRange(location: start, length: endInclusive - start + 1)
    }

    private func visualBlockSelection(anchor: Int, focus: Int, in buffer: EditorBuffer) -> EditorSelection {
        let anchorPosition = buffer.lineAndColumn(for: anchor)
        let focusPosition = buffer.lineAndColumn(for: focus)
        let startLine = min(anchorPosition.line, focusPosition.line)
        let endLine = max(anchorPosition.line, focusPosition.line)
        let startColumn = min(anchorPosition.column, focusPosition.column)
        let endColumnInclusive = max(anchorPosition.column, focusPosition.column)

        var ranges: [EditorTextRange] = []
        var primaryIndex = 0
        for line in startLine...endLine {
            let start = buffer.offset(line: line, column: startColumn)
            let end = buffer.offset(line: line, column: endColumnInclusive + 1)
            if line == focusPosition.line {
                primaryIndex = ranges.count
            }
            ranges.append(EditorTextRange(location: start, length: max(0, end - start)))
        }

        return EditorSelection(ranges: ranges, primaryIndex: primaryIndex)
    }

    private func visualLineSelectionRange(anchor: Int, focus: Int, in buffer: EditorBuffer) -> EditorTextRange {
        let anchorLine = buffer.lineAndColumn(for: anchor).line
        let focusLine = buffer.lineAndColumn(for: focus).line
        let startLine = min(anchorLine, focusLine)
        let endLine = max(anchorLine, focusLine)
        let start = buffer.offset(line: startLine, column: 0)
        let nextLineStart = endLine + 1 < buffer.lineCount
            ? buffer.offset(line: endLine + 1, column: 0)
            : buffer.utf16Length
        return EditorTextRange(location: start, length: max(0, nextLineStart - start))
    }

    private mutating func yankVisualSelection(
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        guard let selection = visualSelection(in: session.document.buffer),
              selection.ranges.contains(where: { $0.length > 0 })
        else {
            leaveVisualMode(restoringCaretAt: session.selection.primaryRange.location, session: &session)
            return
        }
        storeVisualMarks(for: selection, session: session)
        storeRegister(
            selectedVisualText(selection, in: session.document.buffer),
            source: .yank,
            systemRegisters: systemRegisters
        )
        leaveVisualMode(restoringCaretAt: visualAnchor ?? selection.primaryRange.location, session: &session)
    }

    private mutating func deleteVisualSelection(
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        guard let selection = visualSelection(in: session.document.buffer),
              selection.ranges.contains(where: { $0.length > 0 })
        else {
            leaveVisualMode(restoringCaretAt: session.selection.primaryRange.location, session: &session)
            return
        }
        let restoreOffset = visualAnchor ?? selection.primaryRange.location
        let repeatCommand = visualDeleteRepeatCommand(in: session.document.buffer)
        storeVisualMarks(for: selection, session: session)
        storeRegister(
            selectedVisualText(selection, in: session.document.buffer),
            source: .delete,
            systemRegisters: systemRegisters
        )
        session.setSelection(selection)
        session.replaceSelection(with: "")
        leaveVisualMode(
            restoringCaretAt: min(restoreOffset, session.document.buffer.utf16Length),
            session: &session
        )
        lastRepeatCommand = repeatCommand
    }

    private func visualDeleteRepeatCommand(in buffer: EditorBuffer) -> VimRepeatCommand? {
        guard let anchor = visualAnchor,
              let focus = visualFocus
        else { return nil }

        switch mode {
        case .visual:
            guard let range = visualSelectionRange(anchor: anchor, focus: focus, in: buffer),
                  range.length > 0
            else { return nil }
            return .deleteCharacters(count: range.length)
        case .visualLine:
            let anchorLine = buffer.lineAndColumn(for: anchor).line
            let focusLine = buffer.lineAndColumn(for: focus).line
            return .deleteLines(count: abs(anchorLine - focusLine) + 1)
        case .visualBlock:
            let anchorPosition = buffer.lineAndColumn(for: anchor)
            let focusPosition = buffer.lineAndColumn(for: focus)
            return .deleteVisualBlock(
                lineCount: abs(anchorPosition.line - focusPosition.line) + 1,
                columnCount: abs(anchorPosition.column - focusPosition.column) + 1
            )
        default:
            return nil
        }
    }

    private func selectedVisualText(_ selection: EditorSelection, in buffer: EditorBuffer) -> String {
        if mode == .visualBlock {
            return selection.ranges
                .map { buffer.string(in: $0) }
                .joined(separator: "\n")
        }
        return buffer.string(in: selection.primaryRange)
    }

    private mutating func storeVisualMarks(for selection: EditorSelection, session: EditorSession) {
        let selectedRanges = selection.ranges.filter { $0.length > 0 }
        guard let start = selectedRanges.map(\.location).min(),
              let end = selectedRanges.map({ $0.end - 1 }).max()
        else { return }

        marks["<"] = storedMark(offset: start, session: session)
        marks[">"] = storedMark(offset: max(start, end), session: session)
    }

    private mutating func enterInsertMode(trackRepeat: Bool) {
        mode = .insert
        pendingInsertRepeatText = trackRepeat ? "" : nil
        pendingChangeRepeat = nil
    }

    private mutating func enterChangeInsertMode(_ changeRepeat: VimPendingChangeRepeat) {
        mode = .insert
        pendingInsertRepeatText = ""
        pendingChangeRepeat = changeRepeat
    }

    private mutating func appendPendingInsertRepeatText(_ text: String) {
        guard pendingInsertRepeatText != nil else { return }
        pendingInsertRepeatText?.append(text)
    }

    private mutating func appendPendingReplaceRepeatText(_ text: String) {
        guard pendingReplaceRepeatText != nil else { return }
        pendingReplaceRepeatText?.append(text)
    }

    private mutating func finishInsertRepeatIfNeeded() {
        guard let text = pendingInsertRepeatText else {
            pendingChangeRepeat = nil
            return
        }
        pendingInsertRepeatText = nil
        if let pendingChangeRepeat {
            self.pendingChangeRepeat = nil
            switch pendingChangeRepeat {
            case let .motion(motion, count):
                lastRepeatCommand = .changeMotion(motion: motion, count: count, insertedText: text)
            case let .find(command, count):
                lastRepeatCommand = .changeFind(command: command, count: count, insertedText: text)
            case let .textObject(textObject, scope, count):
                lastRepeatCommand = .changeTextObject(
                    textObject: textObject,
                    scope: scope,
                    count: count,
                    insertedText: text
                )
            case let .openLine(below):
                lastRepeatCommand = .openLine(below: below, insertedText: text)
            case let .linewise(count):
                lastRepeatCommand = .changeLines(count: count, insertedText: text)
            }
            return
        }
        guard !text.isEmpty else { return }
        lastRepeatCommand = .insertText(text)
    }

    private mutating func finishReplaceRepeatIfNeeded() {
        guard let text = pendingReplaceRepeatText else { return }
        pendingReplaceRepeatText = nil
        guard !text.isEmpty else { return }
        lastRepeatCommand = .replaceText(text)
    }

    private mutating func replaceTextAtCaret(_ text: String, session: inout EditorSession) {
        let length = max(1, (text as NSString).length)
        replaceRangeAtCaret(length: length, with: text, session: &session)
    }

    private mutating func replaceCharactersAtCaret(
        count: Int,
        with character: Character,
        session: inout EditorSession
    ) {
        let repeatCount = max(1, count)
        replaceRangeAtCaret(
            length: repeatCount,
            with: String(repeating: String(character), count: repeatCount),
            session: &session
        )
        lastRepeatCommand = .replaceCharacters(count: repeatCount, character: character)
    }

    private mutating func replaceRangeAtCaret(
        length requestedLength: Int,
        with replacement: String,
        session: inout EditorSession
    ) {
        let buffer = session.document.buffer
        let start = min(max(0, session.selection.primaryRange.location), buffer.utf16Length)
        let length = min(max(0, requestedLength), max(0, buffer.utf16Length - start))
        session.setSelection(EditorSelection(ranges: [
            EditorTextRange(location: start, length: length),
        ]))
        session.replaceSelection(with: replacement)
    }

    private mutating func leaveVisualMode(restoringCaretAt offset: Int, session: inout EditorSession) {
        mode = .normal
        visualAnchor = nil
        visualFocus = nil
        session.setSelection(.caret(at: offset))
    }

    private func isOperatorMotion(_ character: Character) -> Bool {
        switch character {
        case "h", "l", "0", "$", "w", "W", "b", "B", "%":
            return true
        default:
            return false
        }
    }

    private func isLinewiseOperatorMotion(_ character: Character) -> Bool {
        switch character {
        case "j", "k", "G":
            return true
        default:
            return false
        }
    }

    private func isFindMotionCommand(_ character: Character) -> Bool {
        switch character {
        case "f", "F", "t", "T":
            return true
        default:
            return false
        }
    }

    private mutating func applyMotion(_ character: Character, count: Int, session: inout EditorSession) {
        let buffer = session.document.buffer
        let offset = motionOffset(
            from: session.selection.primaryRange.location,
            motion: character,
            count: count,
            in: buffer
        )

        session.setSelection(.caret(at: offset))
    }

    private mutating func applyPendingFindMotion(
        _ pending: VimPendingFindMotion,
        target: Character,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        let command = VimFindCommand(command: pending.command, target: target)
        if let operatorCharacter = pending.operatorCharacter {
            applyFindOperator(
                operatorCharacter,
                command: command,
                count: pending.count,
                session: &session,
                systemRegisters: systemRegisters
            )
            return
        }
        applyFindMotion(command, count: pending.count, session: &session)
    }

    private mutating func repeatFindMotion(reversed: Bool, count: Int, session: inout EditorSession) {
        guard var command = lastFindCommand else { return }
        if reversed {
            command.command = reversedFindCommand(command.command)
        }
        applyFindMotion(command, count: count, session: &session)
    }

    private func reversedFindCommand(_ command: Character) -> Character {
        switch command {
        case "f": return "F"
        case "F": return "f"
        case "t": return "T"
        case "T": return "t"
        default: return command
        }
    }

    private mutating func applyFindMotion(
        _ command: VimFindCommand,
        count: Int,
        session: inout EditorSession
    ) {
        let start = mode.isVisual
            ? (visualFocus ?? session.selection.primaryRange.location)
            : session.selection.primaryRange.location
        guard let offset = findMotionOffset(
            from: start,
            command: command,
            count: count,
            in: session.document.buffer
        ) else { return }

        lastFindCommand = command
        if mode.isVisual {
            visualFocus = min(max(0, offset), max(0, session.document.buffer.utf16Length - 1))
            updateVisualSelection(session: &session)
        } else {
            session.setSelection(.caret(at: offset))
        }
    }

    private mutating func applyBraceBlockMotion(
        backward: Bool,
        count: Int,
        session: inout EditorSession
    ) {
        let buffer = session.document.buffer
        var result = session.selection.primaryRange.location
        for _ in 0..<max(1, count) {
            guard let next = braceBlockOffset(from: result, backward: backward, in: buffer) else { break }
            result = next
        }
        session.setSelection(.caret(at: result))
    }

    private mutating func applyLinewiseOperator(
        _ operatorCharacter: Character,
        motion: Character,
        count: Int,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        guard let range = linewiseOperatorRange(for: motion, count: count, session: session),
              range.length > 0
        else { return }
        applyLinewiseOperator(
            operatorCharacter,
            range: range,
            session: &session,
            systemRegisters: systemRegisters
        )
    }

    private mutating func applyBraceBlockOperator(
        _ operatorCharacter: Character,
        backward: Bool,
        count: Int,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        let buffer = session.document.buffer
        var result = session.selection.primaryRange.location
        for _ in 0..<max(1, count) {
            guard let next = braceBlockOffset(from: result, backward: backward, in: buffer) else { break }
            result = next
        }
        guard let range = linewiseRange(
            from: session.selection.primaryRange.location,
            to: result,
            in: buffer
        ), range.length > 0 else { return }
        applyLinewiseOperator(
            operatorCharacter,
            range: range,
            session: &session,
            systemRegisters: systemRegisters
        )
    }

    private mutating func applyLinewiseOperator(
        _ operatorCharacter: Character,
        range: EditorTextRange,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        let text = session.document.buffer.string(in: range)
        let affectedLineCount = lineCount(in: range, buffer: session.document.buffer)
        switch operatorCharacter {
        case "d":
            storeRegister(text, source: .delete, systemRegisters: systemRegisters)
            session.setSelection(EditorSelection(ranges: [range]))
            session.replaceSelection(with: "")
            session.setSelection(.caret(at: min(range.location, session.document.buffer.utf16Length)))
            lastRepeatCommand = .deleteLines(count: affectedLineCount)
        case "c":
            storeRegister(text, source: .delete, systemRegisters: systemRegisters)
            session.setSelection(EditorSelection(ranges: [range]))
            session.replaceSelection(with: "")
            session.setSelection(.caret(at: min(range.location, session.document.buffer.utf16Length)))
            enterChangeInsertMode(.linewise(count: affectedLineCount))
        case "y":
            storeRegister(text, source: .yank, systemRegisters: systemRegisters)
            session.setSelection(.caret(at: range.location))
        default:
            break
        }
    }

    private func motionOffset(
        from offset: Int,
        motion character: Character,
        count: Int,
        in buffer: EditorBuffer
    ) -> Int {
        let repeatCount = max(1, count)
        var result = offset

        switch character {
        case "h":
            result = max(0, offset - repeatCount)
        case "l":
            result = min(buffer.utf16Length, offset + repeatCount)
        case "j":
            result = moveVertically(from: offset, lineDelta: repeatCount, in: buffer)
        case "k":
            result = moveVertically(from: offset, lineDelta: -repeatCount, in: buffer)
        case "0":
            let position = buffer.lineAndColumn(for: offset)
            result = buffer.offset(line: position.line, column: 0)
        case "$":
            result = lineLastCharacterOffset(containing: offset, in: buffer)
        case "w":
            for _ in 0..<repeatCount {
                result = nextWordStart(after: result, in: buffer)
            }
        case "W":
            for _ in 0..<repeatCount {
                result = nextBigWordStart(after: result, in: buffer)
            }
        case "b":
            for _ in 0..<repeatCount {
                result = previousWordStart(before: result, in: buffer)
            }
        case "B":
            for _ in 0..<repeatCount {
                result = previousBigWordStart(before: result, in: buffer)
            }
        case "%":
            result = matchingDelimiterOffset(from: offset, in: buffer) ?? offset
        case "G":
            let line = repeatCount > 1 ? repeatCount - 1 : max(0, buffer.lineCount - 1)
            result = buffer.offset(line: line, column: 0)
        default:
            break
        }

        return result
    }

    private func braceBlockOffset(from offset: Int, backward: Bool, in buffer: EditorBuffer) -> Int? {
        guard let openCode = utf16Code(for: "{"),
              let closeCode = utf16Code(for: "}")
        else { return nil }

        let nsText = buffer.text as NSString
        guard nsText.length > 0 else { return nil }

        if backward {
            guard offset > 0 else { return nil }
            var cursor = min(offset - 1, nsText.length - 1)
            var depth = 0
            while cursor >= 0 {
                let code = nsText.character(at: cursor)
                if code == closeCode {
                    depth += 1
                } else if code == openCode {
                    if depth == 0 {
                        return cursor
                    }
                    depth -= 1
                }
                cursor -= 1
            }
            return nil
        }

        var cursor = min(max(0, offset + 1), nsText.length)
        var depth = 0
        while cursor < nsText.length {
            let code = nsText.character(at: cursor)
            if code == openCode {
                depth += 1
            } else if code == closeCode {
                if depth == 0 {
                    return cursor
                }
                depth -= 1
            }
            cursor += 1
        }
        return nil
    }

    private mutating func applyOperator(
        _ operatorCharacter: Character,
        motion: Character,
        count: Int,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        let resolvedRange = operatorCharacter == "c"
            ? changeOperatorRange(for: motion, count: count, session: session)
            : operatorRange(for: motion, count: count, session: session)
        guard let range = resolvedRange,
              range.length > 0
        else { return }

        switch operatorCharacter {
        case "d":
            storeRegister(
                session.document.buffer.string(in: range),
                source: .delete,
                systemRegisters: systemRegisters
            )
            session.setSelection(EditorSelection(ranges: [range]))
            session.replaceSelection(with: "")
            session.setSelection(.caret(at: min(range.location, session.document.buffer.utf16Length)))
            lastRepeatCommand = .deleteMotion(motion: motion, count: max(1, count))
        case "c":
            storeRegister(
                session.document.buffer.string(in: range),
                source: .delete,
                systemRegisters: systemRegisters
            )
            session.setSelection(EditorSelection(ranges: [range]))
            session.replaceSelection(with: "")
            session.setSelection(.caret(at: min(range.location, session.document.buffer.utf16Length)))
            enterChangeInsertMode(.motion(motion: motion, count: max(1, count)))
        case "y":
            storeRegister(
                session.document.buffer.string(in: range),
                source: .yank,
                systemRegisters: systemRegisters
            )
            session.setSelection(.caret(at: range.location))
        default:
            break
        }
    }

    private mutating func applyFindOperator(
        _ operatorCharacter: Character,
        command: VimFindCommand,
        count: Int,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        guard let range = findOperatorRange(for: command, count: count, session: session),
              range.length > 0
        else { return }

        switch operatorCharacter {
        case "d":
            storeRegister(
                session.document.buffer.string(in: range),
                source: .delete,
                systemRegisters: systemRegisters
            )
            session.setSelection(EditorSelection(ranges: [range]))
            session.replaceSelection(with: "")
            session.setSelection(.caret(at: min(range.location, session.document.buffer.utf16Length)))
            lastFindCommand = command
            lastRepeatCommand = .deleteFind(command: command, count: max(1, count))
        case "c":
            storeRegister(
                session.document.buffer.string(in: range),
                source: .delete,
                systemRegisters: systemRegisters
            )
            session.setSelection(EditorSelection(ranges: [range]))
            session.replaceSelection(with: "")
            session.setSelection(.caret(at: min(range.location, session.document.buffer.utf16Length)))
            lastFindCommand = command
            enterChangeInsertMode(.find(command: command, count: max(1, count)))
        case "y":
            storeRegister(
                session.document.buffer.string(in: range),
                source: .yank,
                systemRegisters: systemRegisters
            )
            session.setSelection(.caret(at: range.location))
            lastFindCommand = command
        default:
            break
        }
    }

    private func operatorRange(
        for motion: Character,
        count: Int,
        session: EditorSession
    ) -> EditorTextRange? {
        let repeatCount = max(1, count)
        let buffer = session.document.buffer
        let start = session.selection.primaryRange.location

        switch motion {
        case "w":
            var end = start
            for _ in 0..<repeatCount {
                end = nextWordStart(after: end, in: buffer)
            }
            return forwardRange(from: start, toExclusive: end)
        case "W":
            var end = start
            for _ in 0..<repeatCount {
                end = nextBigWordStart(after: end, in: buffer)
            }
            return forwardRange(from: start, toExclusive: end)
        case "b":
            var target = start
            for _ in 0..<repeatCount {
                target = previousWordStart(before: target, in: buffer)
            }
            return backwardRange(from: start, toInclusiveStart: target)
        case "B":
            var target = start
            for _ in 0..<repeatCount {
                target = previousBigWordStart(before: target, in: buffer)
            }
            return backwardRange(from: start, toInclusiveStart: target)
        case "%":
            guard let target = matchingDelimiterOffset(from: start, in: buffer) else { return nil }
            return delimiterMatchRange(from: start, to: target, in: buffer)
        case "h":
            return backwardRange(from: start, toInclusiveStart: max(0, start - repeatCount))
        case "l":
            return forwardRange(from: start, toExclusive: min(buffer.utf16Length, start + repeatCount))
        case "0":
            let position = buffer.lineAndColumn(for: start)
            return backwardRange(from: start, toInclusiveStart: buffer.offset(line: position.line, column: 0))
        case "$":
            let end = min(buffer.utf16Length, lineLastCharacterOffset(containing: start, in: buffer) + 1)
            return forwardRange(from: start, toExclusive: end)
        default:
            return nil
        }
    }

    private func changeOperatorRange(
        for motion: Character,
        count: Int,
        session: EditorSession
    ) -> EditorTextRange? {
        guard let range = operatorRange(for: motion, count: count, session: session) else {
            return nil
        }
        switch motion {
        case "w", "W":
            return rangeByTrimmingTrailingWhitespaceForChange(range, in: session.document.buffer)
        default:
            return range
        }
    }

    private func rangeByTrimmingTrailingWhitespaceForChange(
        _ range: EditorTextRange,
        in buffer: EditorBuffer
    ) -> EditorTextRange {
        let nsText = buffer.text as NSString
        guard range.length > 0,
              range.location < nsText.length,
              !isWhitespace(nsText.character(at: range.location))
        else {
            return range
        }

        var end = min(range.location + range.length, nsText.length)
        while end > range.location, isWhitespace(nsText.character(at: end - 1)) {
            end -= 1
        }
        return EditorTextRange(location: range.location, length: max(1, end - range.location))
    }

    private func findOperatorRange(
        for command: VimFindCommand,
        count: Int,
        session: EditorSession
    ) -> EditorTextRange? {
        let start = session.selection.primaryRange.location
        guard let target = findTargetOffset(
            from: start,
            command: command,
            count: count,
            in: session.document.buffer
        ) else { return nil }

        switch command.command {
        case "f":
            return forwardRange(from: start, toExclusive: target + 1)
        case "t":
            return forwardRange(from: start, toExclusive: target)
        case "F":
            return backwardRange(from: start, toInclusiveStart: target)
        case "T":
            return backwardRange(from: start, toInclusiveStart: target + 1)
        default:
            return nil
        }
    }

    private func forwardRange(from start: Int, toExclusive end: Int) -> EditorTextRange? {
        guard end > start else { return nil }
        return EditorTextRange(location: start, length: end - start)
    }

    private func backwardRange(from start: Int, toInclusiveStart target: Int) -> EditorTextRange? {
        let lower = min(start, target)
        let upper = max(start, target)
        guard upper > lower else { return nil }
        return EditorTextRange(location: lower, length: upper - lower)
    }

    private func delimiterMatchRange(from start: Int, to target: Int, in buffer: EditorBuffer) -> EditorTextRange? {
        let lower = min(start, target)
        let upper = min(max(start, target) + 1, buffer.utf16Length)
        guard upper > lower else { return nil }
        return EditorTextRange(location: lower, length: upper - lower)
    }

    private mutating func applyTextObjectOperator(
        _ operatorCharacter: Character,
        textObject: Character,
        scope: VimTextObjectScope,
        count: Int,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        guard let range = textObjectRange(for: textObject, scope: scope, count: count, session: session),
              range.length > 0 || operatorCharacter == "c"
        else { return }

        switch operatorCharacter {
        case "d":
            storeRegister(
                session.document.buffer.string(in: range),
                source: .delete,
                systemRegisters: systemRegisters
            )
            session.setSelection(EditorSelection(ranges: [range]))
            session.replaceSelection(with: "")
            session.setSelection(.caret(at: min(range.location, session.document.buffer.utf16Length)))
            lastRepeatCommand = .deleteTextObject(
                textObject: textObject,
                scope: scope,
                count: max(1, count)
            )
        case "c":
            storeRegister(
                session.document.buffer.string(in: range),
                source: .delete,
                systemRegisters: systemRegisters
            )
            session.setSelection(EditorSelection(ranges: [range]))
            session.replaceSelection(with: "")
            session.setSelection(.caret(at: min(range.location, session.document.buffer.utf16Length)))
            enterChangeInsertMode(.textObject(
                textObject: textObject,
                scope: scope,
                count: max(1, count)
            ))
        case "y":
            storeRegister(
                session.document.buffer.string(in: range),
                source: .yank,
                systemRegisters: systemRegisters
            )
            session.setSelection(.caret(at: range.location))
        default:
            break
        }
    }

    private func textObjectRange(
        for textObject: Character,
        scope: VimTextObjectScope,
        count: Int,
        session: EditorSession
    ) -> EditorTextRange? {
        switch textObject {
        case "w":
            let offset = session.selection.primaryRange.location
            let repeatCount = max(1, count)
            switch scope {
            case .inner:
                return innerWordRange(containing: offset, count: repeatCount, in: session.document.buffer)
            case .around:
                return aroundWordRange(containing: offset, count: repeatCount, in: session.document.buffer)
            }
        case "p":
            return paragraphRange(
                containing: session.selection.primaryRange.location,
                count: max(1, count),
                scope: scope,
                in: session.document.buffer
            )
        case "\"", "'", "`":
            return quoteRange(
                delimiter: textObject,
                scope: scope,
                containing: session.selection.primaryRange.location,
                in: session.document.buffer
            )
        case "(", ")":
            return pairedDelimiterRange(
                open: "(",
                close: ")",
                scope: scope,
                containing: session.selection.primaryRange.location,
                in: session.document.buffer
            )
        case "[", "]":
            return pairedDelimiterRange(
                open: "[",
                close: "]",
                scope: scope,
                containing: session.selection.primaryRange.location,
                in: session.document.buffer
            )
        case "{", "}":
            return pairedDelimiterRange(
                open: "{",
                close: "}",
                scope: scope,
                containing: session.selection.primaryRange.location,
                in: session.document.buffer
            )
        case "<", ">":
            return pairedDelimiterRange(
                open: "<",
                close: ">",
                scope: scope,
                containing: session.selection.primaryRange.location,
                in: session.document.buffer
            )
        default:
            return nil
        }
    }

    private func isSupportedTextObject(_ textObject: Character) -> Bool {
        switch textObject {
        case "w", "p", "\"", "'", "`", "(", ")", "[", "]", "{", "}", "<", ">":
            return true
        default:
            return false
        }
    }

    private func innerWordRange(
        containing offset: Int,
        count: Int,
        in buffer: EditorBuffer
    ) -> EditorTextRange? {
        let nsText = buffer.text as NSString
        guard nsText.length > 0 else { return nil }

        var start = min(max(0, offset), nsText.length - 1)
        if !isWordCharacter(nsText.character(at: start)), start > 0 {
            start -= 1
        }
        guard isWordCharacter(nsText.character(at: start)) else { return nil }

        while start > 0, isWordCharacter(nsText.character(at: start - 1)) {
            start -= 1
        }

        var end = min(max(0, offset), nsText.length - 1)
        if !isWordCharacter(nsText.character(at: end)), end > start {
            end -= 1
        }
        while end < nsText.length, isWordCharacter(nsText.character(at: end)) {
            end += 1
        }

        var wordsRemaining = max(1, count) - 1
        while wordsRemaining > 0 {
            while end < nsText.length, !isWordCharacter(nsText.character(at: end)) {
                end += 1
            }
            while end < nsText.length, isWordCharacter(nsText.character(at: end)) {
                end += 1
            }
            wordsRemaining -= 1
        }

        guard end > start else { return nil }
        return EditorTextRange(location: start, length: end - start)
    }

    private func aroundWordRange(
        containing offset: Int,
        count: Int,
        in buffer: EditorBuffer
    ) -> EditorTextRange? {
        guard let innerRange = innerWordRange(containing: offset, count: count, in: buffer) else {
            return nil
        }

        let nsText = buffer.text as NSString
        var start = innerRange.location
        var end = innerRange.location + innerRange.length

        if end < nsText.length, isWhitespace(nsText.character(at: end)) {
            while end < nsText.length, isWhitespace(nsText.character(at: end)) {
                end += 1
            }
        } else {
            while start > 0, isWhitespace(nsText.character(at: start - 1)) {
                start -= 1
            }
        }

        guard end > start else { return nil }
        return EditorTextRange(location: start, length: end - start)
    }

    private func paragraphRange(
        containing offset: Int,
        count: Int,
        scope: VimTextObjectScope,
        in buffer: EditorBuffer
    ) -> EditorTextRange? {
        let nsText = buffer.text as NSString
        guard nsText.length > 0,
              let firstLine = nearestNonblankLine(containing: offset, in: nsText)
        else { return nil }

        let contentRange = paragraphContentRange(startingAt: firstLine, count: max(1, count), in: nsText)
        let start: Int
        let end: Int
        switch scope {
        case .inner:
            start = contentRange.start
            end = contentRange.end
        case .around:
            let trailingEnd = endOfFollowingBlankLines(after: contentRange.end, in: nsText)
            if trailingEnd > contentRange.end {
                start = contentRange.start
                end = trailingEnd
            } else {
                start = startOfPrecedingBlankLines(before: contentRange.start, in: nsText)
                end = contentRange.end
            }
        }

        guard end > start else { return nil }
        return EditorTextRange(location: start, length: end - start)
    }

    private func paragraphContentRange(
        startingAt firstLine: VimLineBounds,
        count: Int,
        in nsText: NSString
    ) -> VimParagraphContentRange {
        var startLine = firstLine
        while let previous = previousLine(before: startLine.start, in: nsText),
              !isBlankLine(previous, in: nsText) {
            startLine = previous
        }

        var end = endOfParagraph(startingAt: firstLine, in: nsText)
        var paragraphsRemaining = max(1, count) - 1
        while paragraphsRemaining > 0,
              let nextLine = nextParagraphLine(after: end, in: nsText) {
            end = endOfParagraph(startingAt: nextLine, in: nsText)
            paragraphsRemaining -= 1
        }

        return VimParagraphContentRange(start: startLine.start, end: end)
    }

    private func endOfParagraph(startingAt line: VimLineBounds, in nsText: NSString) -> Int {
        var end = line.end
        var cursor = line.end
        while cursor < nsText.length {
            let next = lineBounds(containing: cursor, in: nsText)
            guard !isBlankLine(next, in: nsText) else { break }
            end = next.end
            guard next.end > cursor else { break }
            cursor = next.end
        }
        return end
    }

    private func nextParagraphLine(after offset: Int, in nsText: NSString) -> VimLineBounds? {
        var cursor = offset
        while cursor < nsText.length {
            let line = lineBounds(containing: cursor, in: nsText)
            if !isBlankLine(line, in: nsText) {
                return line
            }
            guard line.end > cursor else { break }
            cursor = line.end
        }
        return nil
    }

    private func nearestNonblankLine(containing offset: Int, in nsText: NSString) -> VimLineBounds? {
        let safeOffset = min(max(0, offset), nsText.length - 1)
        let current = lineBounds(containing: safeOffset, in: nsText)
        if !isBlankLine(current, in: nsText) {
            return current
        }

        if let next = nextParagraphLine(after: current.end, in: nsText) {
            return next
        }

        var cursor = current.start
        while let previous = previousLine(before: cursor, in: nsText) {
            if !isBlankLine(previous, in: nsText) {
                return previous
            }
            cursor = previous.start
        }
        return nil
    }

    private func endOfFollowingBlankLines(after offset: Int, in nsText: NSString) -> Int {
        var cursor = offset
        var end = offset
        while cursor < nsText.length {
            let line = lineBounds(containing: cursor, in: nsText)
            guard isBlankLine(line, in: nsText) else { break }
            end = line.end
            guard line.end > cursor else { break }
            cursor = line.end
        }
        return end
    }

    private func startOfPrecedingBlankLines(before offset: Int, in nsText: NSString) -> Int {
        var start = offset
        while let previous = previousLine(before: start, in: nsText),
              isBlankLine(previous, in: nsText) {
            start = previous.start
        }
        return start
    }

    private func previousLine(before offset: Int, in nsText: NSString) -> VimLineBounds? {
        guard offset > 0 else { return nil }
        return lineBounds(containing: offset - 1, in: nsText)
    }

    private func lineBounds(containing offset: Int, in nsText: NSString) -> VimLineBounds {
        let safeOffset = min(max(0, offset), max(0, nsText.length - 1))
        var start = 0
        var end = 0
        var contentsEnd = 0
        nsText.getLineStart(
            &start,
            end: &end,
            contentsEnd: &contentsEnd,
            for: NSRange(location: safeOffset, length: 0)
        )
        return VimLineBounds(start: start, end: end, contentsEnd: contentsEnd)
    }

    private func isBlankLine(_ line: VimLineBounds, in nsText: NSString) -> Bool {
        let length = max(0, line.contentsEnd - line.start)
        let text = nsText.substring(with: NSRange(location: line.start, length: length))
        return text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func quoteRange(
        delimiter: Character,
        scope: VimTextObjectScope,
        containing offset: Int,
        in buffer: EditorBuffer
    ) -> EditorTextRange? {
        guard let delimiterCode = utf16Code(for: delimiter) else { return nil }
        let nsText = buffer.text as NSString
        guard nsText.length > 1 else { return nil }

        let safeOffset = min(max(0, offset), nsText.length - 1)
        let delimiters = (0..<nsText.length).filter { index in
            nsText.character(at: index) == delimiterCode
                && !isEscapedQuoteDelimiter(at: index, in: nsText)
        }

        var index = 0
        while index + 1 < delimiters.count {
            let openingIndex = delimiters[index]
            let closingIndex = delimiters[index + 1]
            if openingIndex <= safeOffset, safeOffset <= closingIndex {
                return scopedDelimiterRange(
                    openingIndex: openingIndex,
                    closingIndex: closingIndex,
                    scope: scope
                )
            }
            index += 2
        }

        return nil
    }

    private func isEscapedQuoteDelimiter(at index: Int, in nsText: NSString) -> Bool {
        var cursor = index - 1
        var slashCount = 0
        while cursor >= 0, nsText.character(at: cursor) == 92 {
            slashCount += 1
            cursor -= 1
        }
        return slashCount % 2 == 1
    }

    private func pairedDelimiterRange(
        open: Character,
        close: Character,
        scope: VimTextObjectScope,
        containing offset: Int,
        in buffer: EditorBuffer
    ) -> EditorTextRange? {
        guard let openCode = utf16Code(for: open),
              let closeCode = utf16Code(for: close)
        else { return nil }

        let nsText = buffer.text as NSString
        guard nsText.length > 1 else { return nil }

        let safeOffset = min(max(0, offset), nsText.length - 1)
        var stack: [Int] = []
        var enclosingPair: (opening: Int, closing: Int)?

        for index in 0..<nsText.length {
            let code = nsText.character(at: index)
            if code == openCode {
                stack.append(index)
            } else if code == closeCode, let openingIndex = stack.popLast() {
                if enclosingPair == nil, openingIndex <= safeOffset, safeOffset <= index {
                    enclosingPair = (openingIndex, index)
                }
            }
        }

        guard let enclosingPair else { return nil }
        return scopedDelimiterRange(
            openingIndex: enclosingPair.opening,
            closingIndex: enclosingPair.closing,
            scope: scope
        )
    }

    private func scopedDelimiterRange(
        openingIndex: Int,
        closingIndex: Int,
        scope: VimTextObjectScope
    ) -> EditorTextRange? {
        let start: Int
        let end: Int
        switch scope {
        case .inner:
            start = openingIndex + 1
            end = closingIndex
        case .around:
            start = openingIndex
            end = closingIndex + 1
        }

        guard end >= start else { return nil }
        return EditorTextRange(location: start, length: end - start)
    }

    private func parseSubstitutionCommand(_ command: String) -> VimSubstitutionCommand? {
        let characters = Array(command)
        guard !characters.isEmpty else { return nil }

        let scope: VimSubstitutionScope
        let commandStart: Int
        if characters.first == "%" {
            scope = .document
            commandStart = 1
        } else {
            scope = .currentLine
            commandStart = 0
        }

        guard characters.indices.contains(commandStart),
              characters[commandStart] == "s" else {
            return nil
        }

        let delimiterIndex = commandStart + 1
        guard characters.indices.contains(delimiterIndex) else { return nil }
        let delimiter = characters[delimiterIndex]
        guard delimiter != "\\" else { return nil }

        let patternStart = delimiterIndex + 1
        guard let patternEnd = nextUnescapedDelimiter(
            in: characters,
            from: patternStart,
            delimiter: delimiter
        ) else { return nil }

        let replacementStart = patternEnd + 1
        guard let replacementEnd = nextUnescapedDelimiter(
            in: characters,
            from: replacementStart,
            delimiter: delimiter
        ) else { return nil }

        let rawPattern = String(characters[patternStart..<patternEnd])
        let rawReplacement = String(characters[replacementStart..<replacementEnd])
        let flags = String(characters[(replacementEnd + 1)..<characters.endIndex])
        let pattern = unescapeSubstitutionField(rawPattern)
        guard !pattern.isEmpty else { return nil }

        return VimSubstitutionCommand(
            scope: scope,
            pattern: pattern,
            replacement: unescapeSubstitutionField(rawReplacement),
            replaceAllMatchesPerLine: flags.contains("g")
        )
    }

    private func nextUnescapedDelimiter(
        in characters: [Character],
        from start: Int,
        delimiter: Character
    ) -> Int? {
        var isEscaped = false
        for index in start..<characters.endIndex {
            let character = characters[index]
            if isEscaped {
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if character == delimiter {
                return index
            }
        }
        return nil
    }

    private func unescapeSubstitutionField(_ field: String) -> String {
        var result = ""
        var isEscaped = false
        for character in field {
            if isEscaped {
                result.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else {
                result.append(character)
            }
        }
        if isEscaped {
            result.append("\\")
        }
        return result
    }

    private mutating func applySubstitution(
        _ command: VimSubstitutionCommand,
        session: inout EditorSession
    ) {
        switch command.scope {
        case .document:
            let currentCaret = session.selection.primaryRange.location
            let updatedText = substitute(command, in: session.document.buffer.text)
            guard updatedText != session.document.buffer.text else { return }
            session.replaceAllText(with: updatedText)
            session.setSelection(.caret(at: min(currentCaret, session.document.buffer.utf16Length)))
        case .currentLine:
            let buffer = session.document.buffer
            let lineRange = buffer.lineRange(containing: session.selection.primaryRange.location)
            let lineText = buffer.string(in: lineRange)
            let updatedLine = substitute(command, in: lineText)
            guard updatedLine != lineText else { return }
            let currentCaret = session.selection.primaryRange.location
            session.setSelection(EditorSelection(ranges: [lineRange]))
            session.replaceSelection(with: updatedLine)
            session.setSelection(.caret(at: min(currentCaret, session.document.buffer.utf16Length)))
        }
    }

    private func substitute(_ command: VimSubstitutionCommand, in text: String) -> String {
        if command.replaceAllMatchesPerLine {
            return text.replacingOccurrences(of: command.pattern, with: command.replacement)
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                replaceFirstOccurrence(
                    of: command.pattern,
                    with: command.replacement,
                    in: String(line)
                )
            }
            .joined(separator: "\n")
    }

    private func replaceFirstOccurrence(
        of pattern: String,
        with replacement: String,
        in text: String
    ) -> String {
        guard let range = text.range(of: pattern) else { return text }
        var updated = text
        updated.replaceSubrange(range, with: replacement)
        return updated
    }

    private mutating func consumeCount() -> Int {
        defer { pendingCount = "" }
        return Int(pendingCount) ?? 1
    }

    private func moveVertically(from offset: Int, lineDelta: Int, in buffer: EditorBuffer) -> Int {
        let position = buffer.lineAndColumn(for: offset)
        let targetLine = min(max(0, position.line + lineDelta), buffer.lineCount - 1)
        return buffer.offset(line: targetLine, column: position.column)
    }

    private mutating func moveByCharacters(_ count: Int, session: inout EditorSession) {
        let offset = min(session.document.buffer.utf16Length, session.selection.primaryRange.location + count)
        session.setSelection(.caret(at: offset))
    }

    private mutating func deleteCharacters(
        count: Int,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        let buffer = session.document.buffer
        let repeatCount = max(1, count)
        let start = session.selection.primaryRange.location
        let length = min(repeatCount, max(0, buffer.utf16Length - start))
        guard length > 0 else { return }
        storeRegister(
            buffer.string(in: EditorTextRange(location: start, length: length)),
            source: .delete,
            systemRegisters: systemRegisters
        )
        session.setSelection(EditorSelection(ranges: [EditorTextRange(location: start, length: length)]))
        session.replaceSelection(with: "")
        session.setSelection(.caret(at: min(start, session.document.buffer.utf16Length)))
        lastRepeatCommand = .deleteCharacters(count: repeatCount)
    }

    private mutating func deleteBackwardCharacters(
        count: Int,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        let buffer = session.document.buffer
        let repeatCount = max(1, count)
        let caret = session.selection.primaryRange.location
        let start = max(0, caret - repeatCount)
        let length = min(repeatCount, caret - start)
        guard length > 0 else { return }
        let range = EditorTextRange(location: start, length: length)
        storeRegister(
            buffer.string(in: range),
            source: .delete,
            systemRegisters: systemRegisters
        )
        session.setSelection(EditorSelection(ranges: [range]))
        session.replaceSelection(with: "")
        session.setSelection(.caret(at: start))
        lastRepeatCommand = .deleteBackwardCharacters(count: repeatCount)
    }

    private mutating func deleteLines(
        count: Int,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        let range = linewiseRange(count: count, session: session)
        guard range.length > 0 else { return }
        storeRegister(
            session.document.buffer.string(in: range),
            source: .delete,
            systemRegisters: systemRegisters
        )
        session.setSelection(EditorSelection(ranges: [range]))
        session.replaceSelection(with: "")
        session.setSelection(.caret(at: min(range.location, session.document.buffer.utf16Length)))
        lastRepeatCommand = .deleteLines(count: max(1, count))
    }

    private mutating func yankLines(
        count: Int,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        let range = linewiseRange(count: count, session: session)
        storeRegister(
            session.document.buffer.string(in: range),
            source: .yank,
            systemRegisters: systemRegisters
        )
    }

    private func linewiseRange(count: Int, session: EditorSession) -> EditorTextRange {
        let buffer = session.document.buffer
        let startLine = buffer.lineAndColumn(for: session.selection.primaryRange.location).line
        let start = buffer.offset(line: startLine, column: 0)
        let endLine = min(buffer.lineCount - 1, startLine + max(1, count) - 1)
        let nextLineStart = endLine + 1 < buffer.lineCount
            ? buffer.offset(line: endLine + 1, column: 0)
            : buffer.utf16Length
        return EditorTextRange(location: start, length: max(0, nextLineStart - start))
    }

    private func linewiseOperatorRange(
        for motion: Character,
        count: Int,
        session: EditorSession
    ) -> EditorTextRange? {
        let buffer = session.document.buffer
        guard buffer.lineCount > 0 else { return nil }
        let currentLine = buffer.lineAndColumn(for: session.selection.primaryRange.location).line
        let repeatCount = max(1, count)
        let targetLine: Int
        switch motion {
        case "j":
            targetLine = min(buffer.lineCount - 1, currentLine + repeatCount)
        case "k":
            targetLine = max(0, currentLine - repeatCount)
        case "G":
            targetLine = repeatCount > 1
                ? min(buffer.lineCount - 1, repeatCount - 1)
                : buffer.lineCount - 1
        case "g":
            targetLine = repeatCount > 1
                ? min(buffer.lineCount - 1, repeatCount - 1)
                : 0
        default:
            return nil
        }
        return linewiseRange(fromLine: currentLine, toLine: targetLine, in: buffer)
    }

    private func linewiseRange(from startOffset: Int, to endOffset: Int, in buffer: EditorBuffer) -> EditorTextRange? {
        guard buffer.lineCount > 0 else { return nil }
        let startLine = buffer.lineAndColumn(for: startOffset).line
        let endLine = buffer.lineAndColumn(for: endOffset).line
        return linewiseRange(fromLine: startLine, toLine: endLine, in: buffer)
    }

    private func linewiseRange(fromLine firstLine: Int, toLine secondLine: Int, in buffer: EditorBuffer) -> EditorTextRange {
        let startLine = min(firstLine, secondLine)
        let endLine = max(firstLine, secondLine)
        let start = buffer.offset(line: startLine, column: 0)
        let nextLineStart = endLine + 1 < buffer.lineCount
            ? buffer.offset(line: endLine + 1, column: 0)
            : buffer.utf16Length
        return EditorTextRange(location: start, length: max(0, nextLineStart - start))
    }

    private func lineCount(in range: EditorTextRange, buffer: EditorBuffer) -> Int {
        guard range.length > 0 else { return 0 }
        let startLine = buffer.lineAndColumn(for: range.location).line
        let endOffset = max(range.location, range.end - 1)
        let endLine = buffer.lineAndColumn(for: endOffset).line
        return max(1, endLine - startLine + 1)
    }

    private mutating func pasteRegister(
        after: Bool,
        count: Int,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        let registerText = pasteRegisterText(systemRegisters: systemRegisters)
        guard !registerText.isEmpty else { return }
        pasteText(registerText, after: after, count: count, session: &session)
        lastRepeatCommand = .paste(text: registerText, after: after, count: max(1, count))
    }

    private mutating func pasteText(
        _ text: String,
        after: Bool,
        count: Int,
        session: inout EditorSession
    ) {
        guard !text.isEmpty else { return }
        let repeatedText = String(repeating: text, count: max(1, count))
        if isLinewisePasteText(text) {
            pasteLinewiseText(repeatedText, after: after, session: &session)
        } else {
            pasteCharacterwiseText(repeatedText, after: after, session: &session)
        }
    }

    private func isLinewisePasteText(_ text: String) -> Bool {
        text.hasSuffix("\n")
    }

    private mutating func pasteLinewiseText(
        _ text: String,
        after: Bool,
        session: inout EditorSession
    ) {
        let insertOffset: Int
        if after {
            insertOffset = endOfLineIncludingNewline(
                containing: session.selection.primaryRange.location,
                in: session.document.buffer
            )
        } else {
            insertOffset = session.document.buffer.lineRange(
                containing: session.selection.primaryRange.location
            ).location
        }
        session.setSelection(.caret(at: insertOffset))
        session.replaceSelection(with: text)
        session.setSelection(.caret(at: insertOffset))
    }

    private mutating func pasteCharacterwiseText(
        _ text: String,
        after: Bool,
        session: inout EditorSession
    ) {
        let bufferLength = session.document.buffer.utf16Length
        let caret = min(max(0, session.selection.primaryRange.location), bufferLength)
        let insertOffset = after && caret < bufferLength ? caret + 1 : caret
        let insertedLength = (text as NSString).length
        session.setSelection(.caret(at: insertOffset))
        session.replaceSelection(with: text)
        session.setSelection(.caret(at: max(insertOffset, insertOffset + insertedLength - 1)))
    }

    private mutating func repeatLastChange(
        count: Int,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        guard let command = lastRepeatCommand else { return }
        for _ in 0..<max(1, count) {
            applyRepeatCommand(command, session: &session, systemRegisters: systemRegisters)
        }
    }

    private mutating func applyRepeatCommand(
        _ command: VimRepeatCommand,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        switch command {
        case let .deleteCharacters(count):
            deleteCharacters(count: count, session: &session, systemRegisters: systemRegisters)
        case let .deleteBackwardCharacters(count):
            deleteBackwardCharacters(count: count, session: &session, systemRegisters: systemRegisters)
        case let .deleteLines(count):
            deleteLines(count: count, session: &session, systemRegisters: systemRegisters)
        case let .deleteMotion(motion, count):
            applyOperator(
                "d",
                motion: motion,
                count: count,
                session: &session,
                systemRegisters: systemRegisters
            )
        case let .deleteFind(command, count):
            applyFindOperator(
                "d",
                command: command,
                count: count,
                session: &session,
                systemRegisters: systemRegisters
            )
        case let .deleteTextObject(textObject, scope, count):
            applyTextObjectOperator(
                "d",
                textObject: textObject,
                scope: scope,
                count: count,
                session: &session,
                systemRegisters: systemRegisters
            )
        case let .deleteVisualBlock(lineCount, columnCount):
            deleteVisualBlock(
                lineCount: lineCount,
                columnCount: columnCount,
                session: &session,
                systemRegisters: systemRegisters
            )
        case let .replaceCharacters(count, character):
            replaceCharactersAtCaret(count: count, with: character, session: &session)
        case let .replaceText(text):
            replaceTextAtCaret(text, session: &session)
        case let .openLine(below, insertedText):
            openLine(below: below, session: &session)
            session.replaceSelection(with: insertedText)
        case let .paste(text, after, count):
            pasteText(text, after: after, count: count, session: &session)
        case let .insertText(text):
            session.replaceSelection(with: text)
        case let .changeMotion(motion, count, insertedText):
            guard let range = changeOperatorRange(for: motion, count: count, session: session),
                  range.length > 0
            else { return }
            replaceChangeRange(
                range,
                insertedText: insertedText,
                session: &session,
                systemRegisters: systemRegisters
            )
        case let .changeFind(command, count, insertedText):
            guard let range = findOperatorRange(for: command, count: count, session: session),
                  range.length > 0
            else { return }
            replaceChangeRange(
                range,
                insertedText: insertedText,
                session: &session,
                systemRegisters: systemRegisters
            )
        case let .changeTextObject(textObject, scope, count, insertedText):
            guard let range = textObjectRange(
                for: textObject,
                scope: scope,
                count: count,
                session: session
            )
            else { return }
            replaceChangeRange(
                range,
                insertedText: insertedText,
                session: &session,
                systemRegisters: systemRegisters
            )
        case let .changeLines(count, insertedText):
            let range = linewiseRange(count: count, session: session)
            guard range.length > 0 else { return }
            replaceChangeRange(
                range,
                insertedText: insertedText,
                session: &session,
                systemRegisters: systemRegisters
            )
        }
    }

    private mutating func replaceChangeRange(
        _ range: EditorTextRange,
        insertedText: String,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        storeRegister(
            session.document.buffer.string(in: range),
            source: .delete,
            systemRegisters: systemRegisters
        )
        session.setSelection(EditorSelection(ranges: [range]))
        session.replaceSelection(with: insertedText)
    }

    private mutating func deleteVisualBlock(
        lineCount: Int,
        columnCount: Int,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        let buffer = session.document.buffer
        let start = session.selection.primaryRange.location
        let startPosition = buffer.lineAndColumn(for: start)
        let lastLine = min(buffer.lineCount - 1, startPosition.line + max(1, lineCount) - 1)
        guard startPosition.line <= lastLine else { return }

        let ranges = (startPosition.line...lastLine).map { line -> EditorTextRange in
            let rangeStart = buffer.offset(line: line, column: startPosition.column)
            let rangeEnd = buffer.offset(line: line, column: startPosition.column + max(1, columnCount))
            return EditorTextRange(location: rangeStart, length: max(0, rangeEnd - rangeStart))
        }
        guard ranges.contains(where: { $0.length > 0 }) else { return }

        let selection = EditorSelection(ranges: ranges)
        storeRegister(
            ranges.map { buffer.string(in: $0) }.joined(separator: "\n"),
            source: .delete,
            systemRegisters: systemRegisters
        )
        session.setSelection(selection)
        session.replaceSelection(with: "")
        session.setSelection(.caret(at: min(start, session.document.buffer.utf16Length)))
        lastRepeatCommand = .deleteVisualBlock(lineCount: max(1, lineCount), columnCount: max(1, columnCount))
    }

    private mutating func startMacroRecording(register: Character) {
        guard register != "_",
              let storageName = storageRegisterName(for: register)
        else { return }

        recordingMacroRegister = storageName
        if isAppendRegister(register) {
            recordingMacroInputs = macros[storageName] ?? []
        } else {
            recordingMacroInputs = []
        }
    }

    private mutating func stopMacroRecording() {
        if let register = recordingMacroRegister {
            macros[register] = recordingMacroInputs
        }
        recordingMacroRegister = nil
        recordingMacroInputs = []
    }

    private mutating func replayMacro(
        register: Character,
        count: Int,
        session: inout EditorSession,
        systemRegisters: VimSystemRegisterAccess
    ) {
        guard !isReplayingMacro,
              let storageName = storageRegisterName(for: register),
              let inputs = macros[storageName],
              !inputs.isEmpty
        else { return }

        lastMacroReplayRegister = storageName
        isReplayingMacro = true
        defer { isReplayingMacro = false }

        for _ in 0..<max(1, count) {
            for input in inputs {
                _ = handleInput(input, session: &session, systemRegisters: systemRegisters)
            }
        }
    }

    private mutating func storeRegister(
        _ text: String,
        source: VimRegisterSource,
        systemRegisters: VimSystemRegisterAccess
    ) {
        defer { pendingRegister = nil }
        guard let register = pendingRegister else {
            unnamedRegister = text
            storeAutomaticRegister(text, source: source)
            return
        }

        guard register != "_" else { return }
        unnamedRegister = text

        if let systemRegister = systemRegister(for: register) {
            systemRegisters.write(text, systemRegister)
            return
        }

        guard let storageName = storageRegisterName(for: register) else { return }
        if isAppendRegister(register) {
            registers[storageName, default: ""].append(text)
        } else {
            registers[storageName] = text
        }
    }

    private mutating func storeAutomaticRegister(_ text: String, source: VimRegisterSource) {
        switch source {
        case .yank:
            registers["0"] = text
        case .delete:
            rotateDeleteRegisters(with: text)
        }
    }

    private mutating func rotateDeleteRegisters(with text: String) {
        for digit in stride(from: 9, through: 2, by: -1) {
            let current = Character(String(digit))
            let previous = Character(String(digit - 1))
            if let value = registers[previous] {
                registers[current] = value
            } else {
                registers.removeValue(forKey: current)
            }
        }
        registers["1"] = text
    }

    private mutating func pasteRegisterText(systemRegisters: VimSystemRegisterAccess) -> String {
        defer { pendingRegister = nil }
        guard let register = pendingRegister else {
            return unnamedRegister
        }
        guard register != "_" else { return "" }
        if let systemRegister = systemRegister(for: register) {
            return systemRegisters.read(systemRegister) ?? ""
        }
        guard let storageName = storageRegisterName(for: register) else {
            return unnamedRegister
        }
        return registers[storageName] ?? ""
    }

    private func isSupportedRegister(_ register: Character) -> Bool {
        if register == "_" { return true }
        if systemRegister(for: register) != nil { return true }
        guard let scalar = String(register).unicodeScalars.first?.value else { return false }
        return (48...57).contains(scalar) || (65...90).contains(scalar) || (97...122).contains(scalar)
    }

    private func storageRegisterName(for register: Character) -> Character? {
        guard isSupportedRegister(register),
              register != "_",
              systemRegister(for: register) == nil
        else { return nil }
        return String(register).lowercased().first
    }

    private func systemRegister(for register: Character) -> VimSystemRegister? {
        switch register {
        case "+":
            return .clipboard
        case "*":
            return .primarySelection
        default:
            return nil
        }
    }

    private func isAppendRegister(_ register: Character) -> Bool {
        guard let scalar = String(register).unicodeScalars.first?.value else { return false }
        return (65...90).contains(scalar)
    }

    @discardableResult
    private mutating func applyMarkOperation(
        _ operation: VimMarkOperation,
        mark: Character,
        session: inout EditorSession
    ) -> VimFileCommand? {
        let buffer = session.document.buffer
        switch operation {
        case .set:
            guard isSettableMark(mark) else { return nil }
            if isUppercaseMark(mark), session.document.fileURL == nil {
                return nil
            }
            let offset = min(max(0, session.selection.primaryRange.location), buffer.utf16Length)
            marks[mark] = storedMark(offset: offset, session: session)
            return nil
        case .jumpExact:
            guard let mark = storedMark(for: mark, operation: operation, session: session) else { return nil }
            if let command = openFileCommandIfNeeded(for: mark, lineWise: false, session: session) {
                return command
            }
            jump(to: mark, lineWise: false, session: &session)
            return nil
        case .jumpLine:
            guard let mark = storedMark(for: mark, operation: operation, session: session) else { return nil }
            if let command = openFileCommandIfNeeded(for: mark, lineWise: true, session: session) {
                return command
            }
            jump(to: mark, lineWise: true, session: &session)
            return nil
        }
    }

    private func storedMark(offset: Int, session: EditorSession) -> VimStoredMark {
        VimStoredMark(
            documentID: session.document.id,
            fileURL: session.document.fileURL,
            offset: offset
        )
    }

    private func storedMark(
        for mark: Character,
        operation: VimMarkOperation,
        session: EditorSession
    ) -> VimStoredMark? {
        if operation == .jumpExact, mark == "`" {
            return previousJumpMark.flatMap { isSameEditorContext($0, session: session) ? $0 : nil }
        }
        if operation == .jumpLine, mark == "'" {
            return previousJumpMark.flatMap { isSameEditorContext($0, session: session) ? $0 : nil }
        }

        guard let storedMark = marks[mark] else { return nil }
        if isUppercaseMark(mark) {
            guard storedMark.fileURL != nil else { return nil }
            return storedMark
        }

        if isVisualMark(mark) {
            return isSameEditorContext(storedMark, session: session) ? storedMark : nil
        }

        guard isLowercaseMark(mark), isSameEditorContext(storedMark, session: session) else {
            return nil
        }
        return storedMark
    }

    private mutating func openFileCommandIfNeeded(
        for storedMark: VimStoredMark,
        lineWise: Bool,
        session: EditorSession
    ) -> VimFileCommand? {
        guard let markFileURL = storedMark.fileURL else { return nil }
        if let currentFileURL = session.document.fileURL, currentFileURL == markFileURL {
            return nil
        }

        let buffer = session.document.buffer
        let currentOffset = min(max(0, session.selection.primaryRange.location), buffer.utf16Length)
        previousJumpMark = self.storedMark(offset: currentOffset, session: session)
        return .openFileAtMark(url: markFileURL, offset: storedMark.offset, lineWise: lineWise)
    }

    private mutating func jump(to storedMark: VimStoredMark, lineWise: Bool, session: inout EditorSession) {
        let buffer = session.document.buffer
        let currentOffset = min(max(0, session.selection.primaryRange.location), buffer.utf16Length)
        previousJumpMark = self.storedMark(offset: currentOffset, session: session)

        let safeOffset = min(max(0, storedMark.offset), buffer.utf16Length)
        let targetOffset = lineWise
            ? firstNonblankOffset(containing: safeOffset, in: buffer)
            : safeOffset
        session.setSelection(.caret(at: targetOffset))
    }

    private func isSameEditorContext(_ storedMark: VimStoredMark, session: EditorSession) -> Bool {
        if let markFileURL = storedMark.fileURL, let currentFileURL = session.document.fileURL {
            return markFileURL == currentFileURL
        }
        return storedMark.documentID == session.document.id
    }

    private func isSupportedMark(_ mark: Character, for operation: VimMarkOperation) -> Bool {
        switch operation {
        case .set:
            return isSettableMark(mark)
        case .jumpExact:
            return mark == "`" || isSettableMark(mark) || isVisualMark(mark)
        case .jumpLine:
            return mark == "'" || isSettableMark(mark) || isVisualMark(mark)
        }
    }

    private func isSettableMark(_ mark: Character) -> Bool {
        isLowercaseMark(mark) || isUppercaseMark(mark)
    }

    private func isLowercaseMark(_ mark: Character) -> Bool {
        guard let scalar = String(mark).unicodeScalars.first?.value else { return false }
        return (97...122).contains(scalar)
    }

    private func isUppercaseMark(_ mark: Character) -> Bool {
        guard let scalar = String(mark).unicodeScalars.first?.value else { return false }
        return (65...90).contains(scalar)
    }

    private func isVisualMark(_ mark: Character) -> Bool {
        mark == "<" || mark == ">"
    }

    private func firstNonblankOffset(containing offset: Int, in buffer: EditorBuffer) -> Int {
        let nsText = buffer.text as NSString
        guard nsText.length > 0 else { return 0 }

        let safeOffset = min(max(0, offset), nsText.length)
        let lineRange = buffer.lineRange(containing: safeOffset)
        let lineStart = min(max(0, lineRange.location), nsText.length)
        let lineEnd = min(nsText.length, lineRange.location + lineRange.length)

        var index = lineStart
        while index < lineEnd {
            let character = nsText.character(at: index)
            if character == 10 || character == 13 {
                break
            }
            if !isWhitespace(character) {
                return index
            }
            index += 1
        }
        return lineStart
    }

    private mutating func openLine(below: Bool, session: inout EditorSession) {
        let buffer = session.document.buffer
        let currentLine = buffer.lineAndColumn(for: session.selection.primaryRange.location).line
        let insertOffset: Int
        let caretOffset: Int
        if below {
            let lineRange = buffer.lineRange(containing: session.selection.primaryRange.location)
            insertOffset = min(buffer.utf16Length, lineRange.location + lineRange.length)
            let lineHasTerminator = buffer.string(in: lineRange).hasSuffix("\n")
            caretOffset = insertOffset + (lineHasTerminator ? 0 : 1)
        } else {
            insertOffset = buffer.offset(line: currentLine, column: 0)
            caretOffset = insertOffset
        }
        session.setSelection(.caret(at: insertOffset))
        session.replaceSelection(with: "\n")
        session.setSelection(.caret(at: caretOffset))
    }

    private func lineLastCharacterOffset(containing offset: Int, in buffer: EditorBuffer) -> Int {
        let lineRange = buffer.lineRange(containing: offset)
        let lineText = buffer.string(in: lineRange) as NSString
        var end = lineRange.location + lineRange.length
        while end > lineRange.location {
            let character = lineText.character(at: end - lineRange.location - 1)
            if character == 10 || character == 13 {
                end -= 1
            } else {
                break
            }
        }
        return max(lineRange.location, end - 1)
    }

    private func endOfLineIncludingNewline(containing offset: Int, in buffer: EditorBuffer) -> Int {
        let lineRange = buffer.lineRange(containing: offset)
        return min(buffer.utf16Length, lineRange.location + lineRange.length)
    }

    private func matchingDelimiterOffset(from offset: Int, in buffer: EditorBuffer) -> Int? {
        let nsText = buffer.text as NSString
        guard nsText.length > 0 else { return nil }
        let safeOffset = min(max(0, offset), nsText.length - 1)

        if let match = matchingDelimiter(at: safeOffset, in: nsText) {
            return match
        }

        let line = lineBounds(containing: safeOffset, in: nsText)
        var index = safeOffset
        while index < line.contentsEnd {
            if delimiterInfo(for: nsText.character(at: index)) != nil {
                return matchingDelimiter(at: index, in: nsText)
            }
            index += 1
        }
        return nil
    }

    private func matchingDelimiter(at offset: Int, in nsText: NSString) -> Int? {
        guard let info = delimiterInfo(for: nsText.character(at: offset)) else { return nil }

        if info.isOpening {
            var depth = 0
            var index = offset
            while index < nsText.length {
                let code = nsText.character(at: index)
                if code == info.open {
                    depth += 1
                } else if code == info.close {
                    depth -= 1
                    if depth == 0 {
                        return index
                    }
                }
                index += 1
            }
        } else {
            var depth = 0
            var index = offset
            while index >= 0 {
                let code = nsText.character(at: index)
                if code == info.close {
                    depth += 1
                } else if code == info.open {
                    depth -= 1
                    if depth == 0 {
                        return index
                    }
                }
                if index == 0 { break }
                index -= 1
            }
        }

        return nil
    }

    private func delimiterInfo(for code: unichar) -> (open: unichar, close: unichar, isOpening: Bool)? {
        switch code {
        case 40: return (40, 41, true)
        case 41: return (40, 41, false)
        case 91: return (91, 93, true)
        case 93: return (91, 93, false)
        case 123: return (123, 125, true)
        case 125: return (123, 125, false)
        default: return nil
        }
    }

    private func findMotionOffset(
        from offset: Int,
        command: VimFindCommand,
        count: Int,
        in buffer: EditorBuffer
    ) -> Int? {
        guard let target = findTargetOffset(from: offset, command: command, count: count, in: buffer) else {
            return nil
        }

        switch command.command {
        case "f", "F":
            return target
        case "t":
            return max(offset, target - 1)
        case "T":
            return min(buffer.utf16Length, target + 1)
        default:
            return nil
        }
    }

    private func findTargetOffset(
        from offset: Int,
        command: VimFindCommand,
        count: Int,
        in buffer: EditorBuffer
    ) -> Int? {
        guard let targetCode = utf16Code(for: command.target) else { return nil }
        let nsText = buffer.text as NSString
        guard nsText.length > 0 else { return nil }

        let safeOffset = min(max(0, offset), nsText.length - 1)
        let line = lineBounds(containing: safeOffset, in: nsText)
        let repeatCount = max(1, count)

        switch command.command {
        case "f", "t":
            var matchesRemaining = repeatCount
            var index = min(safeOffset + 1, line.contentsEnd)
            while index < line.contentsEnd {
                if nsText.character(at: index) == targetCode {
                    matchesRemaining -= 1
                    if matchesRemaining == 0 {
                        return index
                    }
                }
                index += 1
            }
        case "F", "T":
            var matchesRemaining = repeatCount
            var index = min(safeOffset - 1, line.contentsEnd - 1)
            while index >= line.start {
                if nsText.character(at: index) == targetCode {
                    matchesRemaining -= 1
                    if matchesRemaining == 0 {
                        return index
                    }
                }
                if index == 0 { break }
                index -= 1
            }
        default:
            return nil
        }
        return nil
    }

    private func nextWordStart(after offset: Int, in buffer: EditorBuffer) -> Int {
        let nsText = buffer.text as NSString
        var index = min(max(0, offset), nsText.length)
        while index < nsText.length, isWordCharacter(nsText.character(at: index)) {
            index += 1
        }
        while index < nsText.length, !isWordCharacter(nsText.character(at: index)) {
            index += 1
        }
        return index
    }

    private func nextBigWordStart(after offset: Int, in buffer: EditorBuffer) -> Int {
        let nsText = buffer.text as NSString
        var index = min(max(0, offset), nsText.length)
        while index < nsText.length, !isWhitespace(nsText.character(at: index)) {
            index += 1
        }
        while index < nsText.length, isWhitespace(nsText.character(at: index)) {
            index += 1
        }
        return index
    }

    private func previousWordStart(before offset: Int, in buffer: EditorBuffer) -> Int {
        let nsText = buffer.text as NSString
        var index = min(max(0, offset), nsText.length)
        if index > 0 { index -= 1 }
        while index > 0, !isWordCharacter(nsText.character(at: index)) {
            index -= 1
        }
        while index > 0, isWordCharacter(nsText.character(at: index - 1)) {
            index -= 1
        }
        return index
    }

    private func previousBigWordStart(before offset: Int, in buffer: EditorBuffer) -> Int {
        let nsText = buffer.text as NSString
        var index = min(max(0, offset), nsText.length)
        if index > 0 { index -= 1 }
        while index > 0, isWhitespace(nsText.character(at: index)) {
            index -= 1
        }
        while index > 0, !isWhitespace(nsText.character(at: index - 1)) {
            index -= 1
        }
        return index
    }

    private func isWordCharacter(_ character: unichar) -> Bool {
        if character >= 48, character <= 57 { return true }
        if character >= 65, character <= 90 { return true }
        if character >= 97, character <= 122 { return true }
        return character == 95
    }

    private func isWhitespace(_ character: unichar) -> Bool {
        character == 9 || character == 10 || character == 13 || character == 32
    }

    private func utf16Code(for character: Character) -> unichar? {
        String(character).utf16.first
    }
}
