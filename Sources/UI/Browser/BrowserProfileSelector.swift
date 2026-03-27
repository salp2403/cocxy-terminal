// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserProfileSelector.swift - Compact profile switcher for the browser toolbar.

import SwiftUI

// MARK: - Browser Profile Selector

/// A compact dropdown for switching between browser profiles.
///
/// ## Layout
///
/// ```
/// +--------------------+
/// | [icon] Default  v  |  <- Shows active profile name
/// +--------------------+  (on click, shows dropdown)
/// | > [icon] Default   |
/// |   [icon] Work      |
/// |   [icon] Dev       |
/// | -----------------  |
/// | + New Profile      |
/// | > Manage...        |
/// +--------------------+
/// ```
///
/// ## Features
///
/// - Displays the active profile's icon and name.
/// - Dropdown lists all profiles with a checkmark on the active one.
/// - "New Profile" triggers profile creation flow.
/// - "Manage Profiles" opens the profile management view.
///
/// - SeeAlso: ``BrowserProfileManager`` for CRUD operations.
/// - SeeAlso: ``BrowserProfile`` for the profile model.
struct BrowserProfileSelector: View {

    /// The profile manager driving the selector state.
    @ObservedObject var profileManager: BrowserProfileManager

    /// Called when the user selects "New Profile".
    let onCreateProfile: () -> Void

    /// Called when the user selects "Manage Profiles".
    let onManageProfiles: () -> Void

    // MARK: - Body

    var body: some View {
        Menu {
            profileList
            Divider()
            managementActions
        } label: {
            activeProfileLabel
        }
        .menuStyle(.borderlessButton)
        .frame(height: 24)
        .accessibilityLabel("Profile: \(profileManager.activeProfile.name)")
        .accessibilityHint("Opens profile switcher")
    }

    // MARK: - Active Profile Label

    private var activeProfileLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: profileManager.activeProfile.icon)
                .font(.system(size: 10))
                .foregroundColor(profileColor(profileManager.activeProfile))

            Text(profileManager.activeProfile.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.text))
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: CocxyColors.surface0))
        )
    }

    // MARK: - Profile List

    private var profileList: some View {
        ForEach(profileManager.profiles, id: \.id) { profile in
            Button(action: { profileManager.switchProfile(to: profile.id) }) {
                HStack(spacing: 6) {
                    if profile.id == profileManager.activeProfileID {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                    }

                    Image(systemName: profile.icon)
                        .font(.system(size: 11))

                    Text(profile.name)
                        .font(.system(size: 12))

                    if profile.isDefault {
                        Text("(Default)")
                            .font(.system(size: 10))
                            .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                    }
                }
            }
            .accessibilityLabel("Switch to \(profile.name) profile")
        }
    }

    // MARK: - Management Actions

    private var managementActions: some View {
        Group {
            Button(action: onCreateProfile) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                    Text("New Profile")
                        .font(.system(size: 12))
                }
            }
            .accessibilityLabel("Create new profile")

            Button(action: onManageProfiles) {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10))
                    Text("Manage Profiles")
                        .font(.system(size: 12))
                }
            }
            .accessibilityLabel("Open profile management")
        }
    }

    // MARK: - Helpers

    /// Converts a profile's hex color to a SwiftUI color.
    ///
    /// Falls back to the default text color if the hex cannot be parsed.
    private func profileColor(_ profile: BrowserProfile) -> Color {
        Color(nsColor: colorFromHex(profile.colorHex))
    }

    /// Parses a hex color string into an NSColor.
    ///
    /// Supports 6-digit hex with or without leading "#".
    /// Returns ``CocxyColors/text`` as a fallback for invalid input.
    private func colorFromHex(_ hex: String) -> NSColor {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard cleaned.count == 6,
              let hexValue = UInt64(cleaned, radix: 16) else {
            return CocxyColors.text
        }

        let red   = CGFloat((hexValue >> 16) & 0xFF) / 255.0
        let green = CGFloat((hexValue >> 8) & 0xFF) / 255.0
        let blue  = CGFloat(hexValue & 0xFF) / 255.0

        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1.0)
    }
}
