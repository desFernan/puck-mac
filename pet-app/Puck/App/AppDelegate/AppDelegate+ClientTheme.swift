//
//  AppDelegate+ClientTheme.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Persists the client (chat) window's theme and broadcasts it to
//  PuckClient over DistributedNotificationCenter.
//

import Foundation

extension AppDelegate {
    // MARK: - Client (chat) window theme, broadcast to PuckClient

    /// The theme should stay in sync with the menu bar settings, the same
    /// way Shady-style apps let you flip theme from the menu bar rather than
    /// digging into a window -- so ClientThemeStyle (the
    /// client window's own light/dark theme, separate from the
    /// system-wide appearance above) is a Settings item here, but only
    /// PuckClient's client window actually renders with it -- this process
    /// never applies it locally, just persists it (via SettingsStore) and
    /// broadcasts it, same DistributedNotificationCenter shape as
    /// onAppearanceChanged above.
    func setUpClientThemeStyle() {
        broadcastClientThemeStyle(settingsStore.clientThemeStyle)
        settingsStore.onClientThemeStyleChanged = { [weak self] style in
            self?.broadcastClientThemeStyle(style)
        }
    }

    private func broadcastClientThemeStyle(_ style: ClientThemeStyle) {
        // userInfo carries the value itself, not just a "something changed"
        // ping -- re-reading UserDefaults on receipt would race against
        // whether this process's write above had actually propagated to
        // cfprefsd by the time PuckClient's observer fires (the same race
        // AppAppearance's broadcast hit first).
        DistributedNotificationCenter.default().postNotificationName(
            ClientThemeStyle.crossProcessChangeNotification,
            object: nil,
            userInfo: style.crossProcessUserInfo,
            deliverImmediately: true
        )
    }
}
