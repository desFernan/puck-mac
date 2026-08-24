//
//  ClientPaletteTests.swift
//  Puck
//

import XCTest
@testable import Puck

final class ClientPaletteTests: XCTestCase {
    func test_accent_isIdenticalAcrossLightAndDark() {
        XCTAssertEqual(ClientPalette.light.accent, ClientPalette.dark.accent)
    }

    func test_statusIdle_reusesTextSecondary() {
        XCTAssertEqual(ClientPalette.dark.statusIdle, ClientPalette.dark.textSecondary)
        XCTAssertEqual(ClientPalette.light.statusIdle, ClientPalette.light.textSecondary)
    }

    func test_statusActive_reusesAccent() {
        XCTAssertEqual(ClientPalette.dark.statusActive, ClientPalette.dark.accent)
        XCTAssertEqual(ClientPalette.light.statusActive, ClientPalette.light.accent)
    }

    func test_statusColors_areDistinctFromAccentAndEachOther() {
        let dark = ClientPalette.dark
        let colors = [dark.accent, dark.statusSuccess, dark.statusError, dark.statusWarning]
        XCTAssertEqual(Set(colors).count, colors.count, "status colors must not collide with accent or each other")
    }
}
