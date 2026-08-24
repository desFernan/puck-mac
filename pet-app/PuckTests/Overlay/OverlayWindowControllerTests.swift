//
//  OverlayWindowControllerTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Verifies one window is created per real display and positioned using
//  AppKit frames (not the normalized, Y-down movement-logic space).
//

import XCTest
@testable import Puck

/// `@MainActor`: what it exercises belongs to the main thread -- a
/// window, the status item, or the character they draw.
@MainActor
final class OverlayWindowControllerTests: XCTestCase {
    func test_start_createsOneWindowPerDisplay_positionedAtItsAppKitFrame() throws {
        let screenManager = try XCTUnwrap(ScreenManager())
        let controller = OverlayWindowController(screenManager: screenManager)

        controller.start()
        defer { controller.stop() }

        XCTAssertEqual(controller.windows.count, screenManager.current.appKitFrames.count)
        for (window, frame) in zip(controller.windows, screenManager.current.appKitFrames) {
            XCTAssertEqual(window.frame, frame)
        }
    }

    func test_stop_ordersOutAndClearsWindows() throws {
        let screenManager = try XCTUnwrap(ScreenManager())
        let controller = OverlayWindowController(screenManager: screenManager)

        controller.start()
        controller.stop()

        XCTAssertTrue(controller.windows.isEmpty)
    }

    func test_start_firesOnWindowsRebuilt_soConsumersCanReparentTheAvatar() throws {
        let screenManager = try XCTUnwrap(ScreenManager())
        let controller = OverlayWindowController(screenManager: screenManager)

        var rebuiltCount = 0
        controller.onWindowsRebuilt = { rebuiltCount += 1 }

        controller.start()
        defer { controller.stop() }

        XCTAssertEqual(rebuiltCount, 1)
    }
}
