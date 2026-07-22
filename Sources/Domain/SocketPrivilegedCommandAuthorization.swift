// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SocketPrivilegedCommandAuthorization.swift - Exact, one-use approval intents for local socket commands.

import CocxyShared
import CryptoKit
import Foundation

typealias SocketPrivilegedCommandCategory = CocxyPrivilegedSocketCommandCategory

enum SocketCommandAuthorizationPolicy: Equatable, Sendable {
    case ordinary
    case privileged(SocketPrivilegedCommandCategory)
}

struct SocketPrivilegedCommandAuthorizationRequest: Equatable, Sendable {
    static let authorizationLifetime: TimeInterval = 60

    let id: UUID
    let command: CLICommandName
    let category: SocketPrivilegedCommandCategory
    let params: [String: String]
    let authorizationDigest: String
    let createdAt: Date
    let expiresAt: Date

    init?(
        socketRequest: SocketRequest,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        lifetime: TimeInterval = authorizationLifetime
    ) {
        guard let command = CLICommandName(rawValue: socketRequest.command),
              case .privileged(let category) = SocketPrivilegedCommandSecurity.policy(for: command),
              SocketPrivilegedCommandSecurity.hasBoundedParameters(socketRequest.params ?? [:]),
              lifetime > 0 else {
            return nil
        }

        let params = socketRequest.params ?? [:]
        let preview = SocketPrivilegedCommandSecurity.approvalPreview(
            command: command,
            category: category,
            params: params
        )
        guard preview.utf8.count <= SocketPrivilegedCommandSecurity.maxApprovalPreviewBytes else {
            return nil
        }

        self.id = id
        self.command = command
        self.category = category
        self.params = params
        self.createdAt = createdAt
        expiresAt = createdAt.addingTimeInterval(lifetime)
        authorizationDigest = SocketPrivilegedCommandSecurity.digest(
            command: command,
            category: category,
            params: params
        )
    }

    func isValid(at date: Date) -> Bool {
        expiresAt > createdAt
            && date >= createdAt
            && date < expiresAt
            && SocketPrivilegedCommandSecurity.policy(for: command) == .privileged(category)
            && SocketPrivilegedCommandSecurity.hasBoundedParameters(params)
            && authorizationDigest == SocketPrivilegedCommandSecurity.digest(
                command: command,
                category: category,
                params: params
            )
    }
}

struct SocketPrivilegedCommandContext: Equatable, @unchecked Sendable {
    enum Scope: String, Equatable, Sendable {
        case terminalSurface = "terminal-surface"
        case terminalTab = "terminal-tab"
        case browserPage = "browser-page"
        case browserNavigation = "browser-navigation"
        case browserGlobal = "browser-global"
        case repository
        case localExecution = "local-execution"
        case computeCell = "compute-cell"
        case remoteConnection = "remote-connection"
        case internalTrusted = "internal-trusted"
    }

    let scope: Scope
    let windowControllerIdentifier: ObjectIdentifier?
    let tabID: UUID?
    let workingDirectory: String
    let localResourcePaths: [String: String]
    let localResourceDigests: [String: String]
    let surfaceID: UUID?
    let browserViewModelIdentifier: ObjectIdentifier?
    let browserTabID: UUID?
    let browserURL: String?
    let browserWebViewIdentifier: ObjectIdentifier?
    let browserNavigationGeneration: UInt64?
    let browserProfileID: UUID?
    let targetDisplayName: String

    init(
        scope: Scope,
        windowControllerIdentifier: ObjectIdentifier?,
        tabID: UUID?,
        workingDirectory: String,
        localResourcePaths: [String: String] = [:],
        localResourceDigests: [String: String] = [:],
        surfaceID: UUID?,
        browserViewModelIdentifier: ObjectIdentifier?,
        browserTabID: UUID?,
        browserURL: String?,
        browserWebViewIdentifier: ObjectIdentifier? = nil,
        browserNavigationGeneration: UInt64? = nil,
        browserProfileID: UUID? = nil,
        targetDisplayName: String
    ) {
        self.scope = scope
        self.windowControllerIdentifier = windowControllerIdentifier
        self.tabID = tabID
        self.workingDirectory = workingDirectory
        self.localResourcePaths = localResourcePaths
        self.localResourceDigests = localResourceDigests
        self.surfaceID = surfaceID
        self.browserViewModelIdentifier = browserViewModelIdentifier
        self.browserTabID = browserTabID
        self.browserURL = browserURL
        self.browserWebViewIdentifier = browserWebViewIdentifier
        self.browserNavigationGeneration = browserNavigationGeneration
        self.browserProfileID = browserProfileID
        self.targetDisplayName = targetDisplayName
    }

    static func internalTrusted(for request: SocketPrivilegedCommandAuthorizationRequest) -> Self {
        Self(
            scope: .internalTrusted,
            windowControllerIdentifier: nil,
            tabID: nil,
            workingDirectory: "Internal permission boundary",
            surfaceID: nil,
            browserViewModelIdentifier: nil,
            browserTabID: nil,
            browserURL: nil,
            targetDisplayName: request.command.rawValue
        )
    }

    func bindingLocalResourcePaths(
        in params: [String: String],
        keys: [String],
        requiredScope: Scope
    ) -> [String: String]? {
        if scope == .internalTrusted {
            return params
        }
        guard scope == requiredScope else { return nil }

        var bound = params
        for key in keys where params[key] != nil {
            guard let approvedPath = localResourcePaths[key] else { return nil }
            bound[key] = approvedPath
        }
        return bound
    }
}

final class SocketPrivilegedCommandAuthorizationGrant: @unchecked Sendable {
    let requestID: UUID
    let command: CLICommandName
    let authorizationDigest: String
    let context: SocketPrivilegedCommandContext
    let issuedAt: Date
    let expiresAt: Date

    private let lock = NSLock()
    private var consumed = false

    init(
        request: SocketPrivilegedCommandAuthorizationRequest,
        context: SocketPrivilegedCommandContext,
        issuedAt: Date = Date()
    ) {
        requestID = request.id
        command = request.command
        authorizationDigest = request.authorizationDigest
        self.context = context
        self.issuedAt = issuedAt
        expiresAt = request.expiresAt
    }

    static func internalTrusted(
        for request: SocketPrivilegedCommandAuthorizationRequest
    ) -> SocketPrivilegedCommandAuthorizationGrant {
        SocketPrivilegedCommandAuthorizationGrant(
            request: request,
            context: .internalTrusted(for: request)
        )
    }

    func consume(
        for request: SocketPrivilegedCommandAuthorizationRequest,
        at date: Date = Date()
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !consumed,
              request.isValid(at: date),
              requestID == request.id,
              command == request.command,
              authorizationDigest == request.authorizationDigest,
              issuedAt >= request.createdAt,
              issuedAt < request.expiresAt,
              date < expiresAt else {
            return false
        }
        consumed = true
        return true
    }

    func remainsValid(at date: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return consumed && date >= issuedAt && date < expiresAt
    }
}

typealias SocketPrivilegedCommandAuthorizationProvider = @Sendable (
    SocketPrivilegedCommandAuthorizationRequest
) -> SocketPrivilegedCommandAuthorizationGrant?

final class SocketPrivilegedCommandExecutionSession: @unchecked Sendable {
    enum Outcome: Equatable {
        case pending
        case granted
        case denied
    }

    let request: SocketPrivilegedCommandAuthorizationRequest
    private let authorizationProvider: SocketPrivilegedCommandAuthorizationProvider
    private let condition = NSCondition()
    private var storedOutcome: Outcome = .pending
    private var storedGrant: SocketPrivilegedCommandAuthorizationGrant?
    private var authorizationInFlight = false

    init(
        request: SocketPrivilegedCommandAuthorizationRequest,
        authorizationProvider: @escaping SocketPrivilegedCommandAuthorizationProvider
    ) {
        self.request = request
        self.authorizationProvider = authorizationProvider
    }

    var outcome: Outcome {
        condition.lock()
        defer { condition.unlock() }
        return storedOutcome
    }

    var grant: SocketPrivilegedCommandAuthorizationGrant? {
        condition.lock()
        defer { condition.unlock() }
        guard storedOutcome == .granted,
              let storedGrant,
              storedGrant.remainsValid() else {
            return nil
        }
        return storedGrant
    }

    func authorize() -> Bool {
        condition.lock()
        while storedOutcome == .pending && authorizationInFlight {
            guard condition.wait(until: request.expiresAt) else {
                condition.unlock()
                return false
            }
        }
        switch storedOutcome {
        case .granted:
            let isValid = storedGrant?.remainsValid() == true
            condition.unlock()
            return isValid
        case .denied:
            condition.unlock()
            return false
        case .pending:
            authorizationInFlight = true
            condition.unlock()
        }

        let candidate = authorizationProvider(request)
        let consumed = candidate?.consume(for: request) == true

        condition.lock()
        defer {
            authorizationInFlight = false
            condition.broadcast()
            condition.unlock()
        }
        guard consumed, let candidate else {
            storedOutcome = .denied
            storedGrant = nil
            return false
        }

        storedGrant = candidate
        storedOutcome = .granted
        return true
    }
}

enum SocketPrivilegedCommandExecutionContext {
    private static let threadKey = "dev.cocxy.socket.privileged-execution-session"

    static var currentGrant: SocketPrivilegedCommandAuthorizationGrant? {
        currentSession?.grant
    }

    static func authorizeCurrentSession(allowWithoutSession: Bool = false) -> Bool {
        guard let currentSession else { return allowWithoutSession }
        return currentSession.authorize()
    }

    static func withSession<T>(
        _ session: SocketPrivilegedCommandExecutionSession,
        operation: () -> T
    ) -> T {
        let dictionary = Thread.current.threadDictionary
        let previous = dictionary[threadKey]
        dictionary[threadKey] = SessionBox(session)
        defer {
            if let previous {
                dictionary[threadKey] = previous
            } else {
                dictionary.removeObject(forKey: threadKey)
            }
        }
        return operation()
    }

    private static var currentSession: SocketPrivilegedCommandExecutionSession? {
        (Thread.current.threadDictionary[threadKey] as? SessionBox)?.session
    }

    private final class SessionBox: NSObject {
        let session: SocketPrivilegedCommandExecutionSession

        init(_ session: SocketPrivilegedCommandExecutionSession) {
            self.session = session
        }
    }
}

enum SocketPrivilegedCommandSecurity {
    static let maxParameterCount = 64
    static let maxParameterKeyBytes = 256
    static let maxParameterValueBytes = 32_768
    static let maxApprovalPreviewBytes = 49_152
    static let maxBoundLocalResourceBytes = 1 * 1_024 * 1_024

    static func policy(for command: CLICommandName) -> SocketCommandAuthorizationPolicy {
        switch command {
        case .send,
             .sendKey,
             .timelineShow,
             .timelineExport,
             .search,
             .capturePane,
             .ssh,
             .cellCreate,
             .cellList,
             .cellExec,
             .cellAttach,
             .cellDestroy,
             .cellLogs,
             .cellStatus,
             .browserNavigate,
             .browserBack,
             .browserForward,
             .browserReload,
             .browserGetState,
             .browserStateSave,
             .browserStateLoad,
             .browserEval,
             .browserAddScript,
             .browserAddStyle,
             .browserInitScriptRemove,
             .browserInitScriptsList,
             .browserDialogs,
             .browserDialogAccept,
             .browserDialogDismiss,
             .browserGetText,
             .browserListTabs,
             .browserSnapshot,
             .browserContext,
             .browserClick,
             .browserDblClick,
             .browserHover,
             .browserFocus,
             .browserFill,
             .browserUpload,
             .browserType,
             .browserPress,
             .browserKeyDown,
             .browserKeyUp,
             .browserCheck,
             .browserUncheck,
             .browserSelect,
             .browserScroll,
             .browserScrollIntoView,
             .browserGetHTML,
             .browserGetValue,
             .browserGetAttr,
             .browserGetTitle,
             .browserGetCount,
             .browserGetBox,
             .browserGetStyles,
             .browserIsVisible,
             .browserIsEnabled,
             .browserIsChecked,
             .browserFindRole,
             .browserFindText,
             .browserFindLabel,
             .browserFindPlaceholder,
             .browserFindAlt,
             .browserFindTitle,
             .browserFindTestID,
             .browserFindFirst,
             .browserFindLast,
             .browserFindNth,
             .browserScreenshot,
             .browserConsole,
             .browserWait,
             .browserCookiesList,
             .browserCookiesSet,
             .browserCookiesDelete,
             .browserNetwork,
             .browserFrames,
             .browserDownloads,
             .browserStorageList,
             .browserStorageGet,
             .browserStorageSet,
             .browserStorageDelete,
             .browserImportPreview,
             .browserImportRun,
             .agentTeamLaunch,
             .agentTeamStop,
             .webStart,
             .webStop,
             .webStatus,
             .streamList,
             .streamCurrent,
             .protocolCapabilities,
             .protocolViewport,
             .protocolSend,
             .coreReset,
             .coreSignal,
             .coreProcess,
             .coreModes,
             .coreSearch,
             .coreLigatures,
             .coreProtocol,
             .coreSelection,
             .coreFontMetrics,
             .corePreedit,
             .coreSemantic,
             .blockList,
             .blockOutputs,
             .blockCopy,
             .blockRerun,
             .imageList,
             .imageDelete,
             .imageClear,
             .notebookImport,
             .notebookExport,
             .notebookExportHTML,
             .notebookTemplateCreate,
             .notebookRun,
             .workflowRun,
             .gitAssistantCommitMessage,
             .gitAssistantPRDraft,
             .gitAssistantReleaseNotes:
            guard let category = CocxyPrivilegedSocketCommandPolicy.category(
                forRawCommand: command.rawValue
            ) else {
                preconditionFailure("Privileged socket policy drifted for \(command.rawValue)")
            }
            return .privileged(category)

        case .notify,
             .newTab,
             .listTabs,
             .focusTab,
             .closeTab,
             .split,
             .status,
             .hookEvent,
             .hooks,
             .hookHandler,
             .setupHooks,
             .review,
             .reviewRefresh,
             .reviewSubmit,
             .reviewStats,
             .reviewApprove,
             .reviewRequestChanges,
             .tabRename,
             .tabMove,
             .tabConfigSave,
             .tabConfigOpen,
             .tabConfigList,
             .tabConfigPath,
             .tabConfigExport,
             .splitList,
             .splitFocus,
             .splitClose,
             .splitResize,
             .dashboardShow,
             .dashboardHide,
             .dashboardToggle,
             .dashboardStatus,
             .richInputShow,
             .configGet,
             .configSet,
             .configPath,
             .configProject,
             .importConfig,
             .themeList,
             .themeSet,
             .vaultOpen,
             .remoteList,
             .remoteConnect,
             .remoteDisconnect,
             .remoteStatus,
             .remoteTunnels,
             .pluginList,
             .pluginEnable,
             .pluginDisable,
             .pluginSourceList,
             .pluginSourceAdd,
             .pluginInstall,
             .pluginUninstall,
             .sandboxListGrants,
             .sandboxRevoke,
             .browserSplit,
             .browserInitScriptAdd,
             .agentTeamList,
             .windowNew,
             .windowList,
             .windowFocus,
             .windowClose,
             .windowFullscreen,
             .notebookTemplateList,
             .skillList,
             .skillSourceList,
             .skillSourceAdd,
             .skillInstall,
             .skillUninstall,
             .sessionSave,
             .sessionRestore,
             .sessionList,
             .sessionDelete,
             .tabDuplicate,
             .tabPin,
             .configList,
             .configReload,
             .splitSwap,
             .splitZoom,
             .notificationList,
             .notificationClear,
             .worktreeAdd,
             .worktreeList,
             .worktreeFocus,
             .worktreeRemove,
             .worktreePrune,
             .worktreeCleanupMerged,
             .githubStatus,
             .githubPRs,
             .githubIssues,
             .githubOpen,
             .githubRefresh,
             .githubPRMerge:
            return .ordinary
        }
    }

    static func category(for command: CLICommandName) -> SocketPrivilegedCommandCategory? {
        guard case .privileged(let category) = policy(for: command) else { return nil }
        return category
    }

    static func hasBoundedParameters(_ params: [String: String]) -> Bool {
        guard params.count <= maxParameterCount else { return false }
        return params.allSatisfy { key, value in
            !key.isEmpty
                && key.utf8.count <= maxParameterKeyBytes
                && value.utf8.count <= maxParameterValueBytes
                && !key.contains("\0")
                && !value.contains("\0")
        }
    }

    static func approvalPreview(_ request: SocketPrivilegedCommandAuthorizationRequest) -> String {
        approvalPreview(
            command: request.command,
            category: request.category,
            params: request.params
        )
    }

    static func approvalPreview(
        command: CLICommandName,
        category: SocketPrivilegedCommandCategory,
        params: [String: String]
    ) -> String {
        var lines = [
            "Command: \(escapedPreview(command.rawValue))",
            "Category: \(category.rawValue)",
        ]
        if params.isEmpty {
            lines.append("Parameters: (none)")
        } else {
            lines.append("Parameters:")
            for key in params.keys.sorted() {
                lines.append("\(escapedPreview(key)):\n\(escapedPreview(params[key] ?? ""))")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func digest(
        command: CLICommandName,
        category: SocketPrivilegedCommandCategory,
        params: [String: String]
    ) -> String {
        var components = [command.rawValue, category.rawValue]
        for key in params.keys.sorted() {
            components.append(key)
            components.append(params[key] ?? "")
        }

        var canonical = ""
        for component in components {
            canonical += "\(component.utf8.count):\(component)"
        }
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func digest(data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func boundedFileDigest(
        at url: URL,
        maximumBytes: Int = maxBoundLocalResourceBytes,
        fileManager: FileManager = .default
    ) -> String? {
        boundedFileData(
            at: url,
            maximumBytes: maximumBytes,
            fileManager: fileManager
        ).map { digest(data: $0) }
    }

    static func boundedFileData(
        at url: URL,
        maximumBytes: Int = maxBoundLocalResourceBytes,
        fileManager: FileManager = .default
    ) -> Data? {
        guard maximumBytes > 0,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.intValue,
              size <= maximumBytes,
              let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: maximumBytes + 1),
              data.count <= maximumBytes else {
            return nil
        }
        return data
    }

    static func escapedPreview(_ value: String) -> String {
        var preview = ""
        for scalar in value.unicodeScalars {
            if scalar == "\\" {
                preview += "\\\\"
            } else if scalar == "\t" {
                preview += "\\t"
            } else if scalar == "\n" {
                preview += "\\n\n"
            } else if scalar == "\r" {
                preview += "\\r"
            } else {
                switch scalar.properties.generalCategory {
                case .control, .format, .lineSeparator, .paragraphSeparator:
                    preview += String(format: "\\u{%04X}", scalar.value)
                default:
                    preview.unicodeScalars.append(scalar)
                }
            }
        }
        return preview
    }
}
