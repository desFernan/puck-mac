//
//  SettingsSplitTests.swift
//  PuckTests
//
//  Which settings the menu bar panel carries and which the window does.
//
//  The panel drops from the status item over whatever the user was doing, so
//  it holds what the pet is doing right now. Everything set once and then
//  left was making a drop-down into a scrolling form, and moved to a window.
//

import SwiftUI
import XCTest
@testable import Puck

@MainActor
final class SettingsSplitTests: XCTestCase {
    private func store() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "SettingsSplitTests-\(UUID().uuidString)")!)
    }

    /// The panel is a fixed height because a popover has no other way to know
    /// how big to be; the window sizes itself to what it holds.
    func test_onlyThePanelIsGivenAHeight() {
        let panel = SettingsView(store: store(), showsOnlyLiveControls: true)
        let window = SettingsView(store: store(), showsOnlyLiveControls: false)

        XCTAssertTrue(panel.showsOnlyLiveControls)
        XCTAssertFalse(window.showsOnlyLiveControls)
    }

    /// The one the panel offers and the window does not: a window is not
    /// going to offer to open itself.
    func test_theWindowDoesNotOfferToOpenItself() {
        var opened = 0
        let panel = SettingsView(store: store(), onOpenSettings: { opened += 1 }, showsOnlyLiveControls: true)

        panel.onOpenSettings?()

        XCTAssertEqual(opened, 1)
    }

    /// The row has a label in every language, like every other row. A missing
    /// one renders as an empty button, which is a button nobody can read.
    func test_theSettingsRowIsNamedInEveryLanguage() {
        for language in AppLanguage.allCases {
            let label = Strings.text(.menuSettings, language: language)
            XCTAssertFalse(label.isEmpty, "\(language) has no name for the settings row")
        }
    }
}
