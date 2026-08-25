//
//  OverlayWindowControllerTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Verifies one window is created across every real display and positioned
//  using AppKit frames (not the normalized, Y-down movement-logic space).
//

import XCTest
@testable import Puck

/// `@MainActor`: what it exercises belongs to the main thread -- a
/// window, the status item, or the character they draw.
@MainActor
final class OverlayWindowControllerTests: XCTestCase {
    /// One window over every display, not one each: the pet is one character
    /// in one layer tree, and a window per display would mean handing it over
    /// -- layer, coordinates and all -- every time it crossed an edge.
    func test_start_createsOneWindowCoveringEveryDisplay() throws {
        let screenManager = try XCTUnwrap(ScreenManager())
        let controller = OverlayWindowController(screenManager: screenManager)

        controller.start()
        defer { controller.stop() }

        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.frame, screenManager.current.appKitBounds)
        for frame in screenManager.current.appKitFrames {
            XCTAssertTrue(window.frame.contains(frame), "every display is inside the overlay")
        }
    }

    func test_stop_ordersOutAndClearsTheWindow() throws {
        let screenManager = try XCTUnwrap(ScreenManager())
        let controller = OverlayWindowController(screenManager: screenManager)

        controller.start()
        controller.stop()

        XCTAssertNil(controller.window)
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
