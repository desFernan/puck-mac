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

    /// The window is where things are configured, so everything that can be
    /// configured is in it -- the avatar included, which used to be reachable
    /// only from a popover you had to keep open while looking at it.
    func test_theWindowHoldsEverythingThatIsConfigured() {
        let window = SettingsView(store: store(), showsOnlyLiveControls: false)

        XCTAssertEqual(window.sections, [.avatar, .poses, .quickSound, .sound, .movement, .general])
    }

    /// It still draws no control it cannot drive. The toy tiles and Quit
    /// rendered in the window once with every callback nil, so they looked
    /// live and did nothing -- Quit above all.
    func test_theWindowDrawsNoControlItCannotDrive() {
        let window = SettingsView(store: store(), showsOnlyLiveControls: false)

        XCTAssertFalse(window.sections.contains(.toys), "the window has no toy callback")
        XCTAssertFalse(window.sections.contains(.actions), "the window has no quit callback")
    }

    /// And the panel keeps what you reach for without wanting a window. The
    /// set-once controls were what made it a scrolling form in the first
    /// place, and they are not back.
    func test_thePanelKeepsWhatIsReachedForInPassing() {
        let panel = SettingsView(store: store(), showsOnlyLiveControls: true)

        XCTAssertEqual(panel.sections, [.toys, .quickSound, .avatarSize, .theme, .actions])
        XCTAssertFalse(panel.sections.contains(.movement))
        XCTAssertFalse(panel.sections.contains(.general))
    }

    /// A quick view has to be quick to be worth having. The handful worth
    /// changing without opening anything -- the toys, mute and volume, how
    /// big the pet is, which way the theme goes -- are all in it; stripping
    /// it back to two of those made it a menu that sends you somewhere else.
    func test_thePanelHoldsEverythingWorthNudging() {
        let panel = SettingsView(store: store(), showsOnlyLiveControls: true)

        for section in [SettingsView.SectionGroup.toys, .quickSound, .avatarSize, .theme] {
            XCTAssertTrue(panel.sections.contains(section), "\(section) is not in the quick view")
        }
    }

    /// The manager is a page -- picker, import, sixteen emotion rows -- and
    /// belongs in the window. Only the size slider comes out of it.
    func test_theManagerItselfStaysInTheWindow() {
        let panel = SettingsView(store: store(), showsOnlyLiveControls: true)

        XCTAssertFalse(panel.sections.contains(.avatar))
    }

    /// Volume is in both, on purpose: it is the one setting people change
    /// mid-sentence, and sending them to a window for it is the reason the
    /// split exists at all.
    func test_volumeIsReachableFromBoth() {
        let panel = SettingsView(store: store(), showsOnlyLiveControls: true)
        let window = SettingsView(store: store(), showsOnlyLiveControls: false)

        XCTAssertTrue(panel.sections.contains(.quickSound))
        XCTAssertTrue(window.sections.contains(.quickSound))
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

    /// The reported fault: the settings window looked empty. It was left to
    /// size itself to its content and what it holds is a ScrollView, which
    /// has no height of its own to report -- so it came up as a title bar
    /// with a sliver underneath, with every control in there and none of them
    /// visible.
    func testTheWindowAsksForAHeightItCanBeSeenAt() {
        XCTAssertGreaterThanOrEqual(SettingsView.windowMinHeight, 200)
        XCTAssertGreaterThan(SettingsView.windowIdealHeight, SettingsView.windowMinHeight)
    }

    /// And it has to be tall enough for what it holds: three sections of
    /// rows, which is what the split puts in the window.
    func testTheWindowIsTallEnoughForTheSectionsItDraws() {
        let view = SettingsView(store: store(), showsOnlyLiveControls: false)

        XCTAssertEqual(view.sections, [.avatar, .poses, .quickSound, .sound, .movement, .general])
        // Three sections, each a title and two or three rows. Well under the
        // ideal height, which is the point of the number.
        XCTAssertGreaterThan(SettingsView.windowIdealHeight, 400)
    }

    // MARK: - The window's categories

    /// Every section the window draws belongs to exactly one category, or a
    /// section is either unreachable or drawn twice on two different pages.
    func test_everyWindowSectionHasExactlyOneCategory() {
        let window = SettingsView(store: store(), showsOnlyLiveControls: false)
        let fromCategories = SettingsView.SettingsCategory.allCases.flatMap(\.sections)

        XCTAssertEqual(fromCategories.count, Set(fromCategories.map(\.hashValue)).count,
                       "a section is on more than one page")
        XCTAssertEqual(Set(window.sections.map(\.hashValue)), Set(fromCategories.map(\.hashValue)))
    }

    /// The quick view has no sidebar, so its sections are its own list and
    /// must not be dragged around by a change to the window's pages.
    func test_theQuickViewIsNotBuiltFromCategories() {
        let panel = SettingsView(store: store(), showsOnlyLiveControls: true)

        XCTAssertTrue(panel.sections.contains(.actions), "the quick view keeps its own way out")
        XCTAssertFalse(
            SettingsView.SettingsCategory.allCases.flatMap(\.sections).contains(.actions),
            "the window offers no Quit"
        )
    }

    /// Each sidebar row has a name in every language, or the list has a blank
    /// row and nothing says which page it opens.
    func test_everyCategoryIsNamedInEveryLanguage() {
        for category in SettingsView.SettingsCategory.allCases {
            for language in AppLanguage.allCases {
                XCTAssertFalse(
                    Strings.text(category.label, language: language).isEmpty,
                    "\(language) has no name for \(category)"
                )
            }
        }
    }
}
