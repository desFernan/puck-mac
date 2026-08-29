//
//  SettingsStoreTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Uses a dedicated UserDefaults suite (never .standard) so tests can't
//  pollute or be polluted by the developer's real defaults.
//

import XCTest
import CoreGraphics
@testable import Puck

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "PuckTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_volume_defaultsToOne() {
        XCTAssertEqual(SettingsStore(defaults: defaults).volume, 1.0)
    }

    func test_volume_roundTrips() {
        let store = SettingsStore(defaults: defaults)
        store.volume = 0.4
        XCTAssertEqual(store.volume, 0.4)
    }

    func test_isMuted_defaultsToFalse() {
        XCTAssertFalse(SettingsStore(defaults: defaults).isMuted)
    }

    func test_autoMuteOnFocus_defaultsToFalse() {
        // Off by default -- FocusModeObserver's detection is unverified on
        // modern macOS, so this shouldn't silently mute SFX for everyone.
        XCTAssertFalse(SettingsStore(defaults: defaults).autoMuteOnFocus)
    }

    func test_avoidClimbingFocusedWindow_defaultsToTrue() {
        XCTAssertTrue(SettingsStore(defaults: defaults).avoidClimbingFocusedWindow)
    }

    func test_isMuteComplaintEnabled_defaultsToTrue() {
        XCTAssertTrue(SettingsStore(defaults: defaults).isMuteComplaintEnabled)
    }

    func test_isMuteComplaintEnabled_roundTrips() {
        let store = SettingsStore(defaults: defaults)

        store.isMuteComplaintEnabled = false

        XCTAssertFalse(SettingsStore(defaults: defaults).isMuteComplaintEnabled)
    }

    func test_selectedAvatarName_defaultsToDummy() {
        XCTAssertEqual(SettingsStore(defaults: defaults).selectedAvatarName, "dummy")
    }

    func test_settingSelectedAvatarName_firesOnSelectedAvatarChanged() {
        let store = SettingsStore(defaults: defaults)
        var received: String?
        store.onSelectedAvatarChanged = { received = $0 }

        store.selectedAvatarName = "wizard"

        XCTAssertEqual(received, "wizard")
        XCTAssertEqual(store.selectedAvatarName, "wizard")
    }

    func test_speechRecognitionLocaleIdentifier_defaultsToSystemLocale() {
        XCTAssertEqual(
            SettingsStore(defaults: defaults).speechRecognitionLocaleIdentifier,
            Locale.current.identifier
        )
    }

    func test_speechRecognitionLocaleIdentifier_roundTrips() {
        let store = SettingsStore(defaults: defaults)
        store.speechRecognitionLocaleIdentifier = "en-US"
        XCTAssertEqual(store.speechRecognitionLocaleIdentifier, "en-US")
    }

    func test_hotkeyBindings_defaultToPlanDefaults() {
        XCTAssertEqual(SettingsStore(defaults: defaults).hotkeyBindings, .defaults)
    }

    func test_settingVolume_firesOnVolumeChanged() {
        let store = SettingsStore(defaults: defaults)
        var received: Float?
        store.onVolumeChanged = { received = $0 }

        store.volume = 0.6

        XCTAssertEqual(received, 0.6)
    }

    func test_walkSpeedMultiplier_defaultsToOne() {
        XCTAssertEqual(SettingsStore(defaults: defaults).walkSpeedMultiplier, 1.0)
    }

    func test_walkSpeedMultiplier_roundTrips() {
        let store = SettingsStore(defaults: defaults)
        store.walkSpeedMultiplier = 1.8
        XCTAssertEqual(store.walkSpeedMultiplier, 1.8)
    }

    func test_settingWalkSpeedMultiplier_firesOnWalkSpeedMultiplierChanged() {
        let store = SettingsStore(defaults: defaults)
        var received: Double?
        store.onWalkSpeedMultiplierChanged = { received = $0 }

        store.walkSpeedMultiplier = 0.5

        XCTAssertEqual(received, 0.5)
    }

    func test_settingIsMuted_firesOnMuteChanged() {
        let store = SettingsStore(defaults: defaults)
        var received: Bool?
        store.onMuteChanged = { received = $0 }

        store.isMuted = true

        XCTAssertEqual(received, true)
    }

    // An explicit in-app appearance setting.
    func test_appearance_defaultsToSystem() {
        XCTAssertEqual(SettingsStore(defaults: defaults).appearance, .system)
    }

    func test_appearance_roundTrips() {
        let store = SettingsStore(defaults: defaults)
        store.appearance = .dark
        XCTAssertEqual(store.appearance, .dark)
    }

    func test_settingAppearance_firesOnAppearanceChanged() {
        let store = SettingsStore(defaults: defaults)
        var received: AppAppearance?
        store.onAppearanceChanged = { received = $0 }

        store.appearance = .light

        XCTAssertEqual(received, .light)
    }

    // The client window's theme
    // moved here from being a ClientWindow-local setting, so it stays in
    // sync with the menu bar settings.
    func test_clientThemeStyle_defaultsToDark() {
        XCTAssertEqual(SettingsStore(defaults: defaults).clientThemeStyle, .dark)
    }

    func test_clientThemeStyle_roundTrips() {
        let store = SettingsStore(defaults: defaults)
        store.clientThemeStyle = .light
        XCTAssertEqual(store.clientThemeStyle, .light)
    }

    func test_settingClientThemeStyle_firesOnClientThemeStyleChanged() {
        let store = SettingsStore(defaults: defaults)
        var received: ClientThemeStyle?
        store.onClientThemeStyleChanged = { received = $0 }

        store.clientThemeStyle = .light

        XCTAssertEqual(received, .light)
    }

    func test_hotkeyBindings_roundTrip() {
        let store = SettingsStore(defaults: defaults)
        var bindings = HotkeyBindings.defaults
        bindings.pushToTalk = HotkeyBinding(keyCode: 12, modifierFlags: [.maskControl])

        store.hotkeyBindings = bindings

        XCTAssertEqual(store.hotkeyBindings, bindings)
    }

    /// The notch panel ships on. It was off while it was being built, and a
    /// switch that stayed off after the work was done is a feature nobody
    /// finds.
    func test_notchPanel_defaultsToOn() {
        XCTAssertTrue(SettingsStore(defaults: defaults).isNotchPanelEnabled)
    }

    /// Switching it off has to survive a relaunch. A default read through
    /// `bool(forKey:)` cannot tell "off" from "never set", so an off switch
    /// would come back on by itself -- which is the trap that comes with
    /// defaulting a flag to true.
    func test_notchPanel_stayingOffSurvivesARelaunch() {
        let store = SettingsStore(defaults: defaults)
        store.isNotchPanelEnabled = false

        XCTAssertFalse(SettingsStore(defaults: defaults).isNotchPanelEnabled)
    }

    func test_notchPanel_roundTrips() {
        let store = SettingsStore(defaults: defaults)
        store.isNotchPanelEnabled = false
        store.isNotchPanelEnabled = true

        XCTAssertTrue(SettingsStore(defaults: defaults).isNotchPanelEnabled)
    }
}
