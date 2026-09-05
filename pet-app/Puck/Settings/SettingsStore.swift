//
//  SettingsStore.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  UserDefaults wrapper: volume, hotkeys, misc options
//

import CoreGraphics
import Foundation

final class SettingsStore {
    private enum Keys {
        static let volume = "Puck.volume"
        static let isMuted = "Puck.isMuted"
        static let autoMuteOnFocus = "Puck.autoMuteOnFocus"
        static let avoidClimbingFocusedWindow = "Puck.avoidClimbingFocusedWindow"
        static let notchPanelEnabled = "Puck.notchPanelEnabled"
        static let walkSpeedMultiplier = "Puck.walkSpeedMultiplier"
        static let toyScale = "Puck.toyScale"
        static let speechLocale = "Puck.speechLocale"
        static let appearance = AppAppearance.defaultsKey
        static let clientThemeStyle = ClientThemeStyle.defaultsKey
        static let language = AppLanguage.defaultsKey
        static let pushToTalk = "Puck.hotkey.pushToTalk"
        static let textInput = "Puck.hotkey.textInput"
        static let characterSummon = "Puck.hotkey.characterSummon"
        static let toySummon1 = "Puck.hotkey.toySummon1"
        static let toySummon2 = "Puck.hotkey.toySummon2"
        static let isMuteComplaintEnabled = "Puck.isMuteComplaintEnabled"
        static let selectedAvatarName = "Puck.selectedAvatarName"
        static let isAvatarMirrored = "Puck.isAvatarMirrored"
        static let isAvatarOutlined = "Puck.isAvatarOutlined"
        static let avatarPoseAdjustments = "Puck.avatarPoseAdjustments"
        static let hasRequestedAccessibility = "Puck.hasRequestedAccessibility"
        static let petAnnouncesRuns = "Puck.petAnnouncesRuns"
    }

    private let defaults: UserDefaults

    /// Settings changes only persisted to UserDefaults with no way for a
    /// running session to react -- AppDelegate subscribes to these so
    /// Volume/Mute in Settings take effect on the live SFXPlayer immediately
    /// instead of only after a restart.
    var onVolumeChanged: ((Float) -> Void)?
    var onMuteChanged: ((Bool) -> Void)?
    var onWalkSpeedMultiplierChanged: ((Double) -> Void)?
    /// AppDelegate uses this to keep
    /// NSApp.appearance (NSPopover chrome, NSVisualEffectView materials --
    /// AppKit-native rendering that .preferredColorScheme never touches) in
    /// sync with a live appearance change instead of only applying it at
    /// launch.
    var onAppearanceChanged: ((AppAppearance) -> Void)?
    /// The client theme should stay in sync with the menu bar settings, the
    /// same way Shady-style apps do -- AppDelegate uses this to
    /// broadcast the new value to PuckClient (DistributedNotificationCenter,
    /// same shape as onAppearanceChanged's own broadcast) so the client
    /// window picks it up immediately.
    var onClientThemeStyleChanged: ((ClientThemeStyle) -> Void)?
    /// The UI language is read on every `Strings.text(_:)` call from a
    /// per-process copy, so a change has to be pushed into this process and
    /// broadcast to PuckClient -- same shape as the theme above.
    var onLanguageChanged: ((AppLanguage) -> Void)?
    /// Picking a different installed avatar in Settings has to
    /// swap the *running* pet immediately, not just take effect next launch.
    var onSelectedAvatarChanged: ((String) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the Accessibility prompt has already been raised once. Must
    /// outlive the process, or every launch is a first launch and the user is
    /// asked again every time.
    var hasRequestedAccessibility: Bool {
        get { defaults.bool(forKey: Keys.hasRequestedAccessibility) }
        set { defaults.set(newValue, forKey: Keys.hasRequestedAccessibility) }
    }

    var volume: Float {
        get { defaults.object(forKey: Keys.volume) as? Float ?? 1.0 }
        set {
            defaults.set(newValue, forKey: Keys.volume)
            onVolumeChanged?(newValue)
        }
    }

    var isMuted: Bool {
        get { defaults.bool(forKey: Keys.isMuted) }
        set {
            defaults.set(newValue, forKey: Keys.isMuted)
            onMuteChanged?(newValue)
        }
    }

    /// Off by default — FocusModeObserver's Do Not Disturb detection is
    /// unverified on modern macOS (see its doc comment), so this shouldn't
    /// silently mute SFX for everyone until someone confirms it works.
    var autoMuteOnFocus: Bool {
        get { defaults.bool(forKey: Keys.autoMuteOnFocus) }
        set { defaults.set(newValue, forKey: Keys.autoMuteOnFocus) }
    }

    /// Whether the notch panel is shown at all.
    ///
    /// On. It was off while it was being built, because a window over the
    /// menu bar that takes the pointer where it is drawn -- and a notch given
    /// to a display that has no camera housing -- is not something to do to
    /// somebody who installed a desktop pet and did not ask for it. It now
    /// does something worth having found: what the whole machine is playing,
    /// a browser tab included, in the one place on screen that is always in
    /// reach.
    ///
    /// Read through `object(forKey:)` rather than `bool(forKey:)`: the latter
    /// cannot tell "switched off" from "never touched", so turning it off
    /// would have been undone by its own default on the next launch.
    var isNotchPanelEnabled: Bool {
        get { defaults.object(forKey: Keys.notchPanelEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.notchPanelEnabled) }
    }

    /// Whether the pet says anything about a run that finished while the chat
    /// window was not the one being looked at -- and whether it comes to the
    /// pointer when a run has stopped for an approval.
    ///
    /// On. A run that ended, or one that is waiting on an answer, is
    /// otherwise something you find out about the next time you happen to
    /// look at the window -- and for an approval that means the agent sits
    /// doing nothing until you do. It only ever speaks while the window is
    /// behind something else, so it cannot talk over a transcript you are
    /// already reading.
    ///
    /// Read through `object(forKey:)` rather than `bool(forKey:)`: the latter
    /// cannot tell "switched off" from "never touched", so turning it off
    /// would be undone by its own default on the next launch.
    var petAnnouncesRuns: Bool {
        get { defaults.object(forKey: Keys.petAnnouncesRuns) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.petAnnouncesRuns) }
    }

    /// "포커스 창 위로 안 올라감" wander option (F3).
    var avoidClimbingFocusedWindow: Bool {
        get { defaults.object(forKey: Keys.avoidClimbingFocusedWindow) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.avoidClimbingFocusedWindow) }
    }

    /// Whether muting gets a sulk (angry face + "제 목소리가 시끄러우신거에
    /// 요?") -- togglable, since the sulk used to also move the pet to center
    /// screen and that behavior needed to become optional. No
    /// live-callback needed: this is only consulted at the moment mute is
    /// toggled, not applied to something already on screen.
    var isMuteComplaintEnabled: Bool {
        get { defaults.object(forKey: Keys.isMuteComplaintEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.isMuteComplaintEnabled) }
    }

    /// Draws the avatar the other way round.
    ///
    /// Which way a character faces is decided by whoever drew it, and the app
    /// assumes one of the two. An avatar drawn facing the other way walks
    /// backwards for its whole life, and the only fix was to edit the
    /// artwork. This is a mirror on top of the facing the pet already has,
    /// so turning it on flips both directions rather than pinning the pet to
    /// one of them.
    var isAvatarMirrored: Bool {
        get { defaults.bool(forKey: Keys.isAvatarMirrored) }
        set {
            defaults.set(newValue, forKey: Keys.isAvatarMirrored)
            onAvatarMirroredChanged?(newValue)
        }
    }

    var onAvatarMirroredChanged: ((Bool) -> Void)?

    /// Draws a white edge around the character.
    ///
    /// Worth having because the pet is drawn over whatever is on screen, and
    /// a dark character on a dark window is a shape you lose track of. A
    /// sticker's edge separates it from the background whatever the
    /// background is.
    var isAvatarOutlined: Bool {
        get { defaults.bool(forKey: Keys.isAvatarOutlined) }
        set {
            defaults.set(newValue, forKey: Keys.isAvatarOutlined)
            onAvatarOutlinedChanged?(newValue)
        }
    }

    var onAvatarOutlinedChanged: ((Bool) -> Void)?

    /// Per-pose corrections for artwork drawn the other way round -- see
    /// AvatarPose.
    ///
    /// Stored as JSON in one key rather than a key per pose: it is read and
    /// written as a whole, and a key per pose is four times the chance of
    /// half a setting surviving.
    var avatarPoseAdjustments: AvatarPoseAdjustments {
        get {
            guard let data = defaults.data(forKey: Keys.avatarPoseAdjustments),
                  let decoded = try? JSONDecoder().decode(AvatarPoseAdjustments.self, from: data)
            else { return AvatarPoseAdjustments() }
            return decoded
        }
        set {
            // Cleared rather than written empty, so a settings file does not
            // keep a record of corrections somebody undid.
            if newValue.isEmpty {
                defaults.removeObject(forKey: Keys.avatarPoseAdjustments)
            } else if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.avatarPoseAdjustments)
            }
            onAvatarPoseAdjustmentsChanged?(newValue)
        }
    }

    var onAvatarPoseAdjustmentsChanged: ((AvatarPoseAdjustments) -> Void)?

    /// Which installed avatar (a folder name under
    /// AvatarCatalogue.avatarsDirectory) is currently active. "dummy" is the
    /// bundled default, always seeded on first run (see AvatarInstaller).
    var selectedAvatarName: String {
        get { defaults.string(forKey: Keys.selectedAvatarName) ?? "dummy" }
        set {
            defaults.set(newValue, forKey: Keys.selectedAvatarName)
            onSelectedAvatarChanged?(newValue)
        }
    }

    /// Multiplies MovementSolver.walkSpeed for Walk/Climb/WalkOnTop/MoveTo/
    /// Ceiling. 1.0 == the default speed.
    var walkSpeedMultiplier: Double {
        get { defaults.object(forKey: Keys.walkSpeedMultiplier) as? Double ?? 1.0 }
        set {
            defaults.set(newValue, forKey: Keys.walkSpeedMultiplier)
            onWalkSpeedMultiplierChanged?(newValue)
        }
    }

    /// Size of the ball toy, as a multiple of its built-in radius. Lives here rather than in
    /// the avatar manifest because the toy is bundled with the app, not with
    /// an avatar -- swapping avatars must not resize or remove it.
    var toyScale: Double {
        get { defaults.object(forKey: Keys.toyScale) as? Double ?? 1.0 }
        set {
            defaults.set(newValue, forKey: Keys.toyScale)
            onToyScaleChanged?(newValue)
        }
    }

    var onToyScaleChanged: ((Double) -> Void)?

    // Which toy the pet has stopped being a setting on 2026-07-30: several
    // can be out at once now, and the menu bar's per-toy on/off list is the
    // one place that decides. A stored "current toy" alongside it would just
    // be a second answer to the same question.

    var appearance: AppAppearance {
        get {
            AppAppearance.resolved(fromDefaultsValue: defaults.string(forKey: Keys.appearance))
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.appearance)
            onAppearanceChanged?(newValue)
        }
    }

    var clientThemeStyle: ClientThemeStyle {
        get {
            ClientThemeStyle.resolved(fromDefaultsValue: defaults.string(forKey: Keys.clientThemeStyle))
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.clientThemeStyle)
            onClientThemeStyleChanged?(newValue)
        }
    }

    var language: AppLanguage {
        get { AppLanguage.resolved(fromDefaultsValue: defaults.string(forKey: Keys.language)) }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.language)
            onLanguageChanged?(newValue)
        }
    }

    var speechRecognitionLocaleIdentifier: String {
        get { defaults.string(forKey: Keys.speechLocale) ?? Locale.current.identifier }
        set { defaults.set(newValue, forKey: Keys.speechLocale) }
    }

    var hotkeyBindings: HotkeyBindings {
        get {
            HotkeyBindings(
                pushToTalk: binding(forKey: Keys.pushToTalk) ?? HotkeyBindings.defaults.pushToTalk,
                textInput: binding(forKey: Keys.textInput) ?? HotkeyBindings.defaults.textInput,
                characterSummon: binding(forKey: Keys.characterSummon) ?? HotkeyBindings.defaults.characterSummon,
                toySummon1: binding(forKey: Keys.toySummon1) ?? HotkeyBindings.defaults.toySummon1,
                toySummon2: binding(forKey: Keys.toySummon2) ?? HotkeyBindings.defaults.toySummon2
            )
        }
        set {
            setBinding(newValue.pushToTalk, forKey: Keys.pushToTalk)
            setBinding(newValue.textInput, forKey: Keys.textInput)
            setBinding(newValue.characterSummon, forKey: Keys.characterSummon)
            setBinding(newValue.toySummon1, forKey: Keys.toySummon1)
            setBinding(newValue.toySummon2, forKey: Keys.toySummon2)
        }
    }

    // CGEventFlags isn't Codable, so bindings are stored as plain
    // [keyCode, rawModifierFlags] dictionaries rather than via JSONEncoder.
    private func binding(forKey key: String) -> HotkeyBinding? {
        guard
            let dict = defaults.dictionary(forKey: key),
            let keyCode = dict["keyCode"] as? Int,
            let modifiers = dict["modifiers"] as? UInt64
        else {
            return nil
        }
        return HotkeyBinding(keyCode: CGKeyCode(keyCode), modifierFlags: CGEventFlags(rawValue: modifiers))
    }

    private func setBinding(_ binding: HotkeyBinding, forKey key: String) {
        defaults.set(["keyCode": Int(binding.keyCode), "modifiers": binding.modifierFlags.rawValue], forKey: key)
    }
}
