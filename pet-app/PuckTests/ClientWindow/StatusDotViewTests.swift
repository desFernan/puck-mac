//
//  StatusDotViewTests.swift
//  Puck
//

import XCTest
import SwiftUI
@testable import Puck

final class StatusDotViewTests: XCTestCase {
    func test_color_forEachStatus_matchesPaletteToken() {
        let palette = ClientPalette.dark
        XCTAssertEqual(DotStatus.idle.color(in: palette), palette.statusIdle)
        XCTAssertEqual(DotStatus.active.color(in: palette), palette.statusActive)
        XCTAssertEqual(DotStatus.success.color(in: palette), palette.statusSuccess)
        XCTAssertEqual(DotStatus.error.color(in: palette), palette.statusError)
    }

    func test_pulsesDefaultsToTrue() {
        let dot = StatusDotView(status: .active, palette: .dark)
        XCTAssertTrue(dot.pulses)
    }

    func test_pulsesCanBeDisabledForPersistentStates() {
        let dot = StatusDotView(status: .active, palette: .dark, pulses: false)
        XCTAssertFalse(dot.pulses)
    }
}
