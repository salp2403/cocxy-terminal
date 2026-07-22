// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserImportWizardView.swift - Native four-step browser import sheet.

import SwiftUI

struct BrowserImportWizardView: View {
    @ObservedObject var viewModel: BrowserImportViewModel
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stepRail
            Divider()
            ScrollView {
                stepContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(22)
            }
            Divider()
            footer
        }
        .frame(width: 700, height: 570)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("browser.import.accessibility", fallback: "Import browser data"))
        .onAppear { viewModel.start() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color(nsColor: CocxyColors.blue))
                .frame(width: 34, height: 34)
                .background(
                    Color(nsColor: CocxyColors.blue).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.localizedTitle(using: localizer))
                    .font(.system(size: 16, weight: .semibold))
                Text(localized("browser.import.subtitle", fallback: "Browser data import"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isDiscovering {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(localized("browser.import.scanning", fallback: "Scanning browsers"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var stepRail: some View {
        HStack(spacing: 0) {
            ForEach(BrowserImportViewModel.Step.allCases) { step in
                HStack(spacing: 7) {
                    Image(systemName: stepSymbol(step))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(stepColor(step))
                        .frame(width: 20, height: 20)
                    Text(Self.localizedStepTitle(step, using: localizer))
                        .font(.system(size: 11, weight: step == viewModel.step ? .semibold : .regular))
                        .foregroundStyle(step == viewModel.step ? .primary : .secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(step == viewModel.step ? .isSelected : [])

                if step != .review {
                    Rectangle()
                        .fill(
                            step.rawValue < viewModel.step.rawValue
                                ? Color(nsColor: CocxyColors.green).opacity(0.7)
                                : Color.secondary.opacity(0.2)
                        )
                        .frame(height: 1)
                        .padding(.horizontal, 10)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .source:
            sourceStep
        case .data:
            dataStep
        case .filters:
            filtersStep
        case .review:
            reviewStep
        }
    }

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading(
                title: localized("browser.import.source.title", fallback: "Source"),
                detail: String(
                    format: localized("browser.import.source.detected", fallback: "%d browsers detected"),
                    viewModel.detectedSourceCount
                )
            )

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel(localized("browser.import.source.browser", fallback: "Browser"))
                    Picker("", selection: $viewModel.selectedSource) {
                        ForEach(viewModel.discoveries) { discovery in
                            Label(
                                discovery.source.displayName,
                                systemImage: sourceSymbol(discovery.source)
                            )
                            .tag(discovery.source)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel(localized("browser.import.source.browser", fallback: "Browser"))
                    .frame(maxWidth: .infinity)
                }

                Button { viewModel.refreshDiscovery() } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isDiscovering)
                .help(localized("browser.import.source.rescan", fallback: "Scan again"))
                .accessibilityLabel(localized("browser.import.source.rescan", fallback: "Scan again"))
            }

            if let discovery = viewModel.selectedDiscovery, !discovery.profiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel(localized("browser.import.source.profile", fallback: "Source profile"))
                    Picker("", selection: $viewModel.selectedSourceProfileID) {
                        ForEach(discovery.profiles) { profile in
                            Text(sourceProfileLabel(profile)).tag(Optional(profile.id))
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel(localized("browser.import.source.profile", fallback: "Source profile"))
                    .frame(maxWidth: .infinity)
                }

                if let profile = viewModel.selectedSourceProfile {
                    HStack(spacing: 16) {
                        availabilityStatus(.history, profile: profile)
                        availabilityStatus(.cookies, profile: profile)
                        availabilityStatus(.bookmarks, profile: profile)
                    }

                    Text(profile.location.historyPath.deletingLastPathComponent().path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(profile.location.historyPath.deletingLastPathComponent().path)
                }
            } else if !viewModel.isDiscovering {
                statusBanner(
                    symbol: "exclamationmark.magnifyingglass",
                    title: localized("browser.import.source.notFound", fallback: "No readable profile found"),
                    detail: localized(
                        "browser.import.source.notFound.detail",
                        fallback: "Open the browser once, then scan again. macOS privacy settings may also restrict access."
                    ),
                    tint: Color(nsColor: CocxyColors.yellow)
                )
            }
        }
    }

    private var dataStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading(
                title: localized("browser.import.data.title", fallback: "Data and destination"),
                detail: viewModel.selectedSourceProfile?.location.profileName ?? viewModel.selectedSource.displayName
            )

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel(localized("browser.import.destination", fallback: "Cocxy profile"))
                Picker("", selection: $viewModel.selectedDestinationProfileID) {
                    ForEach(viewModel.destinationProfiles, id: \.id) { profile in
                        Label(
                            profile.isRemoteBacked
                                ? String(
                                    format: localized("browser.import.destination.remote", fallback: "%@ (Remote)"),
                                    profile.name
                                )
                                : profile.name,
                            systemImage: profile.isRemoteBacked ? "network.slash" : profile.icon
                        )
                        .tag(Optional(profile.id))
                        .disabled(profile.isRemoteBacked)
                    }
                }
                .labelsHidden()
                .accessibilityLabel(localized("browser.import.destination", fallback: "Cocxy profile"))
                .frame(maxWidth: .infinity)
            }

            if viewModel.destinationProfiles.allSatisfy(\.isRemoteBacked) {
                statusBanner(
                    symbol: "externaldrive.badge.exclamationmark",
                    title: localized("browser.import.destination.none", fallback: "No local Cocxy profile"),
                    detail: localized(
                        "browser.import.destination.none.detail",
                        fallback: "Browser data can only be imported into a local WebKit profile."
                    ),
                    tint: Color(nsColor: CocxyColors.red)
                )
            }

            VStack(spacing: 0) {
                dataToggle(
                    kind: .history,
                    title: localized("browser.import.data.history", fallback: "History"),
                    detail: localized("browser.import.data.history.detail", fallback: "Saved for the selected Cocxy profile"),
                    symbol: "clock.arrow.circlepath",
                    tint: Color(nsColor: CocxyColors.blue),
                    selection: $viewModel.importHistory
                )
                Divider()
                dataToggle(
                    kind: .cookies,
                    title: localized("browser.import.data.cookies", fallback: "Cookies"),
                    detail: localized("browser.import.data.cookies.detail", fallback: "Keychain access may be requested during import"),
                    symbol: "key.horizontal",
                    tint: Color(nsColor: CocxyColors.peach),
                    selection: $viewModel.importCookies
                )
                Divider()
                dataToggle(
                    kind: .bookmarks,
                    title: localized("browser.import.data.bookmarks", fallback: "Bookmarks"),
                    detail: localized("browser.import.data.bookmarks.detail", fallback: "Added under a source folder in Cocxy Bookmarks"),
                    symbol: "bookmark.fill",
                    tint: Color(nsColor: CocxyColors.green),
                    selection: $viewModel.importBookmarks
                )
            }
            .background(Color(nsColor: CocxyColors.surface0).opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: CocxyColors.surface1).opacity(0.55), lineWidth: 1)
            )
        }
    }

    private var filtersStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading(
                title: localized("browser.import.filters.title", fallback: "Filters"),
                detail: localized("browser.import.filters.optional", fallback: "Optional")
            )

            if viewModel.importHistory {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel(localized("browser.import.filters.historyRange", fallback: "History range"))
                    Picker("", selection: $viewModel.historyRange) {
                        ForEach(BrowserImportViewModel.HistoryRange.allCases) { range in
                            Text(Self.localizedHistoryRange(range, using: localizer)).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel(
                        localized("browser.import.filters.historyRange", fallback: "History range")
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel(localized("browser.import.filters.allow", fallback: "Only these domains"))
                TextField(
                    localized(
                        "browser.import.filters.allowPlaceholder",
                        fallback: "example.com, docs.example.com"
                    ),
                    text: $viewModel.domainAllowList
                )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(localized("browser.import.filters.allow", fallback: "Only these domains"))

                fieldLabel(localized("browser.import.filters.block", fallback: "Exclude these domains"))
                TextField(
                    localized(
                        "browser.import.filters.blockPlaceholder",
                        fallback: "internal.example.com"
                    ),
                    text: $viewModel.domainBlockList
                )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(localized("browser.import.filters.block", fallback: "Exclude these domains"))
            }

            if !viewModel.invalidDomainRules.isEmpty {
                statusBanner(
                    symbol: "exclamationmark.triangle.fill",
                    title: localized("browser.import.filters.invalid", fallback: "Invalid domain"),
                    detail: viewModel.invalidDomainRules.joined(separator: ", "),
                    tint: Color(nsColor: CocxyColors.red)
                )
            } else if !viewModel.conflictingDomainRules.isEmpty {
                statusBanner(
                    symbol: "arrow.left.arrow.right",
                    title: localized("browser.import.filters.conflict", fallback: "Domain appears in both lists"),
                    detail: viewModel.conflictingDomainRules.joined(separator: ", "),
                    tint: Color(nsColor: CocxyColors.yellow)
                )
            }
        }
    }

    @ViewBuilder
    private var reviewStep: some View {
        if viewModel.isImporting {
            centeredProgress(
                title: localized("browser.import.running", fallback: "Importing browser data..."),
                detail: localized("browser.import.running.detail", fallback: "Keep this window open until the import finishes.")
            )
        } else if let result = viewModel.result {
            resultView(result)
        } else if viewModel.isPreviewing {
            centeredProgress(
                title: localized("browser.import.preview.loading", fallback: "Reading the selected profile..."),
                detail: localized("browser.import.preview.loading.detail", fallback: "Cookie values are not read during preview.")
            )
        } else if let preview = viewModel.preview {
            previewView(preview)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                failureBanner
                Button { viewModel.retryPreview() } label: {
                    Label(localized("common.retry", fallback: "Retry"), systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func previewView(_ preview: BrowserImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading(
                title: localized("browser.import.review.title", fallback: "Review import"),
                detail: reviewRoute
            )
            countGrid(
                history: preview.history.count,
                cookies: preview.cookies.count,
                bookmarks: preview.bookmarks.count
            )
            reviewScope

            if preview.itemCount == 0 {
                statusBanner(
                    symbol: "tray",
                    title: localized("browser.import.preview.empty", fallback: "No importable data"),
                    detail: localized(
                        "browser.import.preview.empty.detail",
                        fallback: "Change the selected data or source profile and try again."
                    ),
                    tint: Color(nsColor: CocxyColors.yellow)
                )
            }

            if preview.skippedCount > 0 || !preview.errors.isEmpty {
                issueList(
                    skippedCount: preview.skippedCount,
                    issues: preview.errors,
                    title: localized("browser.import.review.issues", fallback: "Import notes")
                )
            }

            failureBanner
        }
    }

    private func resultView(_ result: BrowserImportResult) -> some View {
        let presentation = resultPresentation(result.status)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: presentation.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(presentation.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(reviewRoute)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            countGrid(
                history: result.importedHistoryCount,
                cookies: result.importedCookieCount,
                bookmarks: result.importedBookmarkCount
            )

            if result.skippedCount > 0 || !result.errors.isEmpty {
                issueList(
                    skippedCount: result.skippedCount,
                    issues: result.errors,
                    title: localized("browser.import.result.issues", fallback: "Result details")
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if viewModel.result == nil {
                Button(localized("common.cancel", fallback: "Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(viewModel.isImporting)
            }

            Spacer()

            if viewModel.result != nil {
                Button(localized("common.done", fallback: "Done"), action: onDone)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button { viewModel.goBack() } label: {
                    Label(localized("common.back", fallback: "Back"), systemImage: "chevron.left")
                }
                .disabled(!viewModel.canGoBack)

                Button { viewModel.advance() } label: {
                    Label(primaryButtonTitle, systemImage: primaryButtonSymbol)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canAdvance)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func dataToggle(
        kind: BrowserImportDataKind,
        title: String,
        detail: String,
        symbol: String,
        tint: Color,
        selection: Binding<Bool>
    ) -> some View {
        let isAvailable = viewModel.isDataAvailable(kind)
        return Toggle(isOn: selection) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isAvailable ? tint : Color.secondary)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                    Text(
                        isAvailable
                            ? detail
                            : localized("browser.import.data.unavailable", fallback: "Unavailable for this source or destination")
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
            }
        }
        .toggleStyle(.switch)
        .disabled(!isAvailable)
        .padding(.horizontal, 12)
        .frame(minHeight: 62)
    }

    private func countGrid(history: Int, cookies: Int, bookmarks: Int) -> some View {
        HStack(spacing: 10) {
            countTile(
                value: history,
                title: localized("browser.import.data.history", fallback: "History"),
                symbol: "clock.arrow.circlepath",
                tint: Color(nsColor: CocxyColors.blue)
            )
            countTile(
                value: cookies,
                title: localized("browser.import.data.cookies", fallback: "Cookies"),
                symbol: "key.horizontal",
                tint: Color(nsColor: CocxyColors.peach)
            )
            countTile(
                value: bookmarks,
                title: localized("browser.import.data.bookmarks", fallback: "Bookmarks"),
                symbol: "bookmark.fill",
                tint: Color(nsColor: CocxyColors.green)
            )
        }
    }

    private func countTile(value: Int, title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.formatted())
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(Color(nsColor: CocxyColors.surface0).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func issueList(
        skippedCount: Int,
        issues: [BrowserImportIssue],
        title: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if skippedCount > 0 {
                    Text(
                        String(
                            format: localized("browser.import.skipped", fallback: "%d skipped"),
                            skippedCount
                        )
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(nsColor: CocxyColors.yellow))
                }
            }
            ForEach(Array(issues.prefix(8).enumerated()), id: \.offset) { _, issue in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(nsColor: CocxyColors.yellow))
                        .padding(.top, 2)
                    Text(issue.message)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if issues.count > 8 {
                Text(
                    String(
                        format: localized("browser.import.issues.more", fallback: "%d more notes"),
                        issues.count - 8
                    )
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: CocxyColors.surface0).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private var failureBanner: some View {
        if let failure = viewModel.failure {
            statusBanner(
                symbol: "xmark.octagon.fill",
                title: localized("browser.import.error.title", fallback: "Import could not continue"),
                detail: failureMessage(failure),
                tint: Color(nsColor: CocxyColors.red)
            )
        }
    }

    private func centeredProgress(title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Spacer(minLength: 70)
            ProgressView()
                .controlSize(.regular)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 70)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeading(title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func availabilityStatus(
        _ kind: BrowserImportDataKind,
        profile: BrowserImportSourceProfile
    ) -> some View {
        let available = profile.availableData.contains(kind)
        return HStack(spacing: 5) {
            Image(systemName: available ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(
                    available
                        ? Color(nsColor: CocxyColors.green)
                        : Color.secondary
                )
            Text(localizedDataKind(kind))
                .foregroundStyle(available ? Color.primary : Color.secondary)
        }
        .font(.system(size: 10, weight: .medium))
        .accessibilityValue(
            available
                ? localized("browser.import.available", fallback: "Available")
                : localized("browser.import.unavailable", fallback: "Unavailable")
        )
    }

    private func statusBanner(symbol: String, title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(tint.opacity(0.24), lineWidth: 1))
    }

    private var reviewRoute: String {
        let source = viewModel.selectedSourceProfile?.location.profileName
            ?? viewModel.selectedSource.displayName
        let destination = viewModel.selectedDestinationProfile?.name
            ?? localized("browser.import.destination.unavailable", fallback: "Unavailable destination")
        return String(
            format: localized("browser.import.review.route", fallback: "%@ to %@"),
            source,
            destination
        )
    }

    private var reviewScope: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(
                viewModel.importHistory
                    ? Self.localizedHistoryRange(viewModel.historyRange, using: localizer)
                    : localized("browser.import.review.historyExcluded", fallback: "History not selected"),
                systemImage: "calendar"
            )
            if viewModel.domainAllowList.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(
                    localized("browser.import.review.allDomains", fallback: "All domains except exclusions"),
                    systemImage: "globe"
                )
            } else {
                Label(
                    String(
                        format: localized("browser.import.review.allowedDomains", fallback: "Allowed: %@"),
                        viewModel.domainAllowList
                    ),
                    systemImage: "checkmark.shield"
                )
            }
            if !viewModel.domainBlockList.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(
                    String(
                        format: localized("browser.import.review.blockedDomains", fallback: "Excluded: %@"),
                        viewModel.domainBlockList
                    ),
                    systemImage: "nosign"
                )
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }

    private var primaryButtonTitle: String {
        switch viewModel.step {
        case .source, .data:
            return localized("common.next", fallback: "Next")
        case .filters:
            return localized("browser.import.review.action", fallback: "Review")
        case .review:
            return viewModel.isImporting
                ? localized("browser.import.running.short", fallback: "Importing...")
                : localized("browser.import.action", fallback: "Import")
        }
    }

    private var primaryButtonSymbol: String {
        switch viewModel.step {
        case .source, .data: return "chevron.right"
        case .filters: return "doc.text.magnifyingglass"
        case .review: return "tray.and.arrow.down"
        }
    }

    private func stepSymbol(_ step: BrowserImportViewModel.Step) -> String {
        if step.rawValue < viewModel.step.rawValue { return "checkmark.circle.fill" }
        return step == viewModel.step ? "circle.inset.filled" : "circle"
    }

    private func stepColor(_ step: BrowserImportViewModel.Step) -> Color {
        if step.rawValue < viewModel.step.rawValue { return Color(nsColor: CocxyColors.green) }
        return step == viewModel.step ? Color(nsColor: CocxyColors.blue) : .secondary
    }

    private func sourceSymbol(_ source: BrowserImportSource) -> String {
        if source.isChromiumBased { return "globe" }
        switch source {
        case .firefox, .firefoxDeveloperEdition, .firefoxNightly,
             .librewolf, .waterfox, .floorp, .zen:
            return "flame"
        case .safari:
            return "safari"
        case .orion:
            return "sparkle.magnifyingglass"
        default:
            return "globe"
        }
    }

    private func sourceProfileLabel(_ profile: BrowserImportSourceProfile) -> String {
        let location = profile.location
        guard location.profileName.caseInsensitiveCompare(location.profileIdentifier) != .orderedSame else {
            return location.profileName
        }
        return "\(location.profileName) - \(location.profileIdentifier)"
    }

    private func localizedDataKind(_ kind: BrowserImportDataKind) -> String {
        switch kind {
        case .history: return localized("browser.import.data.history", fallback: "History")
        case .cookies: return localized("browser.import.data.cookies", fallback: "Cookies")
        case .bookmarks: return localized("browser.import.data.bookmarks", fallback: "Bookmarks")
        }
    }

    private func failureMessage(_ failure: BrowserImportWizardFailure) -> String {
        switch failure {
        case .destinationUnavailable:
            return localized(
                "browser.import.error.destinationUnavailable",
                fallback: "The selected Cocxy profile no longer exists."
            )
        case .remoteDestination:
            return localized(
                "browser.import.error.remoteDestination",
                fallback: "Browser data can only be imported into a local WebKit profile."
            )
        case .destinationBusy:
            return localized(
                "browser.import.error.destinationBusy",
                fallback: "Another browser import is already using this Cocxy profile."
            )
        case .sourceChanged:
            return localized(
                "browser.import.error.sourceChanged",
                fallback: "The source data changed after review. Refresh the preview before importing."
            )
        case .operation(let detail):
            return detail
        }
    }

    private func resultPresentation(
        _ status: BrowserImportStatus
    ) -> (symbol: String, tint: Color, title: String) {
        switch status {
        case .completed:
            return (
                "checkmark.circle.fill",
                Color(nsColor: CocxyColors.green),
                localized("browser.import.result.completed", fallback: "Import completed")
            )
        case .partial:
            return (
                "exclamationmark.circle.fill",
                Color(nsColor: CocxyColors.yellow),
                localized("browser.import.result.partial", fallback: "Import completed with notes")
            )
        case .failed:
            return (
                "xmark.octagon.fill",
                Color(nsColor: CocxyColors.red),
                localized("browser.import.result.failed", fallback: "Import failed")
            )
        }
    }

    static func localizedTitle(using localizer: AppLocalizer) -> String {
        localizer.string("browser.import.title", fallback: "Import Browser Data")
    }

    static func localizedStepTitle(
        _ step: BrowserImportViewModel.Step,
        using localizer: AppLocalizer
    ) -> String {
        switch step {
        case .source: return localizer.string("browser.import.step.source", fallback: "Source")
        case .data: return localizer.string("browser.import.step.data", fallback: "Data")
        case .filters: return localizer.string("browser.import.step.filters", fallback: "Filters")
        case .review: return localizer.string("browser.import.step.review", fallback: "Review")
        }
    }

    static func localizedHistoryRange(
        _ range: BrowserImportViewModel.HistoryRange,
        using localizer: AppLocalizer
    ) -> String {
        switch range {
        case .allTime:
            return localizer.string("browser.import.historyRange.all", fallback: "All time")
        case .thirtyDays:
            return localizer.string("browser.import.historyRange.30", fallback: "30 days")
        case .ninetyDays:
            return localizer.string("browser.import.historyRange.90", fallback: "90 days")
        case .oneYear:
            return localizer.string("browser.import.historyRange.365", fallback: "1 year")
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
