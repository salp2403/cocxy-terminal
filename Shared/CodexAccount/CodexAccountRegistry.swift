// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodexAccountRegistry.swift - Safe local Codex account discovery and selection.

import Foundation

public struct CodexAccount: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let email: String
    public let displayName: String?
    public let sourcePath: String?

    public init(id: String, email: String, displayName: String? = nil, sourcePath: String? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.sourcePath = sourcePath
    }
}

public enum CodexAccountScanner {
    public static func defaultAuthJSONURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory.appendingPathComponent(".codex/auth.json", isDirectory: false)
    }

    public static func accounts(authJSONURL: URL = defaultAuthJSONURL()) -> [CodexAccount] {
        guard let data = try? Data(contentsOf: authJSONURL) else { return [] }
        return accounts(inAuthJSONData: data, sourcePath: authJSONURL.path)
    }

    public static func accounts(inAuthJSONData data: Data, sourcePath: String? = nil) -> [CodexAccount] {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            JSONSerialization.isValidJSONObject(object)
        else {
            return []
        }

        var discovered: [CodexAccount] = []
        walk(object) { dictionary in
            if let direct = account(from: dictionary, sourcePath: sourcePath) {
                discovered.append(direct)
            }
            if let jwt = accountFromIDToken(in: dictionary, sourcePath: sourcePath) {
                discovered.append(jwt)
            }
        }

        var seen = Set<String>()
        return discovered.filter { account in
            let key = account.id.lowercased() + "|" + account.email.lowercased()
            return seen.insert(key).inserted
        }
    }

    private static func walk(_ object: Any, visit: ([String: Any]) -> Void) {
        if let dictionary = object as? [String: Any] {
            visit(dictionary)
            for value in dictionary.values {
                walk(value, visit: visit)
            }
        } else if let array = object as? [Any] {
            for value in array {
                walk(value, visit: visit)
            }
        }
    }

    private static func stringValue(forAnyOf keys: [String], in dictionary: [String: Any]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, value.isEmpty == false {
                return value
            }
        }
        return nil
    }

    private static func account(from dictionary: [String: Any], sourcePath: String?) -> CodexAccount? {
        guard let email = stringValue(forAnyOf: ["email", "login_email", "account_email"], in: dictionary),
              email.contains("@") else {
            return nil
        }
        let id = stringValue(forAnyOf: ["id", "account_id", "sub", "user_id"], in: dictionary)
            ?? email.lowercased()
        let displayName = stringValue(forAnyOf: ["name", "display_name", "login"], in: dictionary)
        return CodexAccount(id: id, email: email, displayName: displayName, sourcePath: sourcePath)
    }

    private static func accountFromIDToken(in dictionary: [String: Any], sourcePath: String?) -> CodexAccount? {
        guard let token = dictionary["id_token"] as? String,
              let payload = jwtPayloadDictionary(from: token),
              let email = stringValue(forAnyOf: ["email"], in: payload),
              email.contains("@") else {
            return nil
        }

        let id = stringValue(forAnyOf: ["account_id", "id", "sub", "user_id"], in: dictionary)
            ?? stringValue(forAnyOf: ["account_id", "id", "sub", "user_id"], in: payload)
            ?? email.lowercased()
        let displayName = stringValue(forAnyOf: ["name", "display_name", "login"], in: payload)
            ?? stringValue(forAnyOf: ["name", "display_name", "login"], in: dictionary)
        return CodexAccount(id: id, email: email, displayName: displayName, sourcePath: sourcePath)
    }

    private static func jwtPayloadDictionary(from token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }
}

public struct CodexAccountSelection: Codable, Sendable, Equatable {
    public let selectedAccountID: String?

    public init(selectedAccountID: String?) {
        self.selectedAccountID = selectedAccountID
    }
}

public enum CodexAccountSelectionStore {
    public static func defaultSelectionURL(
        applicationSupportDirectory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    ) -> URL {
        let base = applicationSupportDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("CocxyTerminal", isDirectory: true)
            .appendingPathComponent("codex-account-selection.json", isDirectory: false)
    }

    public static func load(from url: URL) -> CodexAccountSelection {
        guard let data = try? Data(contentsOf: url),
              let selection = try? JSONDecoder().decode(CodexAccountSelection.self, from: data) else {
            return CodexAccountSelection(selectedAccountID: nil)
        }
        return selection
    }

    public static func save(_ selection: CodexAccountSelection, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(selection)
        try data.write(to: url, options: [.atomic])
    }
}
