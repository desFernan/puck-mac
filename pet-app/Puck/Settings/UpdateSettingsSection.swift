//
//  UpdateSettingsSection.swift
//  Puck
//
//  Where being out of date is something you can look up rather than
//  something you have to catch.
//
//  The pet says it once when it finds out, and a line said once is a line
//  missed by anyone who was away from their desk. This is where it stays: the
//  version this is, whether there is a newer one, and the link.
//

import AppKit
import SwiftUI

struct UpdateSettingsSection: View {
    @ObservedObject var updates: UpdateChecker
    @ObservedObject private var localization = Localization.shared
    let preferences: UpdatePreferences

    @State private var checksForUpdates: Bool
    /// Set once a check has run from this window, so "up to date" is
    /// something the window was told rather than something it assumes.
    @State private var hasChecked = false

    init(updates: UpdateChecker, preferences: UpdatePreferences = UpdatePreferences()) {
        self.updates = updates
        self.preferences = preferences
        _checksForUpdates = State(initialValue: preferences.checksForUpdates)
    }

    var body: some View {
        SettingsSection(title: text(.updateSectionHeader)) {
            SettingsRow(label: text(.updateChecksLabel)) {
                Toggle("", isOn: $checksForUpdates)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: checksForUpdates) { _, newValue in preferences.checksForUpdates = newValue }
            }
            if let release = updates.available {
                SettingsRow(label: String(format: text(.updateAvailableFormat), release.version.description)) {
                    HStack(spacing: ClientTheme.Metrics.spacingSmall) {
                        Button(text(.updateSkip)) { updates.skip(release) }
                        Button(text(.updateGet)) { NSWorkspace.shared.open(release.url) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                SettingsRow(label: currentVersionLine) {
                    // Deliberately available whatever the toggle says: turning
                    // the daily check off is declining to be interrupted, not
                    // declining to ever know.
                    Button(updates.isChecking ? text(.updateChecking) : text(.updateCheckNow)) {
                        Task {
                            // Not honouring the skip: pressing this is asking,
                            // and the answer to a question somebody asked is
                            // not "I decided not to tell you".
                            await updates.check(honouringSkip: false)
                            hasChecked = true
                        }
                    }
                    .disabled(updates.isChecking)
                }
            }
        }
    }

    private var currentVersionLine: String {
        let current = AppVersion.current()?.description ?? "?"
        return hasChecked
            ? String(format: text(.updateUpToDateFormat), current)
            : String(format: text(.updateCurrentFormat), current)
    }

    private func text(_ key: L10nKey) -> String {
        Strings.text(key, language: localization.language)
    }
}
