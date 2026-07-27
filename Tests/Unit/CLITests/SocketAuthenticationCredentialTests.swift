// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CocxyShared
import Darwin
import Foundation
import XCTest

final class SocketAuthenticationCredentialTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-auth-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    func testProtectedCredentialRoundTrips() throws {
        let path = directory.appendingPathComponent("cocxy.sock.token").path
        let token = String(
            repeating: "a1",
            count: SocketAuthenticationCredential.tokenByteCount
        )

        try SocketAuthenticationCredential.write(token, to: path)

        XCTAssertEqual(try SocketAuthenticationCredential.read(from: path), token)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        XCTAssertEqual((attributes[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o600)
    }

    func testCredentialReaderRejectsBroadenedPermissions() throws {
        let path = directory.appendingPathComponent("cocxy.sock.token").path
        let token = String(
            repeating: "b2",
            count: SocketAuthenticationCredential.tokenByteCount
        )
        try SocketAuthenticationCredential.write(token, to: path)
        XCTAssertEqual(Darwin.chmod(path, 0o644), 0)

        XCTAssertThrowsError(try SocketAuthenticationCredential.read(from: path)) { error in
            XCTAssertEqual(
                error as? SocketAuthenticationCredentialError,
                .unsafeCredentialFile
            )
        }
    }

    func testCredentialReaderRejectsSymbolicLinks() throws {
        let target = directory.appendingPathComponent("target.token")
        let link = directory.appendingPathComponent("cocxy.sock.token")
        let token = String(
            repeating: "c3",
            count: SocketAuthenticationCredential.tokenByteCount
        )
        try SocketAuthenticationCredential.write(token, to: target.path)
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: target
        )

        XCTAssertThrowsError(try SocketAuthenticationCredential.read(from: link.path))
    }

    func testCredentialWriterReplacesSymlinkWithoutTouchingTarget() throws {
        let target = directory.appendingPathComponent("target.token")
        let link = directory.appendingPathComponent("cocxy.sock.token")
        let original = Data("do-not-change".utf8)
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: target
        )
        let token = String(
            repeating: "f6",
            count: SocketAuthenticationCredential.tokenByteCount
        )

        try SocketAuthenticationCredential.write(token, to: link.path)

        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertEqual(try SocketAuthenticationCredential.read(from: link.path), token)
    }

    func testCredentialReaderRejectsHardLinkedFiles() throws {
        let credential = directory.appendingPathComponent("cocxy.sock.token")
        let secondLink = directory.appendingPathComponent("second.token")
        let token = String(
            repeating: "a7",
            count: SocketAuthenticationCredential.tokenByteCount
        )
        try SocketAuthenticationCredential.write(token, to: credential.path)
        try FileManager.default.linkItem(at: credential, to: secondLink)

        XCTAssertThrowsError(
            try SocketAuthenticationCredential.read(from: credential.path)
        ) { error in
            XCTAssertEqual(
                error as? SocketAuthenticationCredentialError,
                .unsafeCredentialFile
            )
        }
    }

    func testTokenValidationAndComparisonFailClosed() {
        let token = String(
            repeating: "d4",
            count: SocketAuthenticationCredential.tokenByteCount
        )
        let different = String(
            repeating: "e5",
            count: SocketAuthenticationCredential.tokenByteCount
        )

        XCTAssertTrue(SocketAuthenticationCredential.isValidToken(token))
        XCTAssertTrue(SocketAuthenticationCredential.securelyMatches(token, expected: token))
        XCTAssertFalse(SocketAuthenticationCredential.securelyMatches(nil, expected: token))
        XCTAssertFalse(SocketAuthenticationCredential.securelyMatches("", expected: token))
        XCTAssertFalse(SocketAuthenticationCredential.securelyMatches(different, expected: token))
        XCTAssertFalse(SocketAuthenticationCredential.isValidToken(token.uppercased()))
    }
}
