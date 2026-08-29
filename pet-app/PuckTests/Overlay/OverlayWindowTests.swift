//
//  OverlayWindowTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Verifies the declared window configuration (F1).
//  Never orders the window on screen, so it doesn't visibly flash during tests.
//

import XCTest
import AppKit
@testable import Puck

final class OverlayWindowTests: XCTestCase {
    private func makeWindow() -> OverlayWindow {
        OverlayWindow(screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    func test_isBorderlessAndTransparent() {
        let window = makeWindow()

        XCTAssertEqual(window.styleMask, [.borderless, .nonactivatingPanel])
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        XCTAssertFalse(window.hasShadow)
    }

    func test_floatsAboveNormalWindowsAndJoinsAllSpaces() {
        let window = makeWindow()

        XCTAssertEqual(window.level, .floating)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.stationary))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    func test_ignoresMouseEventsByDefault() {
        XCTAssertTrue(makeWindow().ignoresMouseEvents)
    }

    /// Clicking the pet must not bring pet-app forward: whatever the user was
    /// working in stays frontmost, which on the island is the difference
    /// between picking the pet up and the pet leaving.
    func test_doesNotActivateTheAppWhenClicked() {
        XCTAssertTrue(makeWindow().styleMask.contains(.nonactivatingPanel))
    }

    func test_neverBecomesKeyOrMain() {
        let window = makeWindow()

        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
    }
}
