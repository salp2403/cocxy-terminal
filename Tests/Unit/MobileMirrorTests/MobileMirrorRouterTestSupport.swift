// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import WebKit
@testable import CocxyTerminal

protocol MobileMirrorRouterTestSupport {}

extension MobileMirrorRouterTestSupport {
    func request(
        method: String = "GET",
        path: String,
        host: String = "127.0.0.1:43120",
        query: [String: String] = [:],
        headers: [String: String] = [:],
        body: Data = Data()
    ) -> MobileMirrorHTTPRequest {
        let queryText = query.isEmpty
            ? ""
            : "?" + query.keys.sorted().map { "\($0)=\(query[$0] ?? "")" }.joined(separator: "&")
        var resolvedHeaders = headers
        resolvedHeaders["host"] = host
        return MobileMirrorHTTPRequest(
            method: method,
            target: path + queryText,
            path: path,
            query: query,
            version: "HTTP/1.1",
            headers: resolvedHeaders,
            body: body
        )
    }

    func response(from result: MobileMirrorHTTPRouteResult) throws -> MobileMirrorHTTPResponse {
        guard case .response(let response) = result else {
            throw MobileMirrorRouterTestError.expectedResponse
        }
        return response
    }

    func webLocalization(_ language: AppLanguage) throws -> MobileMirrorWebLocalization {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        guard let bundle = Bundle(
            url: root.appendingPathComponent("Resources/Localization", isDirectory: true)
        ) else {
            throw MobileMirrorRouterTestError.missingLocalizationBundle
        }
        return MobileMirrorWebLocalization(localizer: AppLocalizer(
            languagePreference: language,
            bundle: bundle
        ))
    }
}

enum MobileMirrorRouterTestError: Error {
    case expectedResponse
    case missingLocalizationBundle
}

final class MobileMirrorPairingSchemeHandler: NSObject, WKURLSchemeHandler {
    private let pairingHTML: Data
    private let lock = NSLock()
    private var _pairStatusRequestCount = 0

    init(pairingHTML: String) {
        self.pairingHTML = Data(pairingHTML.utf8)
    }

    var pairStatusRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _pairStatusRequestCount
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let body: Data
        let contentType: String
        switch url.path {
        case "/pair":
            body = pairingHTML
            contentType = "text/html; charset=utf-8"
        case "/mobile/api/pair-status":
            lock.lock()
            _pairStatusRequestCount += 1
            lock.unlock()
            body = Data(#"{"status":"confirmed","redirect":"/"}"#.utf8)
            contentType = "application/json"
        default:
            body = Data("<!doctype html><title>paired</title>".utf8)
            contentType = "text/html; charset=utf-8"
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        ) else {
            urlSchemeTask.didFailWithError(URLError(.badServerResponse))
            return
        }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(body)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
