//
//  UpdatePreferences.swift
//  Puck
//
//  The three things the update check has to remember between launches.
//
//  Its own rather than SettingsStore's, which is where they started. The
//  settings window shows this section, so Settings has to know about Updates
//  -- and a checker that read its preferences out of SettingsStore made
//  Updates know about Settings right back. One of the two directions had to
//  go, and the one worth keeping is the window knowing what it displays.
//

import Foundation

struct UpdatePreferences {
    private enum Keys {
        static let checksForUpdates = "Puck.checksForUpdates"
        static let lastCheckedAt = "Puck.lastUpdateCheckAt"
        static let skippedVersion = "Puck.skippedUpdateVersion"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether to ask GitHub, once a day, if there is a newer Puck.
    ///
    /// On by default: the app is dragged out of a .dmg and has no other way
    /// of telling anyone it is out of date. Switchable because it is the one
    /// request this app makes that the user did not ask for -- everything
    /// else on the network is a song being looked up or a model being talked
    /// to, and both of those are something they just did.
    var checksForUpdates: Bool {
        get { defaults.object(forKey: Keys.checksForUpdates) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Keys.checksForUpdates) }
    }

    /// When the last check ran, so the next one is a day later rather than a
    /// launch later.
    var lastCheckedAt: Date? {
        get { defaults.object(forKey: Keys.lastCheckedAt) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Keys.lastCheckedAt) }
    }

    /// A version the user turned down. Text rather than an `AppVersion` so a
    /// defaults file written by a later build cannot fail to read.
    var skippedVersion: String? {
        get { defaults.string(forKey: Keys.skippedVersion) }
        nonmutating set { defaults.set(newValue, forKey: Keys.skippedVersion) }
    }
}
