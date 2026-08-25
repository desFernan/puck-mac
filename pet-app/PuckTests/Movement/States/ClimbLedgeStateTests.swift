//
//  ClimbLedgeStateTests.swift
//  Puck
//
//  Getting back onto the taller monitor.
//
//  The climb is in two moves on purpose -- up first, across second -- because
//  going diagonally leaves half the pet in the empty space beside the display
//  it is climbing to for the whole climb.
//

import XCTest
@testable import Puck

/// `@MainActor`: the character and its states belong to the main thread.
@MainActor
final class ClimbLedgeStateTests: XCTestCase {
    /// Standing at the right edge of the lower display, with the higher one's
    /// floor 100 above and its inside starting at x = 1050.
    private func world() -> TestStateWorld {
        let world = TestStateWorld(position: CGPoint(x: 950, y: 500))
        world.roamableAreas = [
            CGRect(x: 0, y: 0, width: 1000, height: 500),
            CGRect(x: 1000, y: 0, width: 800, height: 400),
        ]
        world.roamableArea = ScreenGround.union(world.roamableAreas)
        return world
    }

    func test_goesStraightUpBeforeGoingAcross() {
        let world = self.world()
        let state = ClimbLedgeState()
        state.target = CGPoint(x: 1050, y: 400)
        state.enter()

        world.run(state, seconds: 0.3)

        XCTAssertEqual(world.body.position.x, 950, "no sideways travel while climbing")
        XCTAssertLessThan(world.body.position.y, 500, "and it is on its way up")
    }

    func test_arrivesOnTheLedgeAndGoesIdle() {
        let world = self.world()
        let state = ClimbLedgeState()
        state.target = CGPoint(x: 1050, y: 400)
        state.enter()

        world.run(state, seconds: 5)

        XCTAssertEqual(world.body.position, CGPoint(x: 1050, y: 400))
        XCTAssertEqual(world.requestedTransitions, [.idle], "asked exactly once")
    }

    /// A ledge is a specific height. Stopping inside the arrival radius and
    /// stepping across from there leaves the pet standing that far into the
    /// side of the display it just climbed.
    func test_landsExactlyOnTheLedge_notWithinArrivalRadiusOfIt() {
        let world = self.world()
        let state = ClimbLedgeState()
        state.target = CGPoint(x: 1050, y: 400)
        state.enter()

        world.run(state, seconds: 5)

        XCTAssertEqual(world.body.position.y, 400, accuracy: 0.0001)
    }

    func test_withoutALedgeToClimb_goesIdleImmediately() {
        let world = self.world()
        let state = ClimbLedgeState()
        state.enter()

        world.run(state, seconds: 0.1)

        XCTAssertEqual(world.requestedTransitions.first, .idle)
        XCTAssertEqual(world.body.position, CGPoint(x: 950, y: 500), "and stays where it was")
    }

    /// Cleared on the way out, or the next climb replays this one.
    func test_forgetsTheLedgeOnExit() {
        let state = ClimbLedgeState()
        state.target = CGPoint(x: 1050, y: 400)

        state.exit()

        XCTAssertNil(state.target)
    }
}
