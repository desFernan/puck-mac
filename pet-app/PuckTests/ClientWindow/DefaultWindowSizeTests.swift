//
//  DefaultWindowSizeTests.swift
//  PuckTests
//
//  How big the chat window opens, on screens this machine does not have.
//

import XCTest
@testable import Puck

final class DefaultWindowSizeTests: XCTestCase {
    private let floor = CGSize(
        width: ClientTheme.Metrics.windowMinWidth,
        height: ClientTheme.Metrics.windowMinHeight
    )

    /// The reported fault: the window opens smaller than what it holds. Five
    /// things across at 1440 meant the conversation, the code column and the
    /// file list were all at a minimum at once.
    func test_aBigScreenGetsTheSizeTheLayoutWants() {
        let size = DefaultWindowSize.size(
            forVisibleFrame: CGSize(width: 3_440, height: 1_415),
            minimum: floor
        )

        XCTAssertEqual(size, DefaultWindowSize.preferred)
        XCTAssertGreaterThan(size.width, ClientTheme.Metrics.windowMinWidthWithCode,
                             "everything open at once has to fit without any of it at its floor")
    }

    /// And not the whole screen with it: this window sits beside what you are
    /// working on, and the pet walks out of it onto the desktop.
    func test_theWindowNeverFillsTheScreen() {
        let screen = CGSize(width: 3_440, height: 1_415)

        let size = DefaultWindowSize.size(forVisibleFrame: screen, minimum: floor)

        XCTAssertLessThan(size.width, screen.width)
        XCTAssertLessThan(size.height, screen.height)
    }

    /// A laptop is the case the fixed number was actually chosen for, and it
    /// still has to fit: 1760 does not go on a 13-inch screen.
    func test_aLaptopScreenGetsWhatItCanSpare() {
        let screen = CGSize(width: 1_512, height: 900)

        let size = DefaultWindowSize.size(forVisibleFrame: screen, minimum: floor)

        XCTAssertLessThanOrEqual(size.width, screen.width * DefaultWindowSize.maximumScreenFraction)
        XCTAssertLessThanOrEqual(size.height, screen.height * DefaultWindowSize.maximumScreenFraction)
        XCTAssertGreaterThanOrEqual(size.width, floor.width)
    }

    /// The floor wins last. A screen too small for it gets it anyway --
    /// under the floor the panes do not compress, they overflow.
    func test_theFloorIsHonouredOnAScreenTooSmallForIt() {
        let size = DefaultWindowSize.size(
            forVisibleFrame: CGSize(width: 400, height: 300),
            minimum: floor
        )

        XCTAssertEqual(size, floor)
    }

    /// A screen that reports nothing -- no `NSScreen.main`, which happens
    /// before a display is attached -- must still open a usable window rather
    /// than one of zero size.
    func test_noScreenAtAllStillOpensSomething() {
        let size = DefaultWindowSize.size(forVisibleFrame: .zero, minimum: floor)

        XCTAssertEqual(size, floor)
    }
}
