//
//  TextInputBubbleWindowTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Verifies this is the one overlay-adjacent window that CAN become key.
//

import XCTest
import AppKit
@testable import Puck

final class TextInputBubbleWindowTests: XCTestCase {
    private func makeWindow() -> TextInputBubbleWindow {
        TextInputBubbleWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 60))
    }

    func test_canBecomeKey_unlikeOverlayWindow() {
        XCTAssertTrue(makeWindow().canBecomeKey)
    }

    func test_isBorderlessAndTransparentBackground() {
        let window = makeWindow()
        XCTAssertEqual(window.styleMask, [.borderless])
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
    }

    func test_floatsAboveNormalWindows() {
        XCTAssertEqual(makeWindow().level, .floating)
    }

    // Re-triggering the hotkey while the bubble is already open used to
    // recapture previouslyFrontmostApp with Puck itself (since Puck's
    // own bubble window is key at that point), silently clobbering the real
    // target app -- closeAndRestoreFocus() then "restored" focus to Puck
    // instead (found via review). Counting frontmostAppProvider calls, rather
    // than comparing NSWorkspace.shared.frontmostApplication before/after, is
    // what makes this deterministic: a real frontmost-app query can't be
    // relied on to actually change value inside a test runner.
    func test_reTriggeringWhileAlreadyVisible_doesNotRecaptureFrontmostApp() {
        let window = makeWindow()
        var captureCount = 0
        window.frontmostAppProvider = {
            captureCount += 1
            return nil
        }

        window.showAndActivate()
        window.showAndActivate()

        XCTAssertEqual(captureCount, 1, "must not recapture the frontmost app while already visible")
    }
}
