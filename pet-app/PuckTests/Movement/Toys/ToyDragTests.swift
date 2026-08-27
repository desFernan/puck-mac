//
//  ToyDragTests.swift
//  PuckTests
//
//  Picking a toy up and putting it back down.
//

import XCTest
@testable import Puck

final class ToyDragTests: XCTestCase {
    /// The point that was grabbed stays under the cursor. Snapping the toy's
    /// own origin to the pointer instead makes it jump the moment it is
    /// picked up, which reads as the physics going wrong rather than as a
    /// subtraction going wrong.
    func test_whateverWasGrabbedStaysUnderTheCursor() {
        var drag = ToyDrag()
        let toy = CGPoint(x: 100, y: 200)
        let grabbedAt = CGPoint(x: 130, y: 190)

        drag.begin(at: grabbedAt, toyPosition: toy, now: 0)
        let moved = drag.move(to: CGPoint(x: 400, y: 500), now: 0.1)

        XCTAssertEqual(moved.x, 370, "the toy keeps the 30pt it was held to the left of")
        XCTAssertEqual(moved.y, 510)
    }

    /// A toy with nowhere to be yet is grabbed by its own origin, so it
    /// arrives under the cursor rather than at some offset from it.
    func test_aToyWithNoPositionIsGrabbedByItsOrigin() {
        var drag = ToyDrag()

        drag.begin(at: CGPoint(x: 130, y: 190), toyPosition: nil, now: 0)

        XCTAssertEqual(drag.grabOffset, .zero)
        XCTAssertEqual(drag.move(to: CGPoint(x: 400, y: 500), now: 0.1), CGPoint(x: 400, y: 500))
    }

    /// Letting go of a still cursor is a plain drop, not a throw.
    func test_aStillCursorReleasesAtRest() {
        var drag = ToyDrag()

        drag.begin(at: CGPoint(x: 10, y: 10), toyPosition: CGPoint(x: 10, y: 10), now: 0)
        _ = drag.move(to: CGPoint(x: 10, y: 10), now: 0.1)

        XCTAssertEqual(drag.releaseVelocity, .zero)
    }

    /// Mouse events do not arrive on a clock, and the first one after the
    /// grab has no interval of its own. Dividing by that gap is how a throw
    /// comes out infinite.
    func test_theFirstMoveAfterAGrabReportsNoSpeedRatherThanInfinite() {
        var drag = ToyDrag()

        drag.begin(at: .zero, toyPosition: .zero, now: 5)
        _ = drag.move(to: CGPoint(x: 300, y: 0), now: 5)

        XCTAssertTrue(drag.releaseVelocity.x.isFinite, "got \(drag.releaseVelocity)")
        XCTAssertTrue(drag.releaseVelocity.y.isFinite)
    }

    /// A second pickup does not inherit the first one's speed.
    func test_aFreshGrabForgetsTheLastThrow() {
        var drag = ToyDrag()

        drag.begin(at: .zero, toyPosition: .zero, now: 0)
        // Two moves: the first after a grab is the one that has no interval
        // to measure against, so it is the second that builds any speed.
        _ = drag.move(to: CGPoint(x: 100, y: 0), now: 0.05)
        _ = drag.move(to: CGPoint(x: 500, y: 0), now: 0.10)
        XCTAssertNotEqual(drag.releaseVelocity, .zero, "the setup has to actually build up speed")

        drag.begin(at: .zero, toyPosition: .zero, now: 1)

        XCTAssertEqual(drag.releaseVelocity, .zero)
    }
}
