//
//  AppDelegate+Permissions.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Launch-time TCC permission self-check and re-prompt (microphone, speech
//  recognition, Accessibility).
//

extension AppDelegate {
    // MARK: - Permissions

    /// Accessibility is asked for here; the microphone and speech recognition
    /// are not.
    ///
    /// They used to be, on the grounds that the app should not fail silently
    /// the first time push-to-talk is held. What that produced in practice was
    /// a microphone prompt on the desktop at every launch after a rebuild --
    /// macOS pins a locally-signed app's privacy grants to the exact binary,
    /// so every install is a new app to it and everything reverts to
    /// undecided. Someone who never uses voice was answering that dialog
    /// forever.
    ///
    /// So they are asked for where they are used, which is also where the
    /// question makes sense: the first time push-to-talk is held
    /// (VoiceInputController). Accessibility stays here because it cannot be
    /// requested at the point of use at all -- the key it enables is the one
    /// that would trigger the request.
    func requestPermissions() {
        AppLogger.shared.log(.info, "Launch permission status: \(PermissionOnboarding.currentStatus())")

        // Accessibility can't be requested silently — the only way to ask is
        // macOS's own modal. Ask once and then stay quiet: prompting on every
        // launch means anyone who dismisses it, or who is part-way through
        // granting it in System Settings, gets the dialog again next time.
        // Settings has a button for granting it later.
        if PermissionPromptPolicy.shouldPromptForAccessibility(
            isTrusted: AccessibilityPermission.isTrusted(prompt: false),
            hasAskedBefore: settingsStore.hasRequestedAccessibility
        ) {
            settingsStore.hasRequestedAccessibility = true
            _ = AccessibilityPermission.isTrusted(prompt: true)
        }
    }
}
