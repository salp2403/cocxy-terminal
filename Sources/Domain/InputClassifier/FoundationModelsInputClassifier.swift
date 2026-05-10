// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public struct FoundationModelsInputClassifier: Sendable {
    public init() {}

    public static var isCompiledIn: Bool {
        #if canImport(FoundationModels)
        true
        #else
        false
        #endif
    }

    public static var isRuntimeAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    public func classify(_ input: String) async -> InputClassification? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await classifyWithFoundationModels(input)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private extension FoundationModelsInputClassifier {
    func classifyWithFoundationModels(_ input: String) async -> InputClassification? {
        guard Self.isRuntimeAvailable else { return nil }
        let boundedInput = String(input.prefix(1_000))
        let prompt = """
        Classify this terminal input locally. Return only JSON with keys:
        category: shell-command, natural-language, dangerous-command, or unknown
        confidence: number from 0 to 1
        languageCode: en, es, or null
        shouldWarnBeforeExecution: boolean

        Input:
        \(boundedInput)
        """

        do {
            let session = LanguageModelSession(
                model: .default,
                instructions: "You classify terminal input. You never execute commands."
            )
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(maximumResponseTokens: 128)
            )
            return Self.parseModelResponse(String(describing: response.content))
        } catch {
            return nil
        }
    }

    static func parseModelResponse(_ raw: String) -> InputClassification? {
        guard let data = raw.data(using: .utf8) else { return nil }
        struct Payload: Decodable {
            let category: InputClassificationCategory
            let confidence: Double
            let languageCode: String?
            let shouldWarnBeforeExecution: Bool?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        let routingHint: InputClassificationRoutingHint
        switch payload.category {
        case .naturalLanguage:
            routingHint = .offerAgentRouting
        case .shellCommand:
            routingHint = .executeInShell
        case .dangerousCommand:
            routingHint = .requireConfirmation
        case .empty:
            routingHint = .ignore
        case .unknown:
            routingHint = .none
        }
        return InputClassification(
            category: payload.category,
            confidence: payload.confidence,
            languageCode: payload.languageCode,
            shouldWarnBeforeExecution: payload.shouldWarnBeforeExecution
                ?? (payload.category == .dangerousCommand),
            routingHint: routingHint
        )
    }
}
#endif
