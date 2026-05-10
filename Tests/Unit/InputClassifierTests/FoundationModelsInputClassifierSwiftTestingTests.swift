// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyInputClassifier

@Suite("Foundation Models input classifier")
struct FoundationModelsInputClassifierSwiftTestingTests {

    @Test("runtime availability is gated at compile time")
    func runtimeAvailabilityIsGatedAtCompileTime() {
        #if canImport(FoundationModels)
        #expect(FoundationModelsInputClassifier.isCompiledIn)
        #else
        #expect(!FoundationModelsInputClassifier.isCompiledIn)
        #endif
    }

    @Test("unsupported runtimes return nil without network fallback")
    func unsupportedRuntimesReturnNilWithoutNetworkFallback() async {
        let classifier = FoundationModelsInputClassifier()

        let result = await classifier.classify("explain how to list files")

        if !FoundationModelsInputClassifier.isRuntimeAvailable {
            #expect(result == nil)
        }
    }

    @Test("runtime availability cannot be true when framework is not compiled in")
    func runtimeAvailabilityCannotBeTrueWithoutFramework() {
        if !FoundationModelsInputClassifier.isCompiledIn {
            #expect(!FoundationModelsInputClassifier.isRuntimeAvailable)
        }
    }

    @Test("empty input has no model fallback on unsupported runtimes")
    func emptyInputHasNoModelFallbackOnUnsupportedRuntimes() async {
        let classifier = FoundationModelsInputClassifier()

        let result = await classifier.classify("")

        if !FoundationModelsInputClassifier.isRuntimeAvailable {
            #expect(result == nil)
        }
    }
}
