// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandRunner.swift - Orchestrates parsing, socket communication, and output.

import Foundation
import CocxyShared
import CocxyInputClassifier
import CocxyCommandSignatures
import CocxyCommandCorrections
import CocxyVault

// MARK: - Command Runner

/// Orchestrates the full CLI lifecycle: parse arguments, send to server, format output.
///
/// This is the top-level coordination layer. It delegates:
/// - Argument parsing to `CLIArgumentParser`.
/// - Socket communication to `SocketClient`.
/// - Output formatting to `OutputFormatter`.
public struct CommandRunner {
    static let extendedGitHubReadSocketTimeoutSeconds: TimeInterval = 25
    static let extendedGitHubMutationSocketTimeoutSeconds: TimeInterval = 65
    public static let extendedGitAssistantSocketTimeoutSeconds: TimeInterval = 65

    /// The socket client to use for communication.
    public let socketClient: SocketClient
    public let signatureKeyStore: SignatureKeychainStore
    public let trustedAuthorRegistryURL: URL
    public let vaultStore: any VaultSessionStoring

    /// Creates a command runner with a socket client.
    ///
    /// - Parameter socketClient: The socket client. Defaults to a new instance
    ///   with the default socket path.
    public init(
        socketClient: SocketClient = SocketClient(),
        signatureKeyStore: SignatureKeychainStore = SignatureKeychainStore(),
        trustedAuthorRegistryURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy/security/trusted-authors.json"),
        vaultStore: any VaultSessionStoring = VaultSessionStore.defaultStore()
    ) {
        self.socketClient = socketClient
        self.signatureKeyStore = signatureKeyStore
        self.trustedAuthorRegistryURL = trustedAuthorRegistryURL
        self.vaultStore = vaultStore
    }

    /// Runs the CLI with the given arguments.
    ///
    /// - Parameter arguments: The arguments array (excluding the program name).
    /// - Returns: A `CLIResult` with the exit code and output.
    public func run(arguments: [String]) -> CLIResult {
        var parsedCommand: ParsedCommand
        do {
            parsedCommand = try CLIArgumentParser.parse(arguments)
        } catch let error as CLIError {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: OutputFormatter.formatError(error)
            )
        } catch {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: "Error: \(error.localizedDescription)"
            )
        }
        if let commandWithBody = parsedCommand.fillingReviewBodyFromStdinIfNeeded() {
            parsedCommand = commandWithBody
        }

        // Handle commands that don't need the server.
        switch parsedCommand {
        case .help:
            return CLIResult(
                exitCode: 0,
                stdout: CLIArgumentParser.helpText(),
                stderr: ""
            )
        case .version:
            return CLIResult(
                exitCode: 0,
                stdout: CLIArgumentParser.versionText(),
                stderr: ""
            )
        case .hooksInstall:
            return executeHooksInstall()
        case .hooksUninstall:
            return executeHooksUninstall()
        case .hooksStatus:
            return executeHooksStatus()
        case .hookHandler:
            return HookHandlerCommand.execute(socketClient: socketClient)
        case .setupHooks(let agent, let remove, let dryRun, let check, let opencodeProject):
            return SetupHooksCommand.execute(
                target: agent,
                remove: remove,
                dryRun: dryRun,
                check: check,
                opencodeProject: opencodeProject
            )
        case .editorOpen(let path, let editor, let line, let column):
            return executeEditorOpen(path: path, editor: editor, line: line, column: column)
        case .classify(let input):
            return executeClassify(input: input)
        case .correct(let input):
            return executeCorrect(input: input)
        case .identify:
            return executeIdentify()
        case .capabilities:
            return executeCapabilities()
        case .top(let mode):
            return CLITopCommand(socketClient: socketClient).run(mode: mode)
        case .vaultList:
            return executeVaultList()
        case .vaultClear:
            return executeVaultClear()
        case .vaultResume(let agent, let sessionID, let dryRun):
            return executeVaultResume(agent: agent, sessionID: sessionID, dryRun: dryRun)
        case .keysGenerate(let author):
            return executeKeysGenerate(author: author)
        case .keysList:
            return executeKeysList()
        case .keysExportPublic(let keyID, let outputPath):
            return executeKeysExportPublic(keyID: keyID, outputPath: outputPath)
        case .keysImport(let path):
            return executeKeysImport(path: path)
        case .signArtifact(let kind, let path, let keyID, let author):
            return executeSignArtifact(kind: kind, path: path, keyID: keyID, author: author)
        case .verifyArtifact(let kind, let path, let publicKeyPath):
            return executeVerifyArtifact(kind: kind, path: path, publicKeyPath: publicKeyPath)
        default:
            break
        }

        // Build the socket request.
        let request = buildRequest(from: parsedCommand)

        // Send to server.
        let response: CLISocketResponse
        do {
            response = try socketClient(for: parsedCommand).send(request)
        } catch let error as CLIError {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: OutputFormatter.formatError(error)
            )
        } catch {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: "Error: \(error.localizedDescription)"
            )
        }

        // Format the response.
        if response.success {
            let output = OutputFormatter.formatSuccess(
                command: parsedCommand,
                response: response
            )
            return CLIResult(exitCode: 0, stdout: output, stderr: "")
        } else {
            let errorMessage = response.error ?? "Unknown error"
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: CLIError.serverError(errorMessage).userMessage
            )
        }
    }

    // MARK: - Local Commands: Hooks

    /// Executes `hooks install` locally (no socket needed).
    private func executeHooksInstall() -> CLIResult {
        let manager = ClaudeSettingsManager()
        do {
            let result = try manager.installHooks()
            if result.alreadyInstalled {
                return CLIResult(
                    exitCode: 0,
                    stdout: "Hooks already installed.",
                    stderr: ""
                )
            }
            let events = result.hookEvents.joined(separator: ", ")
            return CLIResult(
                exitCode: 0,
                stdout: "Hooks installed for events: \(events)",
                stderr: ""
            )
        } catch {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: "Error: Failed to install hooks: \(error.localizedDescription)"
            )
        }
    }

    /// Executes `hooks uninstall` locally (no socket needed).
    private func executeHooksUninstall() -> CLIResult {
        let manager = ClaudeSettingsManager()
        do {
            let result = try manager.uninstallHooks()
            if result.nothingToRemove {
                return CLIResult(
                    exitCode: 0,
                    stdout: "No Cocxy hooks found to remove.",
                    stderr: ""
                )
            }
            let events = result.removedEvents.joined(separator: ", ")
            return CLIResult(
                exitCode: 0,
                stdout: "Hooks removed for events: \(events)",
                stderr: ""
            )
        } catch {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: "Error: Failed to uninstall hooks: \(error.localizedDescription)"
            )
        }
    }

    /// Executes `hooks status` locally (no socket needed).
    private func executeHooksStatus() -> CLIResult {
        let manager = ClaudeSettingsManager()
        do {
            let status = try manager.hooksStatus()
            if status.installed {
                let events = status.installedEvents.joined(separator: ", ")
                return CLIResult(
                    exitCode: 0,
                    stdout: "Cocxy hooks installed for: \(events)",
                    stderr: ""
                )
            } else {
                return CLIResult(
                    exitCode: 0,
                    stdout: "Cocxy hooks not installed. Run 'cocxy hooks install' to set up.",
                    stderr: ""
                )
            }
        } catch {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: "Error: Failed to check hooks status: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Local Commands: Editor Integration

    /// Executes `cocxy open` locally. Opening external editors is a
    /// host-side concern and should not require a running app socket.
    private func executeEditorOpen(path: String, editor: String?, line: Int?, column: Int?) -> CLIResult {
        let request = EditorOpenRequest(filePath: path, editorID: editor, line: line, column: column)
        let launcher = EditorRegistry.launcher(matching: editor)
        let executablePath = launcher?.executableNames.lazy.compactMap { Self.resolveExecutable(named: $0) }.first
        let bundleIdentifier = launcher?.bundleIdentifiers.first
        let plan = EditorLaunchPlanner.plan(
            request: request,
            launcher: launcher,
            executablePath: executablePath,
            bundleIdentifier: bundleIdentifier
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.executablePath)
        process.arguments = plan.arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: "Error: Failed to open \(path): \(error.localizedDescription)"
            )
        }

        guard process.terminationStatus == 0 else {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return CLIResult(
                exitCode: process.terminationStatus,
                stdout: "",
                stderr: "Error: Failed to open \(path) in \(plan.displayName)\(stderr.map { ": \($0)" } ?? ".")"
            )
        }

        return CLIResult(
            exitCode: 0,
            stdout: "Opened \(URL(fileURLWithPath: path).standardizedFileURL.path) in \(plan.displayName).",
            stderr: ""
        )
    }

    private static func resolveExecutable(named name: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"]
            ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in path.split(separator: ":").map(String.init) {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Local Commands: Input Classification

    /// Executes `cocxy classify` locally. The command does not require the
    /// app socket because the input may contain sensitive shell text.
    private func executeClassify(input: String) -> CLIResult {
        let classifier = InputClassifierComposer()
        let classification = Self.runBlocking {
            await classifier.classify(input)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(classification)
            return CLIResult(
                exitCode: 0,
                stdout: String(decoding: data, as: UTF8.self),
                stderr: ""
            )
        } catch {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: "Error: Failed to encode classification: \(error.localizedDescription)"
            )
        }
    }

    /// Executes `cocxy correct` locally. The command may include sensitive
    /// shell text, so suggestions are generated in-process and never require
    /// the app socket.
    private func executeCorrect(input: String) -> CLIResult {
        let engine = CommandCorrectionEngine.localDefault()
        let suggestions = engine.corrections(
            for: CommandCorrectionContext(command: input, exitCode: 127)
        )
        let json: [String: Any] = [
            "command": input,
            "count": suggestions.count,
            "suggestions": suggestions.map { correction in
                [
                    "suggestion": correction.suggestion,
                    "reason": correction.reason,
                    "confidence": correction.confidence,
                    "source": correction.source.rawValue
                ] as [String: Any]
            }
        ]
        return jsonResult(json)
    }

    private static func runBlocking<T: Sendable>(
        _ operation: @escaping @Sendable () async -> T
    ) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = CLIValueBox<T>()
        Task {
            let value = await operation()
            box.store(value)
            semaphore.signal()
        }
        semaphore.wait()
        return box.load()!
    }

    // MARK: - Local Commands: Discovery

    private func executeIdentify() -> CLIResult {
        do {
            return CLIResult(
                exitCode: 0,
                stdout: try CLIEnvironmentDiscovery.json(for: CLIEnvironmentDiscovery.identity()),
                stderr: ""
            )
        } catch {
            return errorResult("Failed to encode identity", error)
        }
    }

    private func executeCapabilities() -> CLIResult {
        do {
            return CLIResult(
                exitCode: 0,
                stdout: try CLIEnvironmentDiscovery.json(for: CLIEnvironmentDiscovery.capabilities()),
                stderr: ""
            )
        } catch {
            return errorResult("Failed to encode capabilities", error)
        }
    }

    // MARK: - Local Commands: External Agent Vault

    private func executeVaultList() -> CLIResult {
        do {
            let formatter = ISO8601DateFormatter()
            let sessions = try vaultStore.loadSessions().map { session -> [String: Any] in
                var object: [String: Any] = [
                    "id": session.id,
                    "agentID": session.agentID.rawValue,
                    "agentDisplayName": session.agentDisplayName,
                    "sessionID": session.sessionID,
                    "capturedAt": formatter.string(from: session.capturedAt),
                    "lastSeenAt": formatter.string(from: session.lastSeenAt),
                    "source": session.source.rawValue,
                    "sanitizedArguments": session.sanitizedArguments,
                ]
                object["workingDirectory"] = session.workingDirectory ?? NSNull()
                return object
            }
            return jsonResult(["sessions": sessions])
        } catch {
            return errorResult("Failed to list vault sessions", error)
        }
    }

    private func executeVaultClear() -> CLIResult {
        do {
            try vaultStore.clear()
            return CLIResult(exitCode: 0, stdout: "Vault cleared.", stderr: "")
        } catch {
            return errorResult("Failed to clear vault", error)
        }
    }

    private func executeVaultResume(agent agentName: String, sessionID: String, dryRun: Bool) -> CLIResult {
        do {
            let registry = VaultAgentRegistry.builtIn
            guard let agent = registry.agent(matching: agentName) else {
                throw VaultError.unknownAgent(agentName)
            }
            let storedSession = try vaultStore.loadSessions().first {
                $0.agentID == agent.id && $0.sessionID == sessionID
            }
            let session = storedSession ?? VaultSession(
                id: "\(agent.id.rawValue):\(sessionID)",
                agentID: agent.id,
                agentDisplayName: agent.displayName,
                sessionID: sessionID,
                workingDirectory: nil,
                capturedAt: Date(),
                lastSeenAt: Date(),
                source: .manual,
                sanitizedArguments: []
            )
            let invocation = try VaultSessionResumer.plan(agent: agent, session: session)
            if dryRun {
                var object: [String: Any] = [
                    "dryRun": true,
                    "executable": invocation.executable,
                    "arguments": invocation.arguments,
                ]
                object["workingDirectory"] = invocation.workingDirectory ?? NSNull()
                return jsonResult(object)
            }

            let result = try VaultSessionResumer.run(invocation)
            return CLIResult(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr)
        } catch {
            return errorResult("Failed to resume vault session", error)
        }
    }

    // MARK: - Local Commands: Signatures

    private func executeKeysGenerate(author: String) -> CLIResult {
        do {
            let keyPair = try SignatureKeyPair.generate(author: author)
            try signatureKeyStore.save(keyPair)
            var registry = try TrustedAuthorRegistry.load(from: trustedAuthorRegistryURL)
            try registry.trust(displayName: author, publicKey: keyPair.publicKey)
            try registry.save()
            return jsonResult([
                "keyID": keyPair.keyID,
                "author": keyPair.author,
                "publicKey": keyPair.publicKeyBase64,
            ])
        } catch {
            return errorResult("Failed to generate signature key", error)
        }
    }

    private func executeKeysList() -> CLIResult {
        do {
            let keys = try signatureKeyStore.listKeyIDs().map { keyID -> [String: String] in
                let keyPair = try signatureKeyStore.load(keyID: keyID)
                return [
                    "keyID": keyID,
                    "author": keyPair?.author ?? "",
                    "publicKey": keyPair?.publicKeyBase64 ?? "",
                ]
            }
            return jsonResult(["keys": keys])
        } catch {
            return errorResult("Failed to list signature keys", error)
        }
    }

    private func executeKeysExportPublic(keyID: String, outputPath: String?) -> CLIResult {
        do {
            guard let keyPair = try signatureKeyStore.load(keyID: keyID) else {
                return CLIResult(exitCode: 1, stdout: "", stderr: "Error: Signature key not found: \(keyID)")
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(keyPair.publicKey)
            if let outputPath {
                try data.write(to: URL(fileURLWithPath: outputPath), options: [.atomic])
                return jsonResult(["status": "exported", "path": outputPath, "keyID": keyID])
            }
            return CLIResult(exitCode: 0, stdout: String(decoding: data, as: UTF8.self), stderr: "")
        } catch {
            return errorResult("Failed to export public signature key", error)
        }
    }

    private func executeKeysImport(path: String) -> CLIResult {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let publicKey = try JSONDecoder().decode(SignaturePublicKey.self, from: data)
            var registry = try TrustedAuthorRegistry.load(from: trustedAuthorRegistryURL)
            try registry.trust(displayName: publicKey.author, publicKey: publicKey)
            try registry.save()
            return jsonResult(["status": "imported", "keyID": publicKey.keyID, "author": publicKey.author])
        } catch {
            return errorResult("Failed to import public signature key", error)
        }
    }

    private func executeSignArtifact(kind: String, path: String, keyID: String?, author: String?) -> CLIResult {
        do {
            try validateSignatureKind(kind)
            let payloadURL = URL(fileURLWithPath: path)
            let payload = try signaturePayloadData(for: payloadURL)
            let availableKeyIDs = try signatureKeyStore.listKeyIDs()
            guard let signingKeyID = keyID ?? availableKeyIDs.first else {
                return CLIResult(
                    exitCode: 1,
                    stdout: "",
                    stderr: "Error: No signature keys are available. Run `cocxy keys generate --author <name>` first."
                )
            }
            guard let keyPair = try signatureKeyStore.load(keyID: signingKeyID) else {
                return CLIResult(exitCode: 1, stdout: "", stderr: "Error: Signature key not found: \(signingKeyID)")
            }
            let artifact = try SignatureSigner().sign(
                payload: payload,
                author: author ?? keyPair.author,
                keyPair: keyPair
            )
            let sidecarURL = signatureSidecarURL(for: payloadURL)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(artifact).write(to: sidecarURL, options: [.atomic])
            return jsonResult([
                "status": "signed",
                "kind": kind,
                "path": payloadURL.path,
                "signaturePath": sidecarURL.path,
                "keyID": artifact.keyID,
            ])
        } catch {
            return errorResult("Failed to sign artifact", error)
        }
    }

    private func executeVerifyArtifact(kind: String, path: String, publicKeyPath: String?) -> CLIResult {
        do {
            try validateSignatureKind(kind)
            let payloadURL = URL(fileURLWithPath: path)
            let payload = try signaturePayloadData(for: payloadURL)
            let sidecarURL = signatureSidecarURL(for: payloadURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let artifact = try decoder.decode(SignedArtifact.self, from: Data(contentsOf: sidecarURL))
            let publicKey: SignaturePublicKey
            if let publicKeyPath {
                publicKey = try decoder.decode(
                    SignaturePublicKey.self,
                    from: Data(contentsOf: URL(fileURLWithPath: publicKeyPath))
                )
            } else if let keyPair = try signatureKeyStore.load(keyID: artifact.keyID) {
                publicKey = keyPair.publicKey
            } else if let trusted = try TrustedAuthorRegistry.load(from: trustedAuthorRegistryURL).publicKey(for: artifact.keyID) {
                publicKey = trusted
            } else {
                return CLIResult(exitCode: 1, stdout: "", stderr: "Error: No trusted public key for \(artifact.keyID)")
            }
            let result = SignatureVerifier().verify(payload: payload, artifact: artifact, publicKey: publicKey)
            return jsonResult([
                "status": result == .valid ? "valid" : "invalid",
                "result": String(describing: result),
                "kind": kind,
                "keyID": artifact.keyID,
            ], exitCode: result == .valid ? 0 : 1)
        } catch {
            return errorResult("Failed to verify artifact", error)
        }
    }

    private func validateSignatureKind(_ kind: String) throws {
        let allowed: Set<String> = ["template", "macro", "plugin", "notebook", "file"]
        guard allowed.contains(kind) else {
            throw CLIError.invalidArgument(
                command: "signatures",
                argument: kind,
                reason: "Kind must be template, macro, plugin, notebook, or file"
            )
        }
    }

    private func signaturePayloadData(for url: URL) throws -> Data {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw CLIError.invalidArgument(command: "signatures", argument: url.path, reason: "Path does not exist")
        }
        if isDirectory.boolValue {
            let manifestURL = url.appendingPathComponent("template.json")
            if FileManager.default.fileExists(atPath: manifestURL.path) {
                return try Data(contentsOf: manifestURL)
            }
            let pluginURL = url.appendingPathComponent("cocxy-plugin.toml")
            if FileManager.default.fileExists(atPath: pluginURL.path),
               let content = try? String(contentsOf: pluginURL, encoding: .utf8) {
                return Self.canonicalPluginManifestPayload(from: content)
            }
            throw CLIError.invalidArgument(command: "signatures", argument: url.path, reason: "Directory has no supported manifest")
        }
        return try Data(contentsOf: url)
    }

    private static func canonicalPluginManifestPayload(from content: String) -> Data {
        let signatureKeys: Set<String> = [
            "signature",
            "signature-algorithm",
            "signature-key-id",
            "signature-author",
            "signature-timestamp",
            "signature-payload-sha256",
        ]
        var lines = content.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let separator = trimmed.firstIndex(of: "=") else { return true }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            return !signatureKeys.contains(key)
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private func signatureSidecarURL(for url: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return url.appendingPathComponent(".cocxy-signature.json")
        }
        return URL(fileURLWithPath: url.path + ".cocxy-signature.json")
    }

    private func jsonResult(_ object: Any, exitCode: Int32 = 0) -> CLIResult {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return CLIResult(exitCode: exitCode, stdout: String(decoding: data, as: UTF8.self), stderr: "")
        } catch {
            return errorResult("Failed to encode JSON", error)
        }
    }

    private func errorResult(_ prefix: String, _ error: Error) -> CLIResult {
        CLIResult(exitCode: 1, stdout: "", stderr: "Error: \(prefix): \(error.localizedDescription)")
    }

    // MARK: - Request Building

    /// Builds a `CLISocketRequest` from a parsed command.
    ///
    /// - Parameter command: The parsed command.
    /// - Returns: A socket request ready to send.
    public func buildRequest(from command: ParsedCommand) -> CLISocketRequest {
        let requestID = UUID().uuidString

        switch command {

        // MARK: Original commands (v1)

        case .notify(let message):
            return CLISocketRequest(
                id: requestID,
                command: "notify",
                params: ["message": message]
            )
        case .newTab(let directory, let engine):
            var params: [String: String] = [:]
            if let directory {
                params["dir"] = directory
            }
            if let engine {
                params["engine"] = engine
            }
            return CLISocketRequest(
                id: requestID,
                command: "new-tab",
                params: params.isEmpty ? nil : params
            )

        case .listTabs:
            return CLISocketRequest(id: requestID, command: "list-tabs", params: nil)

        case .focusTab(let id):
            return CLISocketRequest(id: requestID, command: "focus-tab", params: ["id": id])

        case .closeTab(let id):
            return CLISocketRequest(id: requestID, command: "close-tab", params: ["id": id])

        case .split(let direction):
            var params: [String: String]? = nil
            if let direction {
                params = ["direction": direction == .horizontal ? "horizontal" : "vertical"]
            }
            return CLISocketRequest(id: requestID, command: "split", params: params)

        case .status:
            return CLISocketRequest(id: requestID, command: "status", params: nil)

        case .hooksInstall, .hooksUninstall, .hooksStatus, .hookHandler, .setupHooks, .editorOpen,
             .classify, .correct, .identify, .capabilities, .top,
             .vaultList, .vaultClear, .vaultResume,
             .keysGenerate, .keysList, .keysExportPublic, .keysImport,
             .signArtifact, .verifyArtifact:
            // These are handled locally; should never reach socket request building.
            return CLISocketRequest(id: requestID, command: "status", params: nil)

        case .review:
            return CLISocketRequest(id: requestID, command: "review", params: nil)

        case .reviewRefresh:
            return CLISocketRequest(id: requestID, command: "review-refresh", params: nil)

        case .reviewSubmit:
            return CLISocketRequest(id: requestID, command: "review-submit", params: nil)

        case .reviewStats:
            return CLISocketRequest(id: requestID, command: "review-stats", params: nil)

        case .reviewApprove(let prNumber, let body, _):
            var params: [String: String] = [:]
            if let prNumber { params["pr"] = "\(prNumber)" }
            if let body { params["body"] = body }
            return CLISocketRequest(
                id: requestID,
                command: "review-approve",
                params: params.isEmpty ? nil : params
            )

        case .reviewRequestChanges(let prNumber, let body, _):
            var params: [String: String] = [:]
            if let prNumber { params["pr"] = "\(prNumber)" }
            if let body { params["body"] = body }
            return CLISocketRequest(
                id: requestID,
                command: "review-request-changes",
                params: params.isEmpty ? nil : params
            )

        case .help, .version:
            return CLISocketRequest(id: requestID, command: "status", params: nil)

        // MARK: Tab extended (v2)

        case .tabRename(let id, let name):
            return CLISocketRequest(
                id: requestID,
                command: "tab-rename",
                params: ["id": id, "name": name]
            )

        case .tabMove(let id, let position):
            return CLISocketRequest(
                id: requestID,
                command: "tab-move",
                params: ["id": id, "position": position]
            )

        case .tabConfigSave(let name, let command, let theme, let environment):
            var params: [String: String] = ["name": name]
            if let command { params["command"] = command }
            if let theme { params["theme"] = theme }
            for key in environment.keys.sorted() {
                params["env.\(key)"] = environment[key]
            }
            return CLISocketRequest(id: requestID, command: "tab-config-save", params: params)

        case .tabConfigOpen(let name):
            return CLISocketRequest(
                id: requestID,
                command: "tab-config-open",
                params: ["name": name]
            )

        case .tabConfigList:
            return CLISocketRequest(id: requestID, command: "tab-config-list", params: nil)

        case .tabConfigPath(let name):
            return CLISocketRequest(
                id: requestID,
                command: "tab-config-path",
                params: ["name": name]
            )

        case .tabConfigExport(let name, let output, let force):
            return CLISocketRequest(
                id: requestID,
                command: "tab-config-export",
                params: [
                    "name": name,
                    "output": output,
                    "force": force ? "true" : "false",
                ]
            )

        // MARK: Split extended (v2)

        case .splitList:
            return CLISocketRequest(id: requestID, command: "split-list", params: nil)

        case .splitFocus(let direction):
            return CLISocketRequest(
                id: requestID,
                command: "split-focus",
                params: ["direction": direction]
            )

        case .splitClose:
            return CLISocketRequest(id: requestID, command: "split-close", params: nil)

        case .splitResize(let direction, let pixels):
            return CLISocketRequest(
                id: requestID,
                command: "split-resize",
                params: ["direction": direction, "pixels": pixels]
            )

        // MARK: Dashboard (v2)

        case .dashboardShow:
            return CLISocketRequest(id: requestID, command: "dashboard-show", params: nil)

        case .dashboardHide:
            return CLISocketRequest(id: requestID, command: "dashboard-hide", params: nil)

        case .dashboardToggle:
            return CLISocketRequest(id: requestID, command: "dashboard-toggle", params: nil)

        case .dashboardStatus:
            return CLISocketRequest(id: requestID, command: "dashboard-status", params: nil)

        // MARK: Timeline (v2)

        case .timelineShow(let tabID):
            return CLISocketRequest(
                id: requestID,
                command: "timeline-show",
                params: ["tabId": tabID]
            )

        case .timelineExport(let tabID, let format):
            let normalizedFormat = format.lowercased() == "md" ? "markdown" : format.lowercased()
            return CLISocketRequest(
                id: requestID,
                command: "timeline-export",
                params: ["tabId": tabID, "format": normalizedFormat]
            )

        case .richInputShow(let tabID):
            return CLISocketRequest(
                id: requestID,
                command: "rich-input-show",
                params: ["tabId": tabID]
            )

        // MARK: Search (v2)

        case .search(let query, let regex, let caseSensitive, let tabID):
            var params: [String: String] = [
                "query": query,
                "regex": String(regex),
                "caseSensitive": String(caseSensitive)
            ]
            if let tabID {
                params["tabId"] = tabID
            }
            return CLISocketRequest(id: requestID, command: "search", params: params)

        // MARK: Config (v2)

        case .configGet(let key):
            return CLISocketRequest(
                id: requestID,
                command: "config-get",
                params: ["key": key]
            )

        case .configSet(let key, let value):
            return CLISocketRequest(
                id: requestID,
                command: "config-set",
                params: ["key": key, "value": value]
            )

        case .configPath:
            return CLISocketRequest(id: requestID, command: "config-path", params: nil)

        // MARK: Theme (v2)

        case .themeList:
            return CLISocketRequest(id: requestID, command: "theme-list", params: nil)

        case .themeSet(let name):
            return CLISocketRequest(
                id: requestID,
                command: "theme-set",
                params: ["name": name]
            )

        // MARK: System (v2)

        case .send(let text):
            return CLISocketRequest(
                id: requestID,
                command: "send",
                params: ["text": text]
            )

        case .sendKey(let key):
            return CLISocketRequest(
                id: requestID,
                command: "send-key",
                params: ["key": key]
            )

        // MARK: Window Management (v3)

        case .windowNew(let engine):
            let params = engine.map { ["engine": $0] }
            return CLISocketRequest(id: requestID, command: "window-new", params: params)

        case .windowList:
            return CLISocketRequest(id: requestID, command: "window-list", params: nil)

        case .windowFocus(let index):
            return CLISocketRequest(
                id: requestID, command: "window-focus", params: ["index": index]
            )

        case .windowClose(let index):
            var params: [String: String]?
            if let index { params = ["index": index] }
            return CLISocketRequest(id: requestID, command: "window-close", params: params)

        case .windowFullscreen:
            return CLISocketRequest(id: requestID, command: "window-fullscreen", params: nil)

        // MARK: Session Management (v3)

        case .sessionSave(let name):
            var params: [String: String]?
            if let name { params = ["name": name] }
            return CLISocketRequest(id: requestID, command: "session-save", params: params)

        case .sessionRestore(let name):
            return CLISocketRequest(
                id: requestID, command: "session-restore", params: ["name": name]
            )

        case .sessionList:
            return CLISocketRequest(id: requestID, command: "session-list", params: nil)

        case .sessionDelete(let name):
            return CLISocketRequest(
                id: requestID, command: "session-delete", params: ["name": name]
            )

        // MARK: Tab extended (v3)

        case .tabDuplicate(let id):
            var params: [String: String]?
            if let id { params = ["id": id] }
            return CLISocketRequest(id: requestID, command: "tab-duplicate", params: params)

        case .tabPin(let id):
            var params: [String: String]?
            if let id { params = ["id": id] }
            return CLISocketRequest(id: requestID, command: "tab-pin", params: params)

        // MARK: Config extended (v3)

        case .configList(let filter):
            var params: [String: String]?
            if let filter { params = ["filter": filter] }
            return CLISocketRequest(id: requestID, command: "config-list", params: params)

        case .configReload:
            return CLISocketRequest(id: requestID, command: "config-reload", params: nil)

        case .configProject:
            return CLISocketRequest(id: requestID, command: "config-project", params: nil)

        // MARK: Split extended (v3)

        case .splitSwap(let direction):
            return CLISocketRequest(
                id: requestID, command: "split-swap", params: ["direction": direction]
            )

        case .splitZoom:
            return CLISocketRequest(id: requestID, command: "split-zoom", params: nil)

        // MARK: Output (v3)

        case .capturePane(let start, let end):
            var params: [String: String] = [:]
            if let start { params["start"] = String(start) }
            if let end { params["end"] = String(end) }
            return CLISocketRequest(
                id: requestID,
                command: "capture-pane",
                params: params.isEmpty ? nil : params
            )

        // MARK: Notification CLI (v3)

        case .notificationList(let limit):
            var params: [String: String]?
            if let limit { params = ["limit": String(limit)] }
            return CLISocketRequest(id: requestID, command: "notification-list", params: params)

        case .notificationClear:
            return CLISocketRequest(id: requestID, command: "notification-clear", params: nil)

        // MARK: Remote Workspace (exposed v3)

        case .remoteList:
            return CLISocketRequest(id: requestID, command: "remote-list", params: nil)

        case .remoteConnect(let name):
            return CLISocketRequest(
                id: requestID, command: "remote-connect", params: ["name": name]
            )

        case .remoteDisconnect(let name):
            return CLISocketRequest(
                id: requestID, command: "remote-disconnect", params: ["name": name]
            )

        case .remoteStatus(let name):
            var params: [String: String]?
            if let name { params = ["name": name] }
            return CLISocketRequest(id: requestID, command: "remote-status", params: params)

        case .remoteTunnels(let profile):
            var params: [String: String]?
            if let profile { params = ["profile": profile] }
            return CLISocketRequest(id: requestID, command: "remote-tunnels", params: params)

        // MARK: Plugin Management (exposed v3)

        case .pluginList:
            return CLISocketRequest(id: requestID, command: "plugin-list", params: nil)

        case .pluginEnable(let id):
            return CLISocketRequest(
                id: requestID, command: "plugin-enable", params: ["id": id]
            )

        case .pluginDisable(let id):
            return CLISocketRequest(
                id: requestID, command: "plugin-disable", params: ["id": id]
            )

        case .pluginSourceList:
            return CLISocketRequest(id: requestID, command: "plugin-source-list", params: nil)

        case .pluginSourceAdd(let url, let displayName):
            var params = ["url": url]
            if let displayName {
                params["name"] = displayName
            }
            return CLISocketRequest(id: requestID, command: "plugin-source-add", params: params)

        case .pluginInstall(let url, let replaceExisting):
            return CLISocketRequest(
                id: requestID,
                command: "plugin-install",
                params: ["url": url, "replace": replaceExisting ? "true" : "false"]
            )

        case .pluginUninstall(let id):
            return CLISocketRequest(
                id: requestID, command: "plugin-uninstall", params: ["id": id]
            )

        // MARK: Sandbox Grants (v6)

        case .sandboxListGrants(let pluginID):
            return CLISocketRequest(
                id: requestID,
                command: "sandbox-list-grants",
                params: ["plugin": pluginID]
            )

        case .sandboxRevoke(let pluginID, let capability):
            return CLISocketRequest(
                id: requestID,
                command: "sandbox-revoke",
                params: ["plugin": pluginID, "capability": capability]
            )

        // MARK: Browser (exposed v3)

        case .browserNavigate(let url):
            return CLISocketRequest(
                id: requestID, command: "browser-navigate", params: ["url": url]
            )

        case .browserBack:
            return CLISocketRequest(id: requestID, command: "browser-back", params: nil)

        case .browserForward:
            return CLISocketRequest(id: requestID, command: "browser-forward", params: nil)

        case .browserReload:
            return CLISocketRequest(id: requestID, command: "browser-reload", params: nil)

        case .browserGetState:
            return CLISocketRequest(id: requestID, command: "browser-get-state", params: nil)

        case .browserEval(let script):
            return CLISocketRequest(
                id: requestID, command: "browser-eval", params: ["script": script]
            )

        case .browserGetText:
            return CLISocketRequest(id: requestID, command: "browser-get-text", params: nil)

        case .browserListTabs:
            return CLISocketRequest(id: requestID, command: "browser-list-tabs", params: nil)

        case .browserSnapshot:
            return CLISocketRequest(id: requestID, command: "browser-snapshot", params: nil)

        case .browserClick(let ref):
            return CLISocketRequest(id: requestID, command: "browser-click", params: ["ref": ref])

        case .browserFill(let ref, let text):
            return CLISocketRequest(
                id: requestID,
                command: "browser-fill",
                params: ["ref": ref, "text": text]
            )

        case .browserScreenshot(let outputPath):
            var params: [String: String] = [:]
            if let outputPath {
                params["output"] = outputPath
            }
            return CLISocketRequest(
                id: requestID,
                command: "browser-screenshot",
                params: params.isEmpty ? nil : params
            )

        case .browserConsole:
            return CLISocketRequest(id: requestID, command: "browser-console", params: nil)

        case .browserWait(let selector, let timeoutMilliseconds):
            var params: [String: String] = ["selector": selector]
            if let timeoutMilliseconds {
                params["timeout"] = "\(timeoutMilliseconds)"
            }
            return CLISocketRequest(id: requestID, command: "browser-wait", params: params)

        case .browserCookiesList(let domain):
            var params: [String: String] = [:]
            if let domain {
                params["domain"] = domain
            }
            return CLISocketRequest(
                id: requestID,
                command: "browser-cookies-list",
                params: params.isEmpty ? nil : params
            )

        case .browserCookiesSet(let options):
            return CLISocketRequest(
                id: requestID,
                command: "browser-cookies-set",
                params: options.socketParams
            )

        case .browserCookiesDelete(let name, let path, let domain):
            var params: [String: String] = ["name": name]
            if let path { params["path"] = path }
            if let domain { params["domain"] = domain }
            return CLISocketRequest(id: requestID, command: "browser-cookies-delete", params: params)

        case .browserNetwork(let filter, let tail):
            var params: [String: String] = [:]
            if let filter { params["filter"] = filter }
            if let tail { params["tail"] = "\(tail)" }
            return CLISocketRequest(
                id: requestID,
                command: "browser-network",
                params: params.isEmpty ? nil : params
            )

        case .browserImportPreview(let options):
            return CLISocketRequest(
                id: requestID,
                command: "browser-import-preview",
                params: options.socketParams
            )

        case .browserImportRun(let options):
            return CLISocketRequest(
                id: requestID,
                command: "browser-import-run",
                params: options.socketParams
            )

        // MARK: SSH (v4)

        case .ssh(let destination, let port, let identityFile):
            var params: [String: String] = ["destination": destination]
            if let port { params["port"] = "\(port)" }
            if let identityFile { params["identity"] = identityFile }
            return CLISocketRequest(id: requestID, command: "ssh", params: params)

        // MARK: Web Terminal (v5)

        case .webStart(let bindAddress, let port, let token, let fps):
            var params: [String: String] = [:]
            if let bindAddress { params["bind"] = bindAddress }
            if let port { params["port"] = "\(port)" }
            if let token { params["token"] = token }
            if let fps { params["fps"] = "\(fps)" }
            return CLISocketRequest(id: requestID, command: "web-start", params: params.isEmpty ? nil : params)

        case .webStop:
            return CLISocketRequest(id: requestID, command: "web-stop", params: nil)

        case .webStatus:
            return CLISocketRequest(id: requestID, command: "web-status", params: nil)

        case .streamList:
            return CLISocketRequest(id: requestID, command: "stream-list", params: nil)

        case .streamCurrent(let id):
            return CLISocketRequest(id: requestID, command: "stream-current", params: ["id": "\(id)"])

        case .protocolCapabilities:
            return CLISocketRequest(id: requestID, command: "protocol-capabilities", params: nil)

        case .protocolViewport(let requestIDValue):
            let params = requestIDValue.map { ["request_id": $0] }
            return CLISocketRequest(id: requestID, command: "protocol-viewport", params: params)

        case .protocolSend(let type, let json):
            return CLISocketRequest(
                id: requestID,
                command: "protocol-send",
                params: ["type": type, "json": json]
            )

        case .coreReset:
            return CLISocketRequest(id: requestID, command: "core-reset", params: nil)

        case .coreSignal(let signal):
            return CLISocketRequest(
                id: requestID,
                command: "core-signal",
                params: ["signal": signal]
            )

        case .coreProcess:
            return CLISocketRequest(id: requestID, command: "core-process", params: nil)

        case .coreModes:
            return CLISocketRequest(id: requestID, command: "core-modes", params: nil)

        case .coreSearch:
            return CLISocketRequest(id: requestID, command: "core-search", params: nil)

        case .coreLigatures:
            return CLISocketRequest(id: requestID, command: "core-ligatures", params: nil)

        case .coreProtocol:
            return CLISocketRequest(id: requestID, command: "core-protocol", params: nil)

        case .coreSelection:
            return CLISocketRequest(id: requestID, command: "core-selection", params: nil)

        case .coreFontMetrics:
            return CLISocketRequest(id: requestID, command: "core-font-metrics", params: nil)

        case .corePreedit:
            return CLISocketRequest(id: requestID, command: "core-preedit", params: nil)

        case .coreSemantic(let limit):
            let params = limit.map { ["limit": "\($0)"] }
            return CLISocketRequest(id: requestID, command: "core-semantic", params: params)

        case .blockList(let limit):
            let params = limit.map { ["limit": "\($0)"] }
            return CLISocketRequest(id: requestID, command: "block-list", params: params)

        case .blockOutputs(let limit):
            let params = limit.map { ["limit": "\($0)"] }
            return CLISocketRequest(id: requestID, command: "block-outputs", params: params)

        case .blockCopy(let id, let field):
            return CLISocketRequest(
                id: requestID,
                command: "block-copy",
                params: ["id": "\(id)", "field": field]
            )

        case .blockRerun(let id):
            return CLISocketRequest(
                id: requestID,
                command: "block-rerun",
                params: ["id": "\(id)"]
            )

        case .imageList:
            return CLISocketRequest(id: requestID, command: "image-list", params: nil)

        case .imageDelete(let id):
            return CLISocketRequest(id: requestID, command: "image-delete", params: ["id": "\(id)"])

        case .imageClear:
            return CLISocketRequest(id: requestID, command: "image-clear", params: nil)

        case .notebookImport(let inputPath, let outputPath, let force):
            return CLISocketRequest(
                id: requestID,
                command: "notebook-import",
                params: [
                    "input": inputPath,
                    "output": outputPath,
                    "force": force ? "true" : "false"
                ]
            )

        case .notebookExport(let inputPath, let outputPath, let force):
            return CLISocketRequest(
                id: requestID,
                command: "notebook-export",
                params: [
                    "input": inputPath,
                    "output": outputPath,
                    "force": force ? "true" : "false"
                ]
            )

        case .notebookExportHTML(let inputPath, let outputPath, let force):
            return CLISocketRequest(
                id: requestID,
                command: "notebook-export-html",
                params: [
                    "input": inputPath,
                    "output": outputPath,
                    "force": force ? "true" : "false"
                ]
            )

        case .notebookTemplateList:
            return CLISocketRequest(id: requestID, command: "notebook-template-list", params: nil)

        case .notebookTemplateCreate(let templateID, let outputPath, let force):
            return CLISocketRequest(
                id: requestID,
                command: "notebook-template-create",
                params: [
                    "template": templateID,
                    "output": outputPath,
                    "force": force ? "true" : "false"
                ]
            )

        case .notebookRun(
            let inputPath,
            let outputPath,
            let workingDirectory,
            let timeoutSeconds,
            let sandbox,
            let continueOnFailure
        ):
            var params = [
                "input": inputPath,
                "sandbox": sandbox,
                "continue-on-failure": continueOnFailure ? "true" : "false"
            ]
            if let outputPath { params["output"] = outputPath }
            if let workingDirectory { params["cwd"] = workingDirectory }
            if let timeoutSeconds { params["timeout"] = "\(timeoutSeconds)" }
            return CLISocketRequest(id: requestID, command: "notebook-run", params: params)

        case .workflowRun(let inputPath, let workingDirectory):
            var params = ["input": inputPath]
            if let workingDirectory { params["cwd"] = workingDirectory }
            return CLISocketRequest(id: requestID, command: "workflow-run", params: params)

        case .skillList:
            return CLISocketRequest(id: requestID, command: "skill-list", params: nil)

        case .skillSourceList:
            return CLISocketRequest(id: requestID, command: "skill-source-list", params: nil)

        case .skillSourceAdd(let url, let displayName):
            var params = ["url": url]
            if let displayName { params["name"] = displayName }
            return CLISocketRequest(id: requestID, command: "skill-source-add", params: params)

        case .skillInstall(let url, let replaceExisting):
            return CLISocketRequest(
                id: requestID,
                command: "skill-install",
                params: ["url": url, "replace": replaceExisting ? "true" : "false"]
            )

        case .skillUninstall(let id):
            return CLISocketRequest(id: requestID, command: "skill-uninstall", params: ["id": id])

        case .worktreeAdd(let agent, let branch, let baseRef):
            var params: [String: String] = [:]
            if let agent { params["agent"] = agent }
            if let branch { params["branch"] = branch }
            if let baseRef { params["base-ref"] = baseRef }
            return CLISocketRequest(
                id: requestID,
                command: "worktree-add",
                params: params.isEmpty ? nil : params
            )

        case .worktreeList:
            return CLISocketRequest(id: requestID, command: "worktree-list", params: nil)

        case .worktreeRemove(let id, let force):
            return CLISocketRequest(
                id: requestID,
                command: "worktree-remove",
                params: ["id": id, "force": force ? "true" : "false"]
            )

        case .worktreeFocus(let id):
            return CLISocketRequest(
                id: requestID,
                command: "worktree-focus",
                params: ["id": id]
            )

        case .worktreePrune:
            return CLISocketRequest(id: requestID, command: "worktree-prune", params: nil)

        case .worktreeCleanupMerged(let baseRef, let force, let dryRun):
            var params = [
                "force": force ? "true" : "false",
                "dry-run": dryRun ? "true" : "false"
            ]
            if let baseRef { params["base-ref"] = baseRef }
            return CLISocketRequest(
                id: requestID,
                command: "worktree-cleanup-merged",
                params: params
            )

        case .githubStatus:
            return CLISocketRequest(id: requestID, command: "github-status", params: nil)

        case .githubPRs(let state, let limit):
            var params: [String: String] = [:]
            if let state { params["state"] = state }
            if let limit { params["limit"] = "\(limit)" }
            return CLISocketRequest(
                id: requestID,
                command: "github-prs",
                params: params.isEmpty ? nil : params
            )

        case .githubIssues(let state, let limit):
            var params: [String: String] = [:]
            if let state { params["state"] = state }
            if let limit { params["limit"] = "\(limit)" }
            return CLISocketRequest(
                id: requestID,
                command: "github-issues",
                params: params.isEmpty ? nil : params
            )

        case .githubOpen:
            return CLISocketRequest(id: requestID, command: "github-open", params: nil)

        case .githubRefresh:
            return CLISocketRequest(id: requestID, command: "github-refresh", params: nil)

        case .githubPRMerge(let method, let prNumber, let deleteBranch, let subject, let body):
            var params: [String: String] = ["method": method.rawValue]
            if let prNumber { params["pr"] = "\(prNumber)" }
            // Emit the explicit string so behaviour is unambiguous on
            // both ends regardless of future server defaults.
            params["delete-branch"] = deleteBranch ? "true" : "false"
            if let subject, !subject.isEmpty { params["subject"] = subject }
            if let body, !body.isEmpty { params["body"] = body }
            return CLISocketRequest(
                id: requestID,
                command: "github-pr-merge",
                params: params
            )

        case .gitAssistantCommitMessage:
            return CLISocketRequest(
                id: requestID,
                command: "git-assistant-commit-message",
                params: nil
            )

        case .gitAssistantPRDraft(let baseBranch, let headBranch):
            var params: [String: String] = [:]
            if let baseBranch { params["base"] = baseBranch }
            if let headBranch { params["head"] = headBranch }
            return CLISocketRequest(
                id: requestID,
                command: "git-assistant-pr-draft",
                params: params.isEmpty ? nil : params
            )

        case .gitAssistantReleaseNotes(let baseBranch, let headBranch):
            var params: [String: String] = [:]
            if let baseBranch { params["base"] = baseBranch }
            if let headBranch { params["head"] = headBranch }
            return CLISocketRequest(
                id: requestID,
                command: "git-assistant-release-notes",
                params: params.isEmpty ? nil : params
            )
        }
    }

    func socketClient(for command: ParsedCommand) -> SocketClient {
        let timeoutSeconds = max(
            socketClient.timeoutSeconds,
            Self.socketTimeoutSeconds(for: command)
        )
        guard timeoutSeconds != socketClient.timeoutSeconds else {
            return socketClient
        }
        return SocketClient(
            socketPath: socketClient.socketPath,
            timeoutSeconds: timeoutSeconds
        )
    }

    static func socketTimeoutSeconds(for command: ParsedCommand) -> TimeInterval {
        switch command {
        case .githubStatus,
             .githubPRs,
             .githubIssues,
             .reviewApprove,
             .reviewRequestChanges:
            return extendedGitHubReadSocketTimeoutSeconds
        case .githubPRMerge:
            return extendedGitHubMutationSocketTimeoutSeconds
        case .gitAssistantCommitMessage,
             .gitAssistantPRDraft,
             .gitAssistantReleaseNotes:
            return extendedGitAssistantSocketTimeoutSeconds
        default:
            return SocketClient.defaultTimeoutSeconds
        }
    }
}

private extension ParsedCommand {
    func fillingReviewBodyFromStdinIfNeeded() -> ParsedCommand? {
        switch self {
        case .reviewApprove(let prNumber, let body, true):
            return .reviewApprove(
                prNumber: prNumber,
                body: body ?? Self.readStdinBody(),
                readBodyFromStdin: false
            )
        case .reviewRequestChanges(let prNumber, let body, true):
            return .reviewRequestChanges(
                prNumber: prNumber,
                body: body ?? Self.readStdinBody(),
                readBodyFromStdin: false
            )
        default:
            return nil
        }
    }

    static func readStdinBody() -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private final class CLIValueBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value?

    func store(_ value: Value) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }

    func load() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }
}

// MARK: - CLI Result

/// The result of a CLI command execution.
///
/// Contains the exit code and output for stdout and stderr.
public struct CLIResult: Equatable {
    /// Process exit code. 0 for success, 1 for error.
    public let exitCode: Int32

    /// Output for stdout.
    public let stdout: String

    /// Output for stderr.
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}
