// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorHTTP.swift - Bounded HTTP contracts for the local gateway.

import Foundation

enum MobileMirrorHTTPError: Error, Equatable {
    case malformedRequest
    case headerTooLarge
    case bodyTooLarge
    case unsupportedTransferEncoding
    case duplicateSecurityHeader
}

struct MobileMirrorHTTPRequest: Equatable, Sendable {
    static let maximumHeaderBytes = 32 * 1_024
    static let maximumBodyBytes = 2 * 1_024 * 1_024 + 16 * 1_024

    let method: String
    let target: String
    let path: String
    let query: [String: String]
    let version: String
    let headers: [String: String]
    let body: Data

    var origin: String? { headers["origin"] }
    var userAgent: String { headers["user-agent"] ?? "Unknown device" }
    var host: String? { headers["host"] }

    func cookie(named name: String) -> String? {
        guard let cookieHeader = headers["cookie"] else { return nil }
        for component in cookieHeader.split(separator: ";", omittingEmptySubsequences: true) {
            let pair = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespaces) == name else {
                continue
            }
            return String(pair[1]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    static func parseIfComplete(_ data: Data) throws -> MobileMirrorHTTPRequest? {
        guard data.count <= maximumHeaderBytes + maximumBodyBytes else {
            throw MobileMirrorHTTPError.bodyTooLarge
        }
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > maximumHeaderBytes {
                throw MobileMirrorHTTPError.headerTooLarge
            }
            return nil
        }
        guard boundary.lowerBound <= maximumHeaderBytes,
              let headerText = String(data: data[..<boundary.lowerBound], encoding: .utf8) else {
            throw MobileMirrorHTTPError.malformedRequest
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw MobileMirrorHTTPError.malformedRequest
        }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count == 3 else { throw MobileMirrorHTTPError.malformedRequest }
        let method = String(requestParts[0]).uppercased()
        let target = String(requestParts[1])
        let version = String(requestParts[2])
        guard ["GET", "POST"].contains(method),
              target.hasPrefix("/"),
              target.utf8.count <= 4_096,
              ["HTTP/1.1", "HTTP/1.0"].contains(version) else {
            throw MobileMirrorHTTPError.malformedRequest
        }

        let protectedHeaders = Set([
            "authorization", "content-length", "cookie", "host", "origin",
            "x-cocxy-timestamp", "x-cocxy-nonce", "x-cocxy-signature",
            "x-cocxy-terminal-key",
        ])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else {
                throw MobileMirrorHTTPError.malformedRequest
            }
            let name = line[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  name.utf8.count <= 128,
                  value.utf8.count <= 8_192,
                  name.unicodeScalars.allSatisfy({ scalar in
                      scalar.isASCII && (scalar.properties.isAlphabetic
                          || scalar.properties.numericType != nil
                          || scalar == "-" || scalar == "_")
                  }) else {
                throw MobileMirrorHTTPError.malformedRequest
            }
            if headers[name] != nil, protectedHeaders.contains(name) {
                throw MobileMirrorHTTPError.duplicateSecurityHeader
            }
            if let existing = headers[name] {
                headers[name] = "\(existing), \(value)"
            } else {
                headers[name] = value
            }
        }
        if headers["transfer-encoding"] != nil {
            throw MobileMirrorHTTPError.unsupportedTransferEncoding
        }
        let contentLength: Int
        if let rawLength = headers["content-length"] {
            guard let parsed = Int(rawLength), parsed >= 0, parsed <= maximumBodyBytes else {
                throw MobileMirrorHTTPError.bodyTooLarge
            }
            contentLength = parsed
        } else {
            contentLength = 0
        }
        let bodyStart = boundary.upperBound
        let requiredLength = bodyStart + contentLength
        guard data.count >= requiredLength else { return nil }
        guard data.count == requiredLength else {
            throw MobileMirrorHTTPError.malformedRequest
        }

        let components = URLComponents(string: "http://local\(target)")
        guard let encodedPath = components?.percentEncodedPath,
              let path = encodedPath.removingPercentEncoding,
              !path.contains("\0") else {
            throw MobileMirrorHTTPError.malformedRequest
        }
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            guard query[item.name] == nil,
                  item.name.utf8.count <= 128,
                  item.value?.utf8.count ?? 0 <= 4_096 else {
                throw MobileMirrorHTTPError.malformedRequest
            }
            query[item.name] = item.value ?? ""
        }

        return MobileMirrorHTTPRequest(
            method: method,
            target: target,
            path: path,
            query: query,
            version: version,
            headers: headers,
            body: Data(data[bodyStart..<requiredLength])
        )
    }
}

struct MobileMirrorHTTPResponse: Equatable, Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data

    init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    static func json<T: Encodable>(
        _ value: T,
        status: Int = 200,
        headers: [String: String] = [:]
    ) -> Self {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let body = (try? encoder.encode(value)) ?? Data("{}".utf8)
        var resolvedHeaders = headers
        resolvedHeaders["Content-Type"] = "application/json; charset=utf-8"
        return Self(status: status, headers: resolvedHeaders, body: body)
    }

    static func html(_ value: String, status: Int = 200) -> Self {
        Self(
            status: status,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: Data(value.utf8)
        )
    }

    static func error(_ message: String, status: Int, code: MobileMirrorResponseCode) -> Self {
        json(MobileMirrorActionResponse.failure(message, code: code), status: status)
    }

    func encoded() -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 202: reason = "Accepted"
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 409: reason = "Conflict"
        case 413: reason = "Payload Too Large"
        case 429: reason = "Too Many Requests"
        case 500: reason = "Internal Server Error"
        case 503: reason = "Service Unavailable"
        default: reason = "Response"
        }
        var resolvedHeaders = headers
        resolvedHeaders["Content-Length"] = String(body.count)
        resolvedHeaders["Connection"] = "close"
        resolvedHeaders["Cache-Control"] = resolvedHeaders["Cache-Control"] ?? "no-store"
        resolvedHeaders["X-Content-Type-Options"] = "nosniff"
        resolvedHeaders["Referrer-Policy"] = "no-referrer"
        resolvedHeaders["Content-Security-Policy"] = resolvedHeaders["Content-Security-Policy"]
            ?? "default-src 'none'; frame-ancestors 'none'; base-uri 'none'"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        for key in resolvedHeaders.keys.sorted() {
            head += "\(key): \(resolvedHeaders[key] ?? "")\r\n"
        }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}

struct MobileMirrorProxyTarget: Equatable, Sendable {
    let port: UInt16
    let bearerToken: String
    let rewrittenPath: String
    let terminalEncryptionKey: Data?

    init(
        port: UInt16,
        bearerToken: String,
        rewrittenPath: String,
        terminalEncryptionKey: Data? = nil
    ) {
        self.port = port
        self.bearerToken = bearerToken
        self.rewrittenPath = rewrittenPath
        self.terminalEncryptionKey = terminalEncryptionKey
    }
}

enum MobileMirrorHTTPRouteResult: Sendable {
    case response(MobileMirrorHTTPResponse)
    case proxy(MobileMirrorProxyTarget)
    case eventStream
}
