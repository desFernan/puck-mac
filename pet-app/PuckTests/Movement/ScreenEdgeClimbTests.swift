//
//  ScreenEdgeClimbTests.swift
//  PuckTests
//
//  The screen's own side as a wall.
//
//  Climbing used to need a window to hold on to, and `nearestClimbTarget`
//  excludes a window whose top edge leaves the pet no headroom -- which is
//  exactly what a maximised window is. On a desktop with one of those there
//  was nothing to climb at all, so the ceiling, the crawl along it and
//  everything up there were drawn by the wander and thrown away every time.
//  Measured on a real desktop: three minutes, two draws, nothing to climb
//  either time.
//

import XCTest
@testable import Puck

final class ScreenEdgeClimbTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 500)
    /// A pet 40 wide, standing on its feet.
    private let outline = CGRect(x: -20, y: -80, width: 40, height: 80)

    private func againstEdge(_ x: CGFloat) -> Bool {
        WindowSupport.isAgainstScreenEdge(
            CGPoint(x: x, y: 400), visualBounds: outline, in: screen
        )
    }

    /// The question is asked of the outline, not of the point at the pet's
    /// feet. Containment keeps the whole drawing on screen, so the feet stop
    /// half a pet-width short of the edge and never reach it -- a test
    /// against the bare position is one that can never be true, which is what
    /// made the first version of this do nothing at all.
    func test_theEdgeIsWhereTheDrawingMeetsIt() {
        XCTAssertTrue(againstEdge(20), "feet at 20, left shoulder at 0")
        XCTAssertTrue(againstEdge(980), "feet at 980, right shoulder at 1000")
        XCTAssertFalse(againstEdge(0), "feet at 0 would be half a pet off screen")
    }

    /// Close enough counts, the same tolerance a window's edge gets: a walk
    /// lands on fractions of a pixel and would otherwise stop just shy.
    func test_closeEnoughCounts() {
        XCTAssertTrue(againstEdge(21.5))
        XCTAssertFalse(againstEdge(500))
    }

    /// A desktop with one maximised window: nothing climbable, and the screen
    /// edge is the only thing left. This is the case that made the ceiling
    /// unreachable.
    func test_withOnlyAMaximisedWindowTheEdgeIsTheOnlyWall() {
        let maximised = WindowInfo(
            windowID: 1, ownerPID: 1, ownerName: nil, title: nil, layer: 0, frame: screen
        )

        XCTAssertFalse(
            WindowSupport.hasWall(
                at: CGPoint(x: 500, y: 400), visualBounds: outline,
                in: [maximised], area: screen
            ),
            "nowhere in the middle"
        )
        XCTAssertTrue(
            WindowSupport.hasWall(
                at: CGPoint(x: 20, y: 400), visualBounds: outline,
                in: [maximised], area: screen
            ),
            "but the screen's own side is still there"
        )
    }

    /// A window's side still counts, which is what it always did.
    func test_aWindowsSideIsStillAWall() {
        let window = WindowInfo(
            windowID: 1, ownerPID: 1, ownerName: nil, title: nil, layer: 0,
            frame: CGRect(x: 300, y: 100, width: 400, height: 400)
        )

        XCTAssertTrue(WindowSupport.hasWall(
            at: CGPoint(x: 300, y: 300), visualBounds: outline, in: [window], area: screen
        ))
    }

    /// Where a pet with nothing to climb walks to: the nearer side, at its
    /// own height, and at a place it can actually stand -- aiming at the
    /// screen's own edge means aiming somewhere containment will not allow,
    /// so the walk would be clamped a step short of its target forever.
    func test_itWalksSomewhereItCanActuallyStand() {
        let left = AppDelegate.nearestScreenEdge(
            from: CGPoint(x: 200, y: 400), visualBounds: outline, in: screen
        )
        XCTAssertEqual(left, CGPoint(x: 20, y: 400))
        XCTAssertTrue(againstEdge(left.x), "and having arrived, it is against the wall")

        let right = AppDelegate.nearestScreenEdge(
            from: CGPoint(x: 900, y: 400), visualBounds: outline, in: screen
        )
        XCTAssertEqual(right, CGPoint(x: 980, y: 400))
        XCTAssertTrue(againstEdge(right.x))
    }
}
