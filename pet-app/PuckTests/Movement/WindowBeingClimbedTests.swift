//
//  WindowBeingClimbedTests.swift
//  PuckTests
//
//  The wall a climb holds on to. Asked again on every frame of a climb, so
//  what it accepts is what the pet is seen going up.
//

import XCTest
@testable import Puck

final class WindowBeingClimbedTests: XCTestCase {
    private func window(_ id: CGWindowID, _ frame: CGRect) -> WindowInfo {
        WindowInfo(windowID: id, ownerPID: 1, ownerName: nil, title: nil, layer: 0, frame: frame)
    }

    /// The plain case: the pet is against the left edge of the only window.
    func testTheEdgeOfTheOnlyWindowIsAWall() {
        let front = window(1, CGRect(x: 300, y: 100, width: 400, height: 600))

        XCTAssertEqual(
            WindowSupport.windowBeingClimbed(at: CGPoint(x: 300, y: 500), in: [front])?.windowID,
            1
        )
    }

    /// The bug. Four windows sharing the screen's own edges are four stacked
    /// walls at x = 0, and only the front one is drawn -- so a climb up any
    /// of the others goes up a line with nothing on it.
    func testAnEdgeHiddenBehindAWindowInFrontIsNotAWall() {
        let front = window(1, CGRect(x: 0, y: 0, width: 1000, height: 800))
        let behind = window(2, CGRect(x: 400, y: 100, width: 300, height: 600))

        XCTAssertNil(
            WindowSupport.windowBeingClimbed(at: CGPoint(x: 400, y: 500), in: [front, behind]),
            "the covered window's edge is not something to hold on to"
        )
    }

    /// Same two windows, at a height the front one does not reach: the edge
    /// is on screen there, so it is a wall again.
    func testTheSameEdgeIsAWallWhereNothingCoversIt() {
        let front = window(1, CGRect(x: 0, y: 0, width: 1000, height: 300))
        let behind = window(2, CGRect(x: 400, y: 100, width: 300, height: 600))

        XCTAssertEqual(
            WindowSupport.windowBeingClimbed(at: CGPoint(x: 400, y: 500), in: [front, behind])?.windowID,
            2
        )
    }

    /// "포커스된 창 위로는 올라가지 않기" has to hold for the whole climb, not
    /// only for the step that starts it -- a wall the pet may not climb is
    /// not a wall it may keep climbing either.
    func testAnExcludedWindowIsNotAWall() {
        let focused = window(1, CGRect(x: 300, y: 100, width: 400, height: 600))

        XCTAssertNil(
            WindowSupport.windowBeingClimbed(at: CGPoint(x: 300, y: 500), in: [focused], excluding: [1])
        )
    }

    /// Above or below the window there is no edge to hold, whatever the x.
    func testNothingToHoldAboveOrBelowTheWindow() {
        let only = window(1, CGRect(x: 300, y: 100, width: 400, height: 600))

        XCTAssertNil(WindowSupport.windowBeingClimbed(at: CGPoint(x: 300, y: 50), in: [only]))
        XCTAssertNil(WindowSupport.windowBeingClimbed(at: CGPoint(x: 300, y: 900), in: [only]))
    }

    /// The right edge counts too, and the covering rule applies to whichever
    /// edge the pet is actually holding: the front window here covers the
    /// window's left edge but stops short of its right one.
    func testTheVisibleEdgeIsTheOneThePetIsHolding() {
        let front = window(1, CGRect(x: 0, y: 0, width: 500, height: 800))
        let behind = window(2, CGRect(x: 400, y: 100, width: 300, height: 600))

        XCTAssertNil(
            WindowSupport.windowBeingClimbed(at: CGPoint(x: 400, y: 500), in: [front, behind]),
            "left edge is under the front window"
        )
        XCTAssertEqual(
            WindowSupport.windowBeingClimbed(at: CGPoint(x: 700, y: 500), in: [front, behind])?.windowID,
            2,
            "right edge is out in the open"
        )
    }
}
