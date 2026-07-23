// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserImportViewModel.swift - State machine for the browser import wizard.

import Foundation
import SwiftUI

enum BrowserImportWizardFailure: Sendable, Equatable {
    case destinationUnavailable
    case remoteDestination
    case destinationBusy
    case sourceChanged
    case sourceUnavailable
    case sourceReadFailed
    case noImportableData
    case cookieAccessFailed
    case operation(String)
}

@MainActor
final class BrowserImportViewModel: ObservableObject {
    enum Step: Int, CaseIterable, Identifiable, Sendable {
        case source
        case data
        case filters
        case review

        var id: Int { rawValue }
    }

    enum HistoryRange: String, CaseIterable, Identifiable, Sendable, Hashable {
        case allTime
        case thirtyDays
        case ninetyDays
        case oneYear

        var id: String { rawValue }

        var maximumDays: Int? {
            switch self {
            case .allTime: return nil
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            case .oneYear: return 365
            }
        }
    }

    let destinationProfiles: [BrowserProfile]
    let historyDestinationAvailable: Bool
    let cookieDestinationAvailable: Bool
    let bookmarkDestinationAvailable: Bool

    @Published private(set) var step: Step = .source
    @Published private(set) var discoveries: [BrowserImportSourceDiscovery]
    @Published var selectedSource: BrowserImportSource {
        didSet {
            guard oldValue != selectedSource else { return }
            synchronizeSourceProfileSelection()
        }
    }
    @Published var selectedSourceProfileID: String? {
        didSet {
            guard oldValue != selectedSourceProfileID else { return }
            synchronizeDataSelections()
            clearReviewState()
        }
    }
    @Published var selectedDestinationProfileID: UUID? {
        didSet {
            guard oldValue != selectedDestinationProfileID else { return }
            clearReviewState()
        }
    }
    @Published var importHistory = false
    @Published var importCookies = false
    @Published var importBookmarks = false
    @Published var historyRange: HistoryRange = .allTime
    @Published var domainAllowList = ""
    @Published var domainBlockList = ""
    @Published private(set) var preview: BrowserImportPreview?
    @Published private(set) var result: BrowserImportResult?
    @Published private(set) var failure: BrowserImportWizardFailure?
    @Published private(set) var isDiscovering = false
    @Published private(set) var isPreviewing = false
    @Published private(set) var isImporting = false
    @Published private(set) var isCancellingImport = false

    var onImportCompleted: ((BrowserImportResult) -> Void)?

    private let service: any BrowserImportServicing
    private let destinationProfileProvider: @MainActor () -> [BrowserProfile]
    private weak var destinationProfileManager: BrowserProfileManager?
    private var discoveryTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var discoveryGeneration: UInt = 0
    private var previewGeneration: UInt = 0
    private var importGeneration: UInt = 0
    private var reviewedPreviewToken: String?
    private var hasStarted = false

    init(
        destinationProfiles: [BrowserProfile],
        initialDestinationProfileID: UUID?,
        historyDestinationAvailable: Bool,
        cookieDestinationAvailable: Bool,
        bookmarkDestinationAvailable: Bool,
        service: any BrowserImportServicing,
        destinationProfileProvider: @escaping @MainActor () -> [BrowserProfile],
        destinationProfileManager: BrowserProfileManager? = nil
    ) {
        self.destinationProfiles = destinationProfiles
        self.historyDestinationAvailable = historyDestinationAvailable
        self.cookieDestinationAvailable = cookieDestinationAvailable
        self.bookmarkDestinationAvailable = bookmarkDestinationAvailable
        self.service = service
        self.destinationProfileProvider = destinationProfileProvider
        self.destinationProfileManager = destinationProfileManager
        self.discoveries = BrowserImportSource.allCases.map {
            BrowserImportSourceDiscovery(source: $0, profiles: [])
        }
        self.selectedSource = .chrome

        let localProfiles = destinationProfiles.filter { !$0.isRemoteBacked }
        if let initialDestinationProfileID,
           localProfiles.contains(where: { $0.id == initialDestinationProfileID }) {
            self.selectedDestinationProfileID = initialDestinationProfileID
        } else {
            self.selectedDestinationProfileID = localProfiles.first?.id
        }
    }

    var selectedDiscovery: BrowserImportSourceDiscovery? {
        discoveries.first { $0.source == selectedSource }
    }

    var selectedSourceProfile: BrowserImportSourceProfile? {
        guard let selectedSourceProfileID else { return nil }
        return selectedDiscovery?.profiles.first { $0.id == selectedSourceProfileID }
    }

    var selectedDestinationProfile: BrowserProfile? {
        guard let selectedDestinationProfileID else { return nil }
        return destinationProfiles.first { $0.id == selectedDestinationProfileID }
    }

    var detectedSourceCount: Int {
        discoveries.lazy.filter(\.isDetected).count
    }

    var selectedDataCount: Int {
        [importHistory, importCookies, importBookmarks].filter { $0 }.count
    }

    var invalidDomainRules: [String] {
        let allow = Self.parseDomainRules(domainAllowList)
        let block = Self.parseDomainRules(domainBlockList)
        return Array(Set(allow.invalid + block.invalid)).sorted()
    }

    var conflictingDomainRules: [String] {
        let allow = Set(Self.parseDomainRules(domainAllowList).values)
        let block = Set(Self.parseDomainRules(domainBlockList).values)
        return Array(allow.intersection(block)).sorted()
    }

    var isBusy: Bool {
        isDiscovering || isPreviewing || isImporting
    }

    var canGoBack: Bool {
        step != .source && result == nil && !isImporting
    }

    var canAdvance: Bool {
        switch step {
        case .source:
            return selectedSourceProfile != nil && !isDiscovering
        case .data:
            return selectedDestinationProfile != nil && selectedDataCount > 0
        case .filters:
            return invalidDomainRules.isEmpty && conflictingDomainRules.isEmpty
        case .review:
            return (preview?.itemCount ?? 0) > 0 && !isPreviewing && !isImporting && result == nil
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshDiscovery()
    }

    func refreshDiscovery() {
        discoveryTask?.cancel()
        discoveryGeneration &+= 1
        let generation = discoveryGeneration
        isDiscovering = true
        failure = nil
        let service = self.service

        discoveryTask = Task.detached(priority: .userInitiated) { [weak self, service] in
            let discovered = service.discoverSources()
            guard !Task.isCancelled else { return }
            await self?.applyDiscovery(discovered, generation: generation)
        }
    }

    func cancelPendingWork() {
        discoveryTask?.cancel()
        previewTask?.cancel()
        importTask?.cancel()
        discoveryTask = nil
        previewTask = nil
        importTask = nil
        discoveryGeneration &+= 1
        previewGeneration &+= 1
        importGeneration &+= 1
        isDiscovering = false
        isPreviewing = false
        isImporting = false
        isCancellingImport = false
    }

    func requestImportCancellation() {
        guard isImporting, !isCancellingImport else { return }
        isCancellingImport = true
        importTask?.cancel()
    }

    func advance() {
        guard canAdvance else { return }
        switch step {
        case .source:
            step = .data
        case .data:
            step = .filters
        case .filters:
            loadPreview()
        case .review:
            startImport()
        }
    }

    func goBack() {
        guard canGoBack,
              let previous = Step(rawValue: step.rawValue - 1) else { return }
        previewTask?.cancel()
        previewGeneration &+= 1
        isPreviewing = false
        preview = nil
        reviewedPreviewToken = nil
        failure = nil
        step = previous
    }

    func retryPreview() {
        guard step == .review, !isImporting, result == nil else { return }
        loadPreview()
    }

    func isDataAvailable(_ kind: BrowserImportDataKind) -> Bool {
        guard selectedSourceProfile?.availableData.contains(kind) == true else { return false }
        switch kind {
        case .history: return historyDestinationAvailable
        case .cookies: return cookieDestinationAvailable
        case .bookmarks: return bookmarkDestinationAvailable
        }
    }

    func makePlan() -> BrowserImportPlan? {
        guard let sourceProfile = selectedSourceProfile,
              let destinationID = selectedDestinationProfileID,
              selectedDataCount > 0,
              invalidDomainRules.isEmpty,
              conflictingDomainRules.isEmpty else { return nil }

        return BrowserImportPlan(
            source: selectedSource,
            profileID: destinationID,
            importCookies: importCookies,
            importHistory: importHistory,
            importBookmarks: importBookmarks,
            maxHistoryDays: historyRange.maximumDays,
            domainWhitelist: Self.parseDomainRules(domainAllowList).values,
            domainBlacklist: Self.parseDomainRules(domainBlockList).values,
            sourceProfile: sourceProfile.location.profileIdentifier,
            explicitLocations: [sourceProfile.location],
            expectedPreviewToken: reviewedPreviewToken
        )
    }

    static func parseDomainRules(_ rawValue: String) -> (values: [String], invalid: [String]) {
        let components = rawValue.split { character in
            character == "," || character == ";" || character.isWhitespace
        }
        var values: [String] = []
        var invalid: [String] = []
        var seen = Set<String>()

        for component in components {
            let raw = String(component)
            let normalized = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: ".[]"))
            guard isValidDomainRule(normalized) else {
                invalid.append(raw)
                continue
            }
            if seen.insert(normalized).inserted {
                values.append(normalized)
            }
        }
        return (values, invalid)
    }

    private static func isValidDomainRule(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 253,
              !value.contains("/"), !value.contains("@") else { return false }
        if value.contains(":") {
            return URL(string: "http://[\(value)]")?.host != nil
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        return value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            guard !label.isEmpty, label.utf8.count <= 63,
                  label.first != "-", label.last != "-" else { return false }
            return label.unicodeScalars.allSatisfy(allowed.contains)
        }
    }

    private func synchronizeSourceProfileSelection() {
        let profiles = selectedDiscovery?.profiles ?? []
        if let selectedSourceProfileID,
           profiles.contains(where: { $0.id == selectedSourceProfileID }) {
            synchronizeDataSelections()
        } else {
            selectedSourceProfileID = profiles.first?.id
            if profiles.isEmpty {
                synchronizeDataSelections()
            }
        }
        clearReviewState()
    }

    private func synchronizeDataSelections() {
        importHistory = isDataAvailable(.history)
        importCookies = isDataAvailable(.cookies)
        importBookmarks = isDataAvailable(.bookmarks)
    }

    private func clearReviewState() {
        preview = nil
        reviewedPreviewToken = nil
        result = nil
        failure = nil
    }

    private func loadPreview() {
        guard let plan = makePlan() else { return }
        previewTask?.cancel()
        previewGeneration &+= 1
        let generation = previewGeneration
        step = .review
        preview = nil
        reviewedPreviewToken = nil
        result = nil
        failure = nil
        isPreviewing = true
        let service = self.service

        previewTask = Task.detached(priority: .userInitiated) { [weak self, service] in
            do {
                let value = try service.preview(plan)
                try Task.checkCancellation()
                await self?.applyPreview(value, plan: plan, generation: generation)
            } catch {
                let wasCancelled = error is CancellationError
                    || (error as? BrowserImportError) == .cancelled
                    || Task.isCancelled
                await self?.applyPreviewFailure(
                    wasCancelled ? nil : Self.presentationFailure(for: error),
                    generation: generation
                )
            }
        }
    }

    private func applyDiscovery(
        _ discovered: [BrowserImportSourceDiscovery],
        generation: UInt
    ) {
        guard generation == discoveryGeneration else { return }
        discoveries = discovered
        isDiscovering = false

        let currentIsDetected = discovered.first(where: {
            $0.source == selectedSource
        })?.isDetected == true
        if !currentIsDetected,
           let firstDetected = discovered.first(where: \.isDetected) {
            selectedSource = firstDetected.source
        } else {
            synchronizeSourceProfileSelection()
        }
    }

    private func applyPreview(
        _ value: BrowserImportPreview,
        plan: BrowserImportPlan,
        generation: UInt
    ) {
        guard generation == previewGeneration else { return }
        preview = value
        reviewedPreviewToken = BrowserImportPreviewToken.make(preview: value, plan: plan)
        isPreviewing = false
    }

    private func applyPreviewFailure(
        _ previewFailure: BrowserImportWizardFailure?,
        generation: UInt
    ) {
        guard generation == previewGeneration else { return }
        failure = previewFailure
        isPreviewing = false
    }

    private func startImport() {
        guard let plan = makePlan(), canAdvance else { return }
        guard let destination = destinationProfileProvider().first(where: { $0.id == plan.profileID }) else {
            failure = .destinationUnavailable
            return
        }
        guard !destination.isRemoteBacked else {
            failure = .remoteDestination
            return
        }
        let reservation: BrowserProfileImportReservation?
        if let destinationProfileManager {
            guard let acquired = destinationProfileManager.beginImport(to: plan.profileID) else {
                failure = .destinationBusy
                return
            }
            reservation = acquired
        } else {
            reservation = nil
        }

        isImporting = true
        isCancellingImport = false
        failure = nil
        importGeneration &+= 1
        let generation = importGeneration
        let service = self.service
        let profileManager = destinationProfileManager
        let completion = onImportCompleted
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try service.run(plan)
        }
        importTask = Task { [weak self, weak profileManager] in
            defer {
                if let reservation {
                    profileManager?.endImport(reservation)
                }
            }
            do {
                let importResult = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard let self, generation == self.importGeneration else { return }
                self.result = importResult
                self.isImporting = false
                self.isCancellingImport = false
                self.importTask = nil
                completion?(importResult)
            } catch {
                guard let self, generation == self.importGeneration else { return }
                if (error as? BrowserImportError) == .sourceChangedAfterPreview {
                    self.preview = nil
                    self.reviewedPreviewToken = nil
                    self.failure = .sourceChanged
                } else {
                    self.failure = Self.presentationFailure(for: error)
                }
                self.isImporting = false
                self.isCancellingImport = false
                self.importTask = nil
            }
        }
    }

    nonisolated private static func presentationFailure(
        for error: Error
    ) -> BrowserImportWizardFailure? {
        if error is CancellationError { return nil }
        guard let importError = error as? BrowserImportError else {
            return .operation(error.localizedDescription)
        }
        switch importError {
        case .sourceChangedAfterPreview:
            return .sourceChanged
        case .invalidSourceFile, .sourceProfileUnavailable:
            return .sourceUnavailable
        case .databaseOpenFailed, .statementFailed, .sourceChangedDuringRead:
            return .sourceReadFailed
        case .noImportableData:
            return .noImportableData
        case .cookieDecryptionFailed:
            return .cookieAccessFailed
        case .bookmarkRootConflict:
            return .operation(importError.localizedDescription)
        case .cancelled:
            return nil
        }
    }
}
