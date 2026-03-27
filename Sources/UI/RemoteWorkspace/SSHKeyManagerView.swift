// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHKeyManagerView.swift - SSH key listing and generation panel.

import SwiftUI

// MARK: - SSH Key Manager View Model

/// Drives the SSH key management sub-panel.
///
/// Loads SSH keys from `~/.ssh/` via `SSHKeyManager` and exposes them
/// for display. Supports key generation and adding keys to the agent.
@MainActor
final class SSHKeyManagerViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var keys: [SSHKeyInfo] = []
    @Published var isGenerateSheetPresented = false
    @Published var newKeyName: String = ""
    @Published var newKeyType: SSHKeyType = .ed25519
    @Published var newKeyPassphrase: String = ""
    @Published private(set) var errorMessage: String?

    // MARK: - Dependencies

    private let keyManager: SSHKeyManager

    // MARK: - Initialization

    init(keyManager: SSHKeyManager) {
        self.keyManager = keyManager
    }

    // MARK: - Actions

    func loadKeys() {
        do {
            keys = try keyManager.listKeys()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generateKey() {
        let trimmedName = newKeyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Key name is required."
            return
        }

        do {
            try keyManager.generateKey(
                type: newKeyType,
                name: trimmedName,
                passphrase: newKeyPassphrase
            )
            isGenerateSheetPresented = false
            resetGenerateForm()
            loadKeys()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addToAgent(keyPath: String) {
        do {
            try keyManager.addToAgent(keyPath: keyPath)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Private

    private func resetGenerateForm() {
        newKeyName = ""
        newKeyType = .ed25519
        newKeyPassphrase = ""
    }
}

// MARK: - SSH Key Manager View

/// Sub-panel displaying SSH keys found in `~/.ssh/` with generation support.
///
/// ## Layout
///
/// ```
/// +-- SSH Keys ----------------------[Generate]--+
/// |                                              |
/// | [key] id_ed25519     ED25519  SHA256:abc...  |
/// | [key] id_rsa         RSA     SHA256:def...   |
/// | [key] work_key       ED25519  SHA256:ghi...  |
/// +----------------------------------------------+
/// ```
///
/// - SeeAlso: `SSHKeyManagerViewModel`
/// - SeeAlso: `SSHKeyManager`
struct SSHKeyManagerView: View {

    @ObservedObject var viewModel: SSHKeyManagerViewModel

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            Divider()
            keyListContent
        }
        .onAppear { viewModel.loadKeys() }
        .sheet(isPresented: $viewModel.isGenerateSheetPresented) {
            generateKeySheet
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack {
            Text("SSH Keys")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))

            Spacer()

            Button(action: { viewModel.isGenerateSheetPresented = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 10))
                    Text("Generate")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(Color(nsColor: CocxyColors.blue))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Generate new SSH key")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Key List

    private var keyListContent: some View {
        Group {
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            if viewModel.keys.isEmpty {
                emptyStateView
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.keys) { key in
                            SSHKeyRow(key: key, onAddToAgent: {
                                viewModel.addToAgent(keyPath: key.id)
                            })
                            Divider()
                                .padding(.leading, 40)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "key")
                .font(.system(size: 28))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text("No SSH keys found")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text("Generate a new key or add existing\nkeys to ~/.ssh/ to see them here.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.yellow))

            Text(message)
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.text))
                .lineLimit(2)

            Spacer()

            Button(action: { viewModel.dismissError() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color(nsColor: CocxyColors.yellow).opacity(0.1))
        .cornerRadius(6)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Generate Key Sheet

    private var generateKeySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Generate SSH Key")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))

            VStack(alignment: .leading, spacing: 10) {
                formField(label: "Name") {
                    TextField("my-key", text: $viewModel.newKeyName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                formField(label: "Type") {
                    Picker("", selection: $viewModel.newKeyType) {
                        Text("Ed25519").tag(SSHKeyType.ed25519)
                        Text("RSA").tag(SSHKeyType.rsa)
                        Text("ECDSA").tag(SSHKeyType.ecdsa)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                formField(label: "Passphrase") {
                    SecureField("Optional", text: $viewModel.newKeyPassphrase)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    viewModel.isGenerateSheetPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))

                Button("Generate") {
                    viewModel.generateKey()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(nsColor: CocxyColors.blue))
                .disabled(viewModel.newKeyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(Color(nsColor: CocxyColors.mantle))
    }

    // MARK: - Form Field Helper

    private func formField<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            content()
        }
    }
}

// MARK: - SSH Key Row

/// A single row displaying one SSH key with its type and fingerprint.
struct SSHKeyRow: View {

    let key: SSHKeyInfo
    let onAddToAgent: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 12))
                .foregroundColor(keyTypeColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(key.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(nsColor: CocxyColors.text))
                        .lineLimit(1)

                    keyTypeBadge
                }

                Text(key.fingerprint)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: onAddToAgent) {
                Image(systemName: "person.badge.key")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            }
            .buttonStyle(.plain)
            .help("Add to SSH agent")
            .accessibilityLabel("Add \(key.name) to SSH agent")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(key.name), \(key.type.rawValue), \(key.fingerprint)")
    }

    // MARK: - Key Type Badge

    private var keyTypeBadge: some View {
        Text(key.type.rawValue.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(keyTypeColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(keyTypeColor.opacity(0.15))
            .cornerRadius(3)
    }

    private var keyTypeColor: Color {
        switch key.type {
        case .ed25519:
            return Color(nsColor: CocxyColors.green)
        case .rsa:
            return Color(nsColor: CocxyColors.blue)
        case .ecdsa:
            return Color(nsColor: CocxyColors.mauve)
        case .dsa:
            return Color(nsColor: CocxyColors.yellow)
        case .unknown:
            return Color(nsColor: CocxyColors.overlay1)
        }
    }
}
