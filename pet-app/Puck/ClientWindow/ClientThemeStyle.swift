//
//  ClientThemeStyle.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Which of the ClientWindow themes is active. Design system v2
//  (2026-08-14) dropped the `.glass` theme --
//  the rationale. A distinct setting from Puck's system-wide AppAppearance
//  (Settings' light/dark/system toggle, used by the pet overlay/Settings),
//  but not a separate ClientWindow-local one either -- theme should stay in
//  sync with the menu bar settings, the same way Shady-style apps let you
//  flip theme from the menu bar. Persisted in Puck's own UserDefaults domain (SettingsStore)
//  and broadcast to PuckClient over DistributedNotificationCenter, the same
//  shape AppAppearance's old cross-process wiring used -- PuckClient's
//  AppDelegate is the only consumer, seeding ClientWindowStore.themeStyle
//  from it.
//

import SwiftUI

enum ClientThemeStyle: String, CaseIterable, Identifiable {
    /// Editor themes, so the conversation and the code come from one set of
    /// choices instead of each being tuned against the other.
    ///
    /// `dark` keeps its raw value and is now the neutral one: it is what
    /// everyone already has persisted, and the Vercel palette it used to mean
    /// is beside it under its own name.
    case light, dark, vercelDark, tokyoNight

    var id: String { rawValue }

    /// Shown in Settings' theme picker.
    var displayName: String {
        switch self {
        // The two plain ones stay translated; a named theme is a proper
        // noun and reads worse translated than left alone.
        case .light: return Strings.text(.themeLight)
        case .dark: return Strings.text(.themeDark)
        case .vercelDark: return "Vercel Dark"
        case .tokyoNight: return "Tokyo Night"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark, .vercelDark, .tokyoNight: return .dark
        }
    }

    var palette: ClientPalette {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .vercelDark: return .vercelDark
        case .tokyoNight: return .tokyoNight
        }
    }

    /// Puck's own UserDefaults domain now (SettingsStore), not
    /// PuckClient's -- see this type's header comment.
    static let defaultsKey = "Puck.clientThemeStyle"

    /// Same resolve-with-fallback shape as AppAppearance.resolved(fromDefaultsValue:)
    /// -- `.dark` (not `.light`) is the fallback since that's this app's
    /// original, already-shipped look.
    static func resolved(fromDefaultsValue raw: String?) -> ClientThemeStyle {
        raw.flatMap(ClientThemeStyle.init(rawValue:)) ?? .dark
    }

    /// Posted by Puck's AppDelegate whenever `SettingsStore.clientThemeStyle`
    /// changes, so PuckClient (a separate process with no access to
    /// Puck's UserDefaults domain) picks up the same value immediately
    /// instead of only at its own next launch.
    static let crossProcessChangeNotification = Notification.Name("com.speaki-e.Puck.clientThemeStyleChanged")

    /// The key `crossProcessUserInfo` carries this value under, and
    /// `resolved(fromCrossProcessUserInfo:)` reads it back from.
    private static let crossProcessUserInfoKey = "clientThemeStyle"

    /// Carries the actual new value alongside `crossProcessChangeNotification`
    /// -- `UserDefaults.set()` isn't guaranteed to be visible to a second
    /// process by the time a Darwin/distributed notification posted right
    /// afterward is delivered and handled (a real race AppAppearance's own
    /// wiring hit first), so the value travels with the notification itself
    /// rather than PuckClient re-reading UserDefaults on receipt.
    var crossProcessUserInfo: [AnyHashable: Any] {
        [Self.crossProcessUserInfoKey: rawValue]
    }

    /// Announces the change to every process, including the one calling.
    /// Both windows offer the picker now, so both post through here rather
    /// than each writing the notification out again slightly differently.
    func broadcast() {
        DistributedNotificationCenter.default().postNotificationName(
            Self.crossProcessChangeNotification,
            object: nil,
            userInfo: crossProcessUserInfo,
            deliverImmediately: true
        )
    }

    /// The defaults domain the setting lives in -- Puck's, whichever process
    /// is asking. Same reasoning as `AppLanguage.sharedDefaults`: one setting
    /// with two stores is two settings that disagree.
    static var sharedDefaults: UserDefaults? { SharedDefaults.puck }

    /// nil if `userInfo` carries no recognizable value at all (missing key,
    /// or the notification came with none) -- distinguishing "nothing here"
    /// from a real value lets the caller fall back to its own UserDefaults
    /// read instead of silently treating a malformed notification as unset.
    static func resolved(fromCrossProcessUserInfo userInfo: [AnyHashable: Any]?) -> ClientThemeStyle? {
        guard let raw = userInfo?[crossProcessUserInfoKey] as? String else { return nil }
        return resolved(fromDefaultsValue: raw)
    }
}
