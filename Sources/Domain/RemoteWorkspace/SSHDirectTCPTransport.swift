// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHDirectTCPTransport.swift - Attested OpenSSH ControlMaster MUX transport.

import Darwin
import Foundation

/// Streams bytes through one OpenSSH ControlMaster `direct-tcpip` channel.
///
/// Cocxy speaks the documented MUX v4 protocol directly so `LOCAL_PEERPID` is
/// verified on the exact Unix descriptor that receives `MUX_C_NEW_STDIO_FWD`.
/// The destination and stream descriptors are never sent to an unattested peer.
final class SSHDirectTCPTransport: ProxyUpstreamTransport, @unchecked Sendable {
    struct ConnectionHooks: Sendable {
        var beforeConnect: (@Sendable () throws -> Void)?
        var afterSocketConfigured: (@Sendable (Int32) throws -> Void)?
        var afterConnect: (@Sendable () throws -> Void)?

        static let none = ConnectionHooks()
    }

    fileprivate struct SocketIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    private struct PacketReader {
        let data: Data
        private(set) var offset = 0

        var isAtEnd: Bool { offset == data.count }

        mutating func readUInt32() throws -> UInt32 {
            guard data.count - offset >= 4 else {
                throw ProxyUpstreamTransportError.protocolViolation
            }
            let value = data[offset..<(offset + 4)].reduce(UInt32(0)) {
                ($0 << 8) | UInt32($1)
            }
            offset += 4
            return value
        }

        mutating func readString() throws -> Data {
            let length = Int(try readUInt32())
            guard length <= data.count - offset else {
                throw ProxyUpstreamTransportError.protocolViolation
            }
            let value = Data(data[offset..<(offset + length)])
            offset += length
            return value
        }
    }

    private static let muxMessageHello: UInt32 = 0x0000_0001
    private static let muxClientAliveCheck: UInt32 = 0x1000_0004
    private static let muxClientNewStdioForward: UInt32 = 0x1000_0008
    private static let muxServerPermissionDenied: UInt32 = 0x8000_0002
    private static let muxServerFailure: UInt32 = 0x8000_0003
    private static let muxServerAlive: UInt32 = 0x8000_0005
    private static let muxServerSessionOpened: UInt32 = 0x8000_0006
    private static let muxVersion: UInt32 = 4
    private static let maximumPacketBytes = 256 * 1_024
    private static let maximumDiagnosticBytes = 4_096
    private static let defaultHandshakeTimeout: TimeInterval = 8

    private let controlPath: String
    private let target: ProxyTarget
    private let expectedAttestation: SSHControlSocketAttestation
    private let connectionHooks: ConnectionHooks
    private let handshakeTimeout: TimeInterval
    private let writeQueue = DispatchQueue(label: "com.cocxy.proxy-transport.write")
    private let handshakeQueue = DispatchQueue(
        label: "com.cocxy.proxy-transport.mux",
        qos: .utility
    )
    private let stateLock = NSLock()
    private let inputHandle: FileHandle
    private let outputHandle: FileHandle

    private var controlDescriptor: Int32 = -1
    private var connectingDescriptor: Int32 = -1
    private var passedInputDescriptor: Int32
    private var passedOutputDescriptor: Int32
    private var writeDescriptor: Int32
    private var readDescriptor: Int32
    private var controlReadSource: DispatchSourceRead?
    private var cancelled = false
    private var writeClosed = false
    private var controlReachedEOF = false
    private var receivePending = false
    private var receiveMaximumLength = 0
    private var receiveCompletion: (@Sendable (Result<Data?, any Error>) -> Void)?
    private var bufferedOutput = Data()
    private var outputReachedEOF = false
    private var diagnosticData = Data()
    private var readinessConfirmed = false
    private var readinessFailure: (any Error)?
    private var readinessContinuation: CheckedContinuation<Void, any Error>?
    private var readinessTimeoutWorkItem: DispatchWorkItem?

    var processIdentifier: Int32 { expectedAttestation.peerProcessID }

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return !cancelled
            && !controlReachedEOF
            && !outputReachedEOF
            && readinessFailure == nil
    }

    var diagnosticOutput: String {
        stateLock.lock()
        let data = diagnosticData
        stateLock.unlock()
        return String(decoding: data, as: UTF8.self)
    }

    init(
        controlPath: String,
        target: ProxyTarget,
        expectedAttestation: SSHControlSocketAttestation,
        connectionHooks: ConnectionHooks = .none,
        handshakeTimeout: TimeInterval = SSHDirectTCPTransport.defaultHandshakeTimeout
    ) throws {
        var inputDescriptors = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&inputDescriptors) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var outputDescriptors = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&outputDescriptors) == 0 else {
            Darwin.close(inputDescriptors[0])
            Darwin.close(inputDescriptors[1])
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        do {
            for descriptor in inputDescriptors + outputDescriptors {
                try Self.configureCloseOnExec(descriptor)
            }
            try Self.configurePipeWriter(inputDescriptors[1])
            try Self.configurePipeWriter(outputDescriptors[1])
        } catch {
            for descriptor in inputDescriptors + outputDescriptors {
                Darwin.close(descriptor)
            }
            throw error
        }

        self.controlPath = controlPath
        self.target = target
        self.expectedAttestation = expectedAttestation
        self.connectionHooks = connectionHooks
        self.handshakeTimeout = max(0.1, handshakeTimeout)
        passedInputDescriptor = inputDescriptors[0]
        writeDescriptor = inputDescriptors[1]
        readDescriptor = outputDescriptors[0]
        passedOutputDescriptor = outputDescriptors[1]
        inputHandle = FileHandle(
            fileDescriptor: inputDescriptors[1],
            closeOnDealloc: false
        )
        outputHandle = FileHandle(
            fileDescriptor: outputDescriptors[0],
            closeOnDealloc: false
        )

        handshakeQueue.async { [weak self] in
            self?.performHandshake()
        }
    }

    deinit {
        cancel()
    }

    func waitUntilReady() async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                registerReadinessContinuation(continuation)
            }
        } onCancel: { [weak self] in
            self?.failHandshake(CancellationError())
        }
    }

    func send(
        _ data: Data,
        completion: @escaping @Sendable (Result<Void, any Error>) -> Void
    ) {
        guard !data.isEmpty else {
            completion(.success(()))
            return
        }

        writeQueue.async { [weak self] in
            guard let self else {
                completion(.failure(ProxyUpstreamTransportError.closed))
                return
            }
            self.stateLock.lock()
            let mayWrite = !self.cancelled
                && !self.writeClosed
                && self.readinessConfirmed
            self.stateLock.unlock()
            guard mayWrite else {
                completion(.failure(ProxyUpstreamTransportError.closed))
                return
            }

            do {
                try self.inputHandle.write(contentsOf: data)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func receive(
        maximumLength: Int,
        completion: @escaping @Sendable (Result<Data?, any Error>) -> Void
    ) {
        let boundedLength = max(1, min(maximumLength, 65_536))
        stateLock.lock()
        guard !cancelled, readinessConfirmed else {
            stateLock.unlock()
            completion(.failure(ProxyUpstreamTransportError.closed))
            return
        }
        guard !receivePending else {
            stateLock.unlock()
            completion(.failure(ProxyUpstreamTransportError.receiveAlreadyPending))
            return
        }
        if !bufferedOutput.isEmpty {
            let delivered = Data(bufferedOutput.prefix(boundedLength))
            bufferedOutput = Data(bufferedOutput.dropFirst(delivered.count))
            stateLock.unlock()
            completion(.success(delivered))
            return
        }
        if outputReachedEOF {
            stateLock.unlock()
            completion(.success(nil))
            return
        }
        receivePending = true
        receiveMaximumLength = boundedLength
        receiveCompletion = completion
        outputHandle.readabilityHandler = { [weak self] handle in
            self?.deliverAvailableOutput(from: handle)
        }
        stateLock.unlock()
    }

    func closeWrite() {
        writeQueue.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            guard !self.cancelled, !self.writeClosed else {
                self.stateLock.unlock()
                return
            }
            self.writeClosed = true
            let descriptor = self.writeDescriptor
            self.writeDescriptor = -1
            self.stateLock.unlock()

            if descriptor >= 0 {
                try? self.inputHandle.close()
            }
        }
    }

    func cancel() {
        _ = resolveReadiness(.failure(ProxyUpstreamTransportError.closed))
        terminateResources()
    }

    private func performHandshake() {
        let timeoutNanoseconds = UInt64(handshakeTimeout * 1_000_000_000)
        let deadline = DispatchTime.now().uptimeNanoseconds &+ timeoutNanoseconds
        var unownedControlDescriptor: Int32 = -1
        var handshakeControlDescriptor: Int32 = -1
        var inputDescriptor: Int32 = -1
        var outputDescriptor: Int32 = -1

        do {
            try checkCancellation()
            guard try Self.protectedSocketIdentity(at: controlPath)
                    == expectedAttestation.socketIdentity else {
                throw ProxyUpstreamTransportError.controlSocketRejected
            }

            try connectionHooks.beforeConnect?()
            unownedControlDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard unownedControlDescriptor >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try Self.configureSocket(unownedControlDescriptor)
            try publishConnectingDescriptor(unownedControlDescriptor)
            try connectionHooks.afterSocketConfigured?(unownedControlDescriptor)
            try checkCancellation()
            try Self.connect(
                descriptor: unownedControlDescriptor,
                path: controlPath,
                deadline: deadline
            )
            try checkCancellation()
            try connectionHooks.afterConnect?()

            guard try Self.peerProcessID(for: unownedControlDescriptor)
                    == expectedAttestation.peerProcessID,
                  try Self.protectedSocketIdentity(at: controlPath)
                    == expectedAttestation.socketIdentity else {
                throw ProxyUpstreamTransportError.controlSocketRejected
            }

            try adoptControlDescriptor(unownedControlDescriptor)
            let controlDescriptor = unownedControlDescriptor
            handshakeControlDescriptor = controlDescriptor
            unownedControlDescriptor = -1

            try Self.writePacket(
                Self.packetBody(
                    uint32Values: [Self.muxMessageHello, Self.muxVersion]
                ),
                to: controlDescriptor,
                deadline: deadline
            )
            try Self.validateHello(
                Self.readPacket(from: controlDescriptor, deadline: deadline)
            )

            let aliveRequestID: UInt32 = 0
            try Self.writePacket(
                Self.packetBody(
                    uint32Values: [Self.muxClientAliveCheck, aliveRequestID]
                ),
                to: controlDescriptor,
                deadline: deadline
            )
            try Self.validateAliveReply(
                Self.readPacket(from: controlDescriptor, deadline: deadline),
                requestID: aliveRequestID,
                expectedProcessID: expectedAttestation.peerProcessID
            )

            let forwardRequestID: UInt32 = 1
            var forwardRequest = Data()
            Self.appendUInt32(Self.muxClientNewStdioForward, to: &forwardRequest)
            Self.appendUInt32(forwardRequestID, to: &forwardRequest)
            Self.appendString(Data(), to: &forwardRequest)
            Self.appendString(Data(target.host.utf8), to: &forwardRequest)
            Self.appendUInt32(UInt32(target.port), to: &forwardRequest)
            try Self.writePacket(
                forwardRequest,
                to: controlDescriptor,
                deadline: deadline
            )

            (inputDescriptor, outputDescriptor) = try takePassedStreamDescriptors()
            try Self.sendFileDescriptor(
                inputDescriptor,
                to: controlDescriptor,
                deadline: deadline
            )
            Darwin.close(inputDescriptor)
            inputDescriptor = -1
            try Self.sendFileDescriptor(
                outputDescriptor,
                to: controlDescriptor,
                deadline: deadline
            )
            Darwin.close(outputDescriptor)
            outputDescriptor = -1

            try Self.validateForwardReply(
                Self.readPacket(from: controlDescriptor, deadline: deadline),
                requestID: forwardRequestID
            )

            guard try completeHandshakeAndStartControlMonitor(
                descriptor: controlDescriptor
            ) else {
                throw ProxyUpstreamTransportError.closed
            }
            handshakeControlDescriptor = -1
        } catch {
            if inputDescriptor >= 0 { Darwin.close(inputDescriptor) }
            if outputDescriptor >= 0 { Darwin.close(outputDescriptor) }
            if unownedControlDescriptor >= 0 {
                releaseConnectingDescriptor(unownedControlDescriptor)
            }
            if handshakeControlDescriptor >= 0 {
                releaseHandshakeControlDescriptor(handshakeControlDescriptor)
            }
            failHandshake(error)
        }
    }

    private func deliverAvailableOutput(from handle: FileHandle) {
        handle.readabilityHandler = nil
        let available = handle.availableData

        stateLock.lock()
        guard !cancelled,
              receivePending,
              let completion = receiveCompletion else {
            stateLock.unlock()
            return
        }
        receiveCompletion = nil
        receivePending = false
        let maximumLength = receiveMaximumLength
        receiveMaximumLength = 0
        let result: Data?
        if available.isEmpty {
            outputReachedEOF = true
            result = nil
        } else {
            result = Data(available.prefix(maximumLength))
            if available.count > maximumLength {
                bufferedOutput.append(available.dropFirst(maximumLength))
            }
        }
        stateLock.unlock()
        completion(.success(result))
    }

    private func adoptControlDescriptor(_ descriptor: Int32) throws {
        stateLock.lock()
        guard !cancelled, connectingDescriptor == descriptor else {
            stateLock.unlock()
            throw ProxyUpstreamTransportError.closed
        }
        connectingDescriptor = -1
        controlDescriptor = descriptor
        stateLock.unlock()
    }

    private func publishConnectingDescriptor(_ descriptor: Int32) throws {
        stateLock.lock()
        guard !cancelled, connectingDescriptor < 0 else {
            stateLock.unlock()
            throw ProxyUpstreamTransportError.closed
        }
        connectingDescriptor = descriptor
        stateLock.unlock()
    }

    private func releaseConnectingDescriptor(_ descriptor: Int32) {
        stateLock.lock()
        if connectingDescriptor == descriptor {
            connectingDescriptor = -1
        }
        stateLock.unlock()

        _ = Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
    }

    private func releaseHandshakeControlDescriptor(_ descriptor: Int32) {
        stateLock.lock()
        if controlDescriptor == descriptor {
            controlDescriptor = -1
        }
        stateLock.unlock()

        _ = Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
    }

    private func takePassedStreamDescriptors() throws -> (Int32, Int32) {
        stateLock.lock()
        guard !cancelled,
              passedInputDescriptor >= 0,
              passedOutputDescriptor >= 0 else {
            stateLock.unlock()
            throw ProxyUpstreamTransportError.closed
        }
        let descriptors = (passedInputDescriptor, passedOutputDescriptor)
        passedInputDescriptor = -1
        passedOutputDescriptor = -1
        stateLock.unlock()
        return descriptors
    }

    private func completeHandshakeAndStartControlMonitor(
        descriptor: Int32
    ) throws -> Bool {
        stateLock.lock()
        guard !cancelled,
              controlDescriptor == descriptor,
              !readinessConfirmed,
              readinessFailure == nil else {
            stateLock.unlock()
            return false
        }

        let currentFlags = Darwin.fcntl(descriptor, F_GETFL)
        guard currentFlags >= 0,
              Darwin.fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK) == 0 else {
            let failure = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            stateLock.unlock()
            throw failure
        }
        let source = DispatchSource.makeReadSource(
            fileDescriptor: descriptor,
            queue: handshakeQueue
        )
        source.setEventHandler { [weak self] in
            self?.handleControlEvent(descriptor: descriptor)
        }
        controlReadSource = source
        readinessConfirmed = true
        let continuation = readinessContinuation
        readinessContinuation = nil
        let timeoutWorkItem = readinessTimeoutWorkItem
        readinessTimeoutWorkItem = nil
        source.activate()
        stateLock.unlock()

        timeoutWorkItem?.cancel()
        continuation?.resume(returning: ())
        return true
    }

    private func handleControlEvent(descriptor: Int32) {
        var byte: UInt8 = 0
        stateLock.lock()
        guard !cancelled, controlDescriptor == descriptor else {
            stateLock.unlock()
            return
        }
        let count = Darwin.recv(descriptor, &byte, 1, 0)
        stateLock.unlock()
        if count > 0 {
            setDiagnostic(ProxyUpstreamTransportError.protocolViolation)
            terminateResources()
        } else if count == 0 {
            markControlEOF(descriptor: descriptor)
        } else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
            markControlEOF(descriptor: descriptor)
        }
    }

    private func markControlEOF(descriptor: Int32) {
        stateLock.lock()
        guard controlDescriptor == descriptor else {
            stateLock.unlock()
            return
        }
        let source = controlReadSource
        controlReadSource = nil
        controlDescriptor = -1
        controlReachedEOF = true
        stateLock.unlock()

        source?.cancel()
        Darwin.close(descriptor)
    }

    private func registerReadinessContinuation(
        _ continuation: CheckedContinuation<Void, any Error>
    ) {
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.failHandshake(ProxyUpstreamTransportError.readinessTimedOut)
        }
        let immediateResult: Result<Void, any Error>?

        stateLock.lock()
        if cancelled {
            immediateResult = .failure(ProxyUpstreamTransportError.closed)
        } else if readinessConfirmed {
            immediateResult = .success(())
        } else if let readinessFailure {
            immediateResult = .failure(readinessFailure)
        } else if readinessContinuation != nil {
            immediateResult = .failure(
                ProxyUpstreamTransportError.readinessAlreadyPending
            )
        } else {
            readinessContinuation = continuation
            readinessTimeoutWorkItem = timeoutWorkItem
            immediateResult = nil
        }
        stateLock.unlock()

        if let immediateResult {
            continuation.resume(with: immediateResult)
        } else {
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + handshakeTimeout,
                execute: timeoutWorkItem
            )
        }
    }

    @discardableResult
    private func resolveReadiness(_ result: Result<Void, any Error>) -> Bool {
        stateLock.lock()
        guard !readinessConfirmed, readinessFailure == nil else {
            stateLock.unlock()
            return false
        }
        switch result {
        case .success:
            readinessConfirmed = true
        case .failure(let error):
            readinessFailure = error
        }
        let continuation = readinessContinuation
        readinessContinuation = nil
        let timeoutWorkItem = readinessTimeoutWorkItem
        readinessTimeoutWorkItem = nil
        stateLock.unlock()

        timeoutWorkItem?.cancel()
        continuation?.resume(with: result)
        return true
    }

    private func failHandshake(_ error: any Error) {
        guard resolveReadiness(.failure(error)) else { return }
        setDiagnostic(error)
        terminateResources()
    }

    private func setDiagnostic(_ error: any Error) {
        let description = (error as? LocalizedError)?.errorDescription
            ?? "Secure proxy transport failed"
        stateLock.lock()
        diagnosticData = Data(description.utf8.prefix(Self.maximumDiagnosticBytes))
        stateLock.unlock()
    }

    private func terminateResources() {
        stateLock.lock()
        guard !cancelled else {
            stateLock.unlock()
            return
        }
        cancelled = true
        writeClosed = true
        let pendingReceive = receiveCompletion
        receiveCompletion = nil
        receivePending = false
        let source = controlReadSource
        controlReadSource = nil
        let connecting = connectingDescriptor
        let control = controlDescriptor
        let handshakeOwnsControl = control >= 0
            && !readinessConfirmed
            && source == nil
        if !handshakeOwnsControl {
            controlDescriptor = -1
        }
        let passedInput = passedInputDescriptor
        passedInputDescriptor = -1
        let passedOutput = passedOutputDescriptor
        passedOutputDescriptor = -1
        let write = writeDescriptor
        writeDescriptor = -1
        let read = readDescriptor
        readDescriptor = -1
        stateLock.unlock()

        outputHandle.readabilityHandler = nil
        source?.cancel()
        if connecting >= 0 {
            _ = Darwin.shutdown(connecting, SHUT_RDWR)
        }
        if control >= 0 {
            _ = Darwin.shutdown(control, SHUT_RDWR)
            if !handshakeOwnsControl {
                Darwin.close(control)
            }
        }
        if passedInput >= 0 { Darwin.close(passedInput) }
        if passedOutput >= 0 { Darwin.close(passedOutput) }
        if write >= 0 {
            try? inputHandle.close()
        }
        if read >= 0 {
            try? outputHandle.close()
        }
        pendingReceive?(.failure(ProxyUpstreamTransportError.closed))
    }

    private func checkCancellation() throws {
        stateLock.lock()
        let isCancelled = cancelled
        stateLock.unlock()
        if isCancelled { throw ProxyUpstreamTransportError.closed }
    }

    private static func configureSocket(_ descriptor: Int32) throws {
        try configureCloseOnExec(descriptor)
        let currentFlags = Darwin.fcntl(descriptor, F_GETFL)
        guard currentFlags >= 0,
              Darwin.fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var enabled: Int32 = 1
        guard Darwin.setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func configurePipeWriter(_ descriptor: Int32) throws {
        guard Darwin.fcntl(descriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func configureCloseOnExec(_ descriptor: Int32) throws {
        guard Darwin.fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func protectedSocketIdentity(at path: String) throws -> SocketIdentity {
        var metadata = stat()
        let result = path.withCString { Darwin.lstat($0, &metadata) }
        guard result == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK),
              metadata.st_uid == geteuid(),
              metadata.st_nlink == 1,
              (metadata.st_mode & 0o077) == 0 else {
            throw ProxyUpstreamTransportError.controlSocketRejected
        }
        return SocketIdentity(
            device: UInt64(truncatingIfNeeded: metadata.st_dev),
            inode: UInt64(truncatingIfNeeded: metadata.st_ino)
        )
    }

    private static func connect(
        descriptor: Int32,
        path: String,
        deadline: UInt64
    ) throws {
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8CString)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= pathCapacity else {
            throw ProxyUpstreamTransportError.controlSocketRejected
        }
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) {
                    destination in
                    _ = memset(destination, 0, pathCapacity)
                    _ = memcpy(destination, source, pathBytes.count)
                }
            }
        }

        while true {
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(
                        descriptor,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_un>.size)
                    )
                }
            }
            if result == 0 { return }
            let connectError = errno
            if connectError == EINTR {
                try ensureBeforeDeadline(deadline)
                continue
            }
            guard connectError == EINPROGRESS
                    || connectError == EALREADY
                    || connectError == EAGAIN else {
                throw ProxyUpstreamTransportError.controlSocketRejected
            }
            try waitForConnection(descriptor, deadline: deadline)
            return
        }
    }

    private static func waitForConnection(
        _ descriptor: Int32,
        deadline: UInt64
    ) throws {
        while true {
            let timeout = try remainingMilliseconds(until: deadline)
            var descriptorState = pollfd(
                fd: descriptor,
                events: Int16(POLLOUT),
                revents: 0
            )
            let result = Darwin.poll(&descriptorState, 1, timeout)
            if result > 0 {
                guard descriptorState.revents & Int16(POLLNVAL) == 0 else {
                    throw ProxyUpstreamTransportError.closed
                }
                var socketError: Int32 = 0
                var socketErrorLength = socklen_t(MemoryLayout<Int32>.size)
                guard Darwin.getsockopt(
                    descriptor,
                    SOL_SOCKET,
                    SO_ERROR,
                    &socketError,
                    &socketErrorLength
                ) == 0 else {
                    throw ProxyUpstreamTransportError.closed
                }
                guard socketError == 0 else {
                    throw ProxyUpstreamTransportError.controlSocketRejected
                }
                return
            }
            if result == 0 {
                throw ProxyUpstreamTransportError.readinessTimedOut
            }
            if errno != EINTR {
                throw ProxyUpstreamTransportError.closed
            }
        }
    }

    private static func peerProcessID(for descriptor: Int32) throws -> Int32 {
        var processID: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard Darwin.getsockopt(
            descriptor,
            SOL_LOCAL,
            LOCAL_PEERPID,
            &processID,
            &length
        ) == 0,
        processID > 0 else {
            throw ProxyUpstreamTransportError.controlSocketRejected
        }
        return processID
    }

    private static func writePacket(
        _ body: Data,
        to descriptor: Int32,
        deadline: UInt64
    ) throws {
        guard body.count <= maximumPacketBytes else {
            throw ProxyUpstreamTransportError.protocolViolation
        }
        var framed = Data()
        appendUInt32(UInt32(body.count), to: &framed)
        framed.append(body)

        try framed.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var sent = 0
            while sent < buffer.count {
                try waitForDescriptor(
                    descriptor,
                    events: Int16(POLLOUT),
                    deadline: deadline
                )
                let count = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: sent),
                    buffer.count - sent,
                    0
                )
                if count > 0 {
                    sent += count
                } else if count < 0, errno == EINTR || errno == EAGAIN {
                    continue
                } else {
                    throw ProxyUpstreamTransportError.closed
                }
            }
        }
    }

    private static func readPacket(
        from descriptor: Int32,
        deadline: UInt64
    ) throws -> Data {
        let header = try readExactly(4, from: descriptor, deadline: deadline)
        var reader = PacketReader(data: header)
        let length = Int(try reader.readUInt32())
        guard length <= maximumPacketBytes else {
            throw ProxyUpstreamTransportError.protocolViolation
        }
        return try readExactly(length, from: descriptor, deadline: deadline)
    }

    private static func readExactly(
        _ count: Int,
        from descriptor: Int32,
        deadline: UInt64
    ) throws -> Data {
        var result = Data(count: count)
        var received = 0
        try result.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            while received < count {
                try waitForDescriptor(
                    descriptor,
                    events: Int16(POLLIN),
                    deadline: deadline
                )
                let next = Darwin.recv(
                    descriptor,
                    baseAddress.advanced(by: received),
                    count - received,
                    0
                )
                if next > 0 {
                    received += next
                } else if next < 0, errno == EINTR || errno == EAGAIN {
                    continue
                } else {
                    throw ProxyUpstreamTransportError.closed
                }
            }
        }
        return result
    }

    private static func sendFileDescriptor(
        _ passedDescriptor: Int32,
        to controlDescriptor: Int32,
        deadline: UInt64
    ) throws {
        let controlAlignment = max(
            MemoryLayout<cmsghdr>.alignment,
            MemoryLayout<Int32>.alignment
        )
        let descriptorOffset = alignedSize(
            MemoryLayout<cmsghdr>.size,
            to: controlAlignment
        )
        let messageLength = descriptorOffset + MemoryLayout<Int32>.size
        let controlSize = alignedSize(messageLength, to: controlAlignment)
        let control = UnsafeMutableRawPointer.allocate(
            byteCount: controlSize,
            alignment: controlAlignment
        )
        defer { control.deallocate() }
        _ = memset(control, 0, controlSize)

        let header = control.bindMemory(to: cmsghdr.self, capacity: 1)
        header.pointee.cmsg_len = socklen_t(messageLength)
        header.pointee.cmsg_level = SOL_SOCKET
        header.pointee.cmsg_type = SCM_RIGHTS
        control
            .advanced(by: descriptorOffset)
            .storeBytes(of: passedDescriptor, as: Int32.self)

        var payload: UInt8 = 0

        try withUnsafeMutablePointer(to: &payload) { payloadPointer in
            var vector = iovec(
                iov_base: UnsafeMutableRawPointer(payloadPointer),
                iov_len: 1
            )
            try withUnsafeMutablePointer(to: &vector) { vectorPointer in
                var message = msghdr()
                message.msg_iov = vectorPointer
                message.msg_iovlen = 1
                message.msg_control = control
                message.msg_controllen = socklen_t(controlSize)

                while true {
                    try waitForDescriptor(
                        controlDescriptor,
                        events: Int16(POLLOUT),
                        deadline: deadline
                    )
                    let sent = Darwin.sendmsg(controlDescriptor, &message, 0)
                    if sent == 1 { return }
                    if sent < 0, errno == EINTR || errno == EAGAIN {
                        continue
                    }
                    throw ProxyUpstreamTransportError.closed
                }
            }
        }
    }

    private static func alignedSize(_ size: Int, to alignment: Int) -> Int {
        (size + alignment - 1) & ~(alignment - 1)
    }

    private static func waitForDescriptor(
        _ descriptor: Int32,
        events: Int16,
        deadline: UInt64
    ) throws {
        while true {
            let timeout = try remainingMilliseconds(until: deadline)
            var descriptorState = pollfd(fd: descriptor, events: events, revents: 0)
            let result = Darwin.poll(&descriptorState, 1, timeout)
            if result > 0 {
                if descriptorState.revents & Int16(POLLNVAL | POLLERR) != 0 {
                    throw ProxyUpstreamTransportError.closed
                }
                return
            }
            if result == 0 {
                throw ProxyUpstreamTransportError.readinessTimedOut
            }
            if errno != EINTR {
                throw ProxyUpstreamTransportError.closed
            }
        }
    }

    private static func remainingMilliseconds(until deadline: UInt64) throws -> Int32 {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else {
            throw ProxyUpstreamTransportError.readinessTimedOut
        }
        let nanoseconds = deadline - now
        let milliseconds = max(1, (nanoseconds + 999_999) / 1_000_000)
        return Int32(min(milliseconds, UInt64(Int32.max)))
    }

    private static func ensureBeforeDeadline(_ deadline: UInt64) throws {
        guard DispatchTime.now().uptimeNanoseconds < deadline else {
            throw ProxyUpstreamTransportError.readinessTimedOut
        }
    }

    private static func validateHello(_ data: Data) throws {
        var reader = PacketReader(data: data)
        guard try reader.readUInt32() == muxMessageHello,
              try reader.readUInt32() == muxVersion else {
            throw ProxyUpstreamTransportError.protocolViolation
        }
        while !reader.isAtEnd {
            _ = try reader.readString()
            _ = try reader.readString()
        }
    }

    private static func validateAliveReply(
        _ data: Data,
        requestID: UInt32,
        expectedProcessID: Int32
    ) throws {
        var reader = PacketReader(data: data)
        guard try reader.readUInt32() == muxServerAlive,
              try reader.readUInt32() == requestID,
              try reader.readUInt32() == UInt32(expectedProcessID),
              reader.isAtEnd else {
            throw ProxyUpstreamTransportError.controlSocketRejected
        }
    }

    private static func validateForwardReply(
        _ data: Data,
        requestID: UInt32
    ) throws {
        var reader = PacketReader(data: data)
        let type = try reader.readUInt32()
        guard try reader.readUInt32() == requestID else {
            throw ProxyUpstreamTransportError.protocolViolation
        }
        switch type {
        case muxServerSessionOpened:
            _ = try reader.readUInt32()
            guard reader.isAtEnd else {
                throw ProxyUpstreamTransportError.protocolViolation
            }
        case muxServerPermissionDenied, muxServerFailure:
            _ = try reader.readString()
            throw ProxyUpstreamTransportError.unavailable
        default:
            throw ProxyUpstreamTransportError.protocolViolation
        }
    }

    private static func packetBody(uint32Values: [UInt32]) -> Data {
        var result = Data()
        for value in uint32Values {
            appendUInt32(value, to: &result)
        }
        return result
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    private static func appendString(_ value: Data, to data: inout Data) {
        appendUInt32(UInt32(value.count), to: &data)
        data.append(value)
    }
}

private extension SSHControlSocketAttestation {
    var socketIdentity: SSHDirectTCPTransport.SocketIdentity {
        SSHDirectTCPTransport.SocketIdentity(device: device, inode: inode)
    }
}
