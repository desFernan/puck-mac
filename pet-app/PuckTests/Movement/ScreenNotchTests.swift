//
//  ScreenNotchTests.swift
//  PuckTests
//
//  The camera housing as something in the pet's way -- tested on a machine
//  that has none, which is the whole reason the geometry is pure.
//

import XCTest
@testable import Puck

final class ScreenNotchTests: XCTestCase {
    /// A 16" MacBook Pro's numbers, in AppKit's space: the screen is
    /// 3456x2234, the menu bar beside the notch is 37pt tall, and the notch
    /// is the gap left between the two strips.
    private let screen = CGRect(x: 0, y: 0, width: 3456, height: 2234)
    private var left: CGRect { CGRect(x: 0, y: 2197, width: 1493, height: 37) }
    private var right: CGRect { CGRect(x: 1963, y: 2197, width: 1493, height: 37) }

    // MARK: - Reading it off the screen

    func test_theNotchIsTheGapBetweenTheTwoStrips() throws {
        let notch = try XCTUnwrap(ScreenNotch.appKitRect(
            inScreenFrame: screen,
            auxiliaryTopLeft: left,
            auxiliaryTopRight: right
        ))

        XCTAssertEqual(notch.minX, 1493)
        XCTAssertEqual(notch.maxX, 1963)
        XCTAssertEqual(notch.height, 37, "as tall as the strips beside it")
        XCTAssertEqual(notch.maxY, screen.maxY, "and its top is the screen's")
    }

    /// A display with no notch reports neither strip, and must produce
    /// nothing rather than a rectangle spanning the whole screen.
    func test_aScreenWithNoNotchHasNone() {
        XCTAssertNil(ScreenNotch.appKitRect(inScreenFrame: screen, auxiliaryTopLeft: nil, auxiliaryTopRight: nil))
        XCTAssertNil(ScreenNotch.appKitRect(inScreenFrame: screen, auxiliaryTopLeft: left, auxiliaryTopRight: nil))
        XCTAssertNil(ScreenNotch.appKitRect(inScreenFrame: screen, auxiliaryTopLeft: nil, auxiliaryTopRight: right))
    }

    /// Strips that meet, or arrive the other way round on an arrangement
    /// nobody anticipated, are not a notch. A negative width would be a
    /// rectangle the pet then tries to walk around.
    func test_anImpossibleGapIsNotANotch() {
        let touching = CGRect(x: 1493, y: 2197, width: 1493, height: 37)
        XCTAssertNil(ScreenNotch.appKitRect(inScreenFrame: screen, auxiliaryTopLeft: left, auxiliaryTopRight: touching))
        XCTAssertNil(ScreenNotch.appKitRect(inScreenFrame: screen, auxiliaryTopLeft: right, auxiliaryTopRight: left))
    }

    // MARK: - What it does to the ceiling

    /// In the pet's space: y grows downward, so the notch hangs from y=0 and
    /// its bottom edge is the larger number.
    private let notch = ScreenNotch(rect: CGRect(x: 1493, y: 0, width: 470, height: 37))

    func test_awayFromTheNotchTheCeilingIsTheScreensOwn() {
        XCTAssertEqual(notch.ceiling(atX: 100, areaTop: 0), 0)
        XCTAssertEqual(notch.ceiling(atX: 3400, areaTop: 0), 0)
    }

    func test_underTheNotchTheCeilingIsItsBottomEdge() {
        XCTAssertEqual(notch.ceiling(atX: 1700, areaTop: 0), 37)
    }

    /// Its own sides count as under it: a ceiling that changed only strictly
    /// inside would let the pet clip the corner.
    func test_theNotchsOwnEdgesAreUnderIt() {
        XCTAssertEqual(notch.ceiling(atX: 1493, areaTop: 0), 37)
        XCTAssertEqual(notch.ceiling(atX: 1963, areaTop: 0), 37)
    }

    /// The ordinary case, and the reason this is usually invisible: with the
    /// menu bar there, the pet's own ceiling is already below the notch, and
    /// the notch must not raise it back up.
    func test_aCeilingAlreadyBelowTheNotchIsLeftAlone() {
        XCTAssertEqual(notch.ceiling(atX: 1700, areaTop: 37), 37)
        XCTAssertEqual(notch.ceiling(atX: 1700, areaTop: 60), 60, "never above the area's own top")
    }

    // MARK: - Whether the pet clears it

    /// A pet's outline, standing on its feet: 40 wide, 80 tall.
    private let outline = CGRect(x: -20, y: -80, width: 40, height: 80)

    func test_aPetWellClearOfTheNotchClearsIt() {
        XCTAssertTrue(notch.clears(CGPoint(x: 400, y: 80), visualBounds: outline, areaTop: 0))
    }

    /// Its head, not its feet: the pet hangs upside down from the ceiling, so
    /// what meets the camera housing is the top of the drawing.
    func test_aPetWhoseHeadIsInsideTheNotchDoesNot() {
        XCTAssertFalse(notch.clears(CGPoint(x: 1700, y: 100), visualBounds: outline, areaTop: 0))
        XCTAssertTrue(notch.clears(CGPoint(x: 1700, y: 117), visualBounds: outline, areaTop: 0))
    }

    /// Half a pet behind the camera housing is as wrong as all of it, so the
    /// question is asked of the outline's edges rather than its middle.
    func test_aPetHalfwayUnderTheNotchDoesNotClearIt() {
        // Feet at the notch's left edge: its middle is clear, its right
        // shoulder is not.
        XCTAssertFalse(notch.clears(CGPoint(x: 1483, y: 100), visualBounds: outline, areaTop: 0))
    }
}
