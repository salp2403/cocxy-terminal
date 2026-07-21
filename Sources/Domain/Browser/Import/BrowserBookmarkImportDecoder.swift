// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserBookmarkImportDecoder.swift - Bounded bookmark decoders for browser exports.

import Foundation

enum BrowserBookmarkImportDecoder {
    private static let maximumFileSize = 64 * 1_024 * 1_024
    private static let maximumItems = 100_000
    private static let maximumDepth = 64

    static func chromiumBookmarks(from url: URL) throws -> [BrowserImportedBookmark] {
        let data = try BrowserImportFileReader.readData(from: url, maximumByteCount: maximumFileSize)
        guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = document["roots"] as? [String: Any] else {
            throw BrowserImportError.invalidSourceFile(url.path)
        }

        let orderedRoots: [(String, String)] = [
            ("bookmark_bar", "Bookmarks Bar"),
            ("other", "Other Bookmarks"),
            ("synced", "Mobile Bookmarks"),
        ]
        var bookmarks: [BrowserImportedBookmark] = []
        for (key, fallbackName) in orderedRoots {
            guard let node = roots[key] as? [String: Any] else { continue }
            let rootName = normalizedTitle(node["name"] as? String, fallback: fallbackName)
            appendChromiumChildren(
                node["children"] as? [[String: Any]] ?? [],
                folderPath: [rootName],
                depth: 0,
                output: &bookmarks
            )
            if bookmarks.count >= maximumItems { break }
        }
        return bookmarks
    }

    static func safariBookmarks(from url: URL) throws -> [BrowserImportedBookmark] {
        let data = try BrowserImportFileReader.readData(from: url, maximumByteCount: maximumFileSize)
        let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let root = propertyList as? [String: Any] else {
            throw BrowserImportError.invalidSourceFile(url.path)
        }
        var bookmarks: [BrowserImportedBookmark] = []
        appendSafariChildren(
            root["Children"] as? [[String: Any]] ?? [],
            folderPath: [],
            depth: 0,
            output: &bookmarks
        )
        return bookmarks
    }

    private static func appendChromiumChildren(
        _ children: [[String: Any]],
        folderPath: [String],
        depth: Int,
        output: inout [BrowserImportedBookmark]
    ) {
        guard depth < maximumDepth, output.count < maximumItems else { return }
        for (index, child) in children.enumerated() where output.count < maximumItems {
            let type = child["type"] as? String
            if type == "url", let rawURL = child["url"] as? String, validURL(rawURL) {
                output.append(BrowserImportedBookmark(
                    title: normalizedTitle(child["name"] as? String, fallback: rawURL),
                    url: rawURL,
                    folderPath: folderPath,
                    createdAt: chromiumDate(child["date_added"]),
                    sortOrder: index
                ))
            } else if type == "folder" {
                let name = normalizedTitle(child["name"] as? String, fallback: "Folder")
                appendChromiumChildren(
                    child["children"] as? [[String: Any]] ?? [],
                    folderPath: folderPath + [name],
                    depth: depth + 1,
                    output: &output
                )
            }
        }
    }

    private static func appendSafariChildren(
        _ children: [[String: Any]],
        folderPath: [String],
        depth: Int,
        output: inout [BrowserImportedBookmark]
    ) {
        guard depth < maximumDepth, output.count < maximumItems else { return }
        for (index, child) in children.enumerated() where output.count < maximumItems {
            if let rawURL = child["URLString"] as? String, validURL(rawURL) {
                let uriDictionary = child["URIDictionary"] as? [String: Any]
                let title = normalizedTitle(
                    uriDictionary?["title"] as? String ?? child["Title"] as? String,
                    fallback: rawURL
                )
                output.append(BrowserImportedBookmark(
                    title: title,
                    url: rawURL,
                    folderPath: folderPath,
                    sortOrder: index
                ))
                continue
            }
            guard let nested = child["Children"] as? [[String: Any]] else { continue }
            let title = normalizedTitle(child["Title"] as? String, fallback: "Folder")
            appendSafariChildren(
                nested,
                folderPath: folderPath + [title],
                depth: depth + 1,
                output: &output
            )
        }
    }

    private static func chromiumDate(_ rawValue: Any?) -> Date? {
        let microseconds: Int64?
        if let value = rawValue as? String {
            microseconds = Int64(value)
        } else if let value = rawValue as? NSNumber {
            microseconds = value.int64Value
        } else {
            microseconds = nil
        }
        return microseconds.flatMap(BrowserImportDateConverter.chromeDate)
    }

    private static func normalizedTitle(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String((trimmed.isEmpty ? fallback : trimmed).prefix(2_048))
    }

    private static func validURL(_ rawValue: String) -> Bool {
        guard rawValue.utf8.count <= 16_384,
              let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "file", "ftp"].contains(scheme)
    }
}

enum SafariBinaryCookieDecoder {
    private static let maximumFileSize = 256 * 1_024 * 1_024
    private static let maximumCookieCount = 100_000

    static func cookies(from url: URL, includeValues: Bool) throws -> [BrowserImportedCookie] {
        let data = try BrowserImportFileReader.readData(from: url, maximumByteCount: maximumFileSize)
        guard data.count >= 8,
              data.prefix(4) == Data("cook".utf8),
              let pageCount = uint32BE(data, at: 4),
              pageCount <= 16_384 else {
            throw BrowserImportError.invalidSourceFile(url.path)
        }

        let sizeTableEnd = 8 + Int(pageCount) * 4
        guard sizeTableEnd <= data.count else {
            throw BrowserImportError.invalidSourceFile(url.path)
        }
        var pageSizes: [Int] = []
        pageSizes.reserveCapacity(Int(pageCount))
        for index in 0..<Int(pageCount) {
            guard let size = uint32BE(data, at: 8 + index * 4), size > 0 else {
                throw BrowserImportError.invalidSourceFile(url.path)
            }
            pageSizes.append(Int(size))
        }

        var cookies: [BrowserImportedCookie] = []
        var cursor = sizeTableEnd
        for pageSize in pageSizes {
            guard pageSize <= data.count - cursor else {
                throw BrowserImportError.invalidSourceFile(url.path)
            }
            let page = data.subdata(in: cursor..<(cursor + pageSize))
            try appendCookies(fromPage: page, includeValues: includeValues, output: &cookies)
            cursor += pageSize
            if cookies.count >= maximumCookieCount { break }
        }
        return cookies
    }

    private static func appendCookies(
        fromPage page: Data,
        includeValues: Bool,
        output: inout [BrowserImportedCookie]
    ) throws {
        guard page.count >= 12,
              uint32LE(page, at: 0) == 0x0000_0100,
              let cookieCount = uint32LE(page, at: 4),
              cookieCount <= UInt32(maximumCookieCount),
              8 + Int(cookieCount) * 4 <= page.count else {
            throw BrowserImportError.invalidSourceFile("Cookies.binarycookies")
        }

        for index in 0..<Int(cookieCount) where output.count < maximumCookieCount {
            guard let rawOffset = uint32LE(page, at: 8 + index * 4) else {
                throw BrowserImportError.invalidSourceFile("Cookies.binarycookies")
            }
            let offset = Int(rawOffset)
            guard offset >= 0, offset + 56 <= page.count,
                  let rawSize = uint32LE(page, at: offset),
                  rawSize >= 56,
                  Int(rawSize) <= page.count - offset else {
                throw BrowserImportError.invalidSourceFile("Cookies.binarycookies")
            }
            let record = page.subdata(in: offset..<(offset + Int(rawSize)))
            guard let flags = uint32LE(record, at: 8),
                  let domainOffset = uint32LE(record, at: 16),
                  let nameOffset = uint32LE(record, at: 20),
                  let pathOffset = uint32LE(record, at: 24),
                  let valueOffset = uint32LE(record, at: 28),
                  let domain = nullTerminatedUTF8(record, at: Int(domainOffset)),
                  let name = nullTerminatedUTF8(record, at: Int(nameOffset)),
                  let path = nullTerminatedUTF8(record, at: Int(pathOffset)),
                  let rawValue = nullTerminatedUTF8(record, at: Int(valueOffset)),
                  !domain.isEmpty else {
                throw BrowserImportError.invalidSourceFile("Cookies.binarycookies")
            }
            let expiresAt = doubleLE(record, at: 40).flatMap { value in
                value > 0 ? Date(timeIntervalSinceReferenceDate: value) : nil
            }
            output.append(BrowserImportedCookie(
                domain: domain,
                name: name,
                path: path.isEmpty ? "/" : path,
                value: includeValues ? rawValue : nil,
                expiresAt: expiresAt,
                isSecure: flags & 0x1 != 0,
                isHTTPOnly: flags & 0x4 != 0,
                sourceValueFingerprint: BrowserImportPreviewToken.fingerprint(Data(rawValue.utf8))
            ))
        }
    }

    private static func uint32BE(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func uint32LE(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        var result: UInt32 = 0
        for index in 0..<4 {
            result |= UInt32(data[offset + index]) << UInt32(index * 8)
        }
        return result
    }

    private static func doubleLE(_ data: Data, at offset: Int) -> Double? {
        guard offset >= 0, offset + 8 <= data.count else { return nil }
        var bits: UInt64 = 0
        for index in 0..<8 {
            bits |= UInt64(data[offset + index]) << UInt64(index * 8)
        }
        let value = Double(bitPattern: bits)
        return value.isFinite ? value : nil
    }

    private static func nullTerminatedUTF8(_ data: Data, at offset: Int) -> String? {
        guard offset >= 0, offset < data.count else { return nil }
        let end = data[offset...].firstIndex(of: 0) ?? data.endIndex
        guard end - offset <= 16_384 else { return nil }
        return String(data: data[offset..<end], encoding: .utf8)
    }
}
