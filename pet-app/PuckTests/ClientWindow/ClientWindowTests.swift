//
//  ClientWindowTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Never orders the window on screen, so it doesn't visibly flash during
//  tests.
//

import XCTest
import AppKit
@testable import Puck

final class ClientWindowTests: XCTestCase {
    private func makeWindow() -> ClientWindow {
        ClientWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 740))
    }

    func test_appliesGlassChrome() {
        let window = makeWindow()

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .hidden)
    }

    func test_isReleasedWhenClosed_isFalse() {
        // A window cached in a strong property (AppDelegate.window) that IS
        // released on close is a use-after-free the next time it's shown --
        // a documented gap this repo has hit before with other windows.
        XCTAssertFalse(makeWindow().isReleasedWhenClosed)
    }
}
