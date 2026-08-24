//
//  AppDelegate+Language.swift
//  Puck
//
//  Applies the selected UI language to this process and broadcasts it to
//  PuckClient over DistributedNotificationCenter.
//

import Foundation

extension AppDelegate {
    // MARK: - UI language, applied here and broadcast to PuckClient

    /// Unlike the client theme, this process renders in the language too --
    /// the menu bar panel, Settings, and the pet's own speech bubbles all go
    /// through `Strings`. So the value is applied locally *and* broadcast,
    /// rather than only broadcast.
    func setUpLanguage() {
        applyLanguage(settingsStore.language)
        settingsStore.onLanguageChanged = { [weak self] language in
            self?.applyLanguage(language)
        }
        // Unlike the theme, this setting has two writers: PuckClient's own
        // settings window offers the same picker, because that is the window
        // most of this app's text is in. So this process listens as well as
        // posts. Its own post comes back here and `apply` ignores it -- the
        // value is already the one it just set.
        languageObserver = DistributedNotificationCenter.default().addObserver(
            forName: AppLanguage.crossProcessChangeNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let language = AppLanguage.resolved(fromCrossProcessUserInfo: notification.userInfo) else { return }
            Localization.shared.apply(language)
        }
    }

    private func applyLanguage(_ language: AppLanguage) {
        Localization.shared.apply(language)
        // The value travels with the notification: re-reading UserDefaults on
        // receipt would race against whether this process's write had
        // propagated to cfprefsd by the time the other observer fires -- the
        // same race the theme broadcast documents.
        language.broadcast()
    }
}
