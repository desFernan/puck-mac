//
//  TravelStateTests.swift
//  Puck
//
//  Being carried between the desktop and the tank. The move used to be a cut;
//  these hold the line that it is a movement.
//

import XCTest
@testable import Puck

/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class TravelStateTests: XCTestCase {
    func test_easingStartsAndEndsAtRest() {
        XCTAssertEqual(TravelState.eased(0), 0, accuracy: 0.0001)
        XCTAssertEqual(TravelState.eased(1), 1, accuracy: 0.0001)
        XCTAssertEqual(TravelState.eased(0.5), 0.5, accuracy: 0.0001)
        // Slower than linear at the ends, faster in the middle: that is what
        // reads as being picked up and set down.
        XCTAssertLessThan(TravelState.eased(0.15), 0.15)
        XCTAssertGreaterThan(TravelState.eased(0.85), 0.85)
    }

    func test_easingIsClampedOutsideItsRange() {
        XCTAssertEqual(TravelState.eased(-1), 0, accuracy: 0.0001)
        XCTAssertEqual(TravelState.eased(2), 1, accuracy: 0.0001)
    }

    /// The whole point: the pet is somewhere between the two ends partway
    /// through, rather than at one end and then the other.
    func test_thePetIsInBetweenPartwayThrough() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 400))
        world.roamableArea = CGRect(x: 0, y: 0, width: 2000, height: 1000)
        let state = TravelState()
        state.origin = CGPoint(x: 100, y: 400)
        state.destination = CGPoint(x: 1100, y: 100)
        state.duration = 1
        state.enter()

        state.update(dt: 0.5, context: world.context)

        XCTAssertGreaterThan(world.body.position.x, 100)
        XCTAssertLessThan(world.body.position.x, 1100)
        XCTAssertLessThan(world.body.position.y, 400)
        XCTAssertGreaterThan(world.body.position.y, 100)
    }

    func test_landsAtTheDestinationAndAsksToLand() {
        let world = TestStateWorld()
        let state = TravelState()
        state.origin = .zero
        state.destination = CGPoint(x: 500, y: 300)
        state.duration = 0.2
        state.enter()

        state.update(dt: 0.3, context: world.context)

        XCTAssertEqual(world.body.position, CGPoint(x: 500, y: 300))
        XCTAssertEqual(world.requestedTransitions, [.land])
    }

    /// The caller puts `roamableArea` back through this, and it has to happen
    /// before anything else runs -- the area is widened for the trip, and a
    /// frame spent in the widened one would let the pet stand outside its
    /// world.
    func test_arrivalRunsBeforeTheTransitionIsRequested() {
        let world = TestStateWorld()
        let state = TravelState()
        var arrivedBeforeTransition = false
        state.origin = .zero
        state.destination = CGPoint(x: 10, y: 10)
        state.duration = 0.1
        state.onArrival = { arrivedBeforeTransition = world.requestedTransitions.isEmpty }
        state.enter()

        state.update(dt: 0.2, context: world.context)

        XCTAssertTrue(arrivedBeforeTransition)
        XCTAssertEqual(world.requestedTransitions, [.land])
    }

    /// Fires once however many frames follow, so a slow frame after arrival
    /// cannot request a second landing.
    func test_arrivalHappensOnlyOnce() {
        let world = TestStateWorld()
        let state = TravelState()
        var arrivals = 0
        state.origin = .zero
        state.destination = CGPoint(x: 10, y: 10)
        state.duration = 0.1
        state.onArrival = { arrivals += 1 }
        state.enter()

        state.update(dt: 0.2, context: world.context)
        state.update(dt: 0.2, context: world.context)

        XCTAssertEqual(arrivals, 1)
    }

    /// A trip with nowhere to go still ends, rather than leaving the pet
    /// mid-air in a state nothing will move it out of.
    func test_aTripWithNoDestinationStillLands() {
        let world = TestStateWorld()
        let state = TravelState()
        state.enter()

        state.update(dt: 0.1, context: world.context)

        XCTAssertEqual(world.requestedTransitions, [.land])
    }

    /// Cleared on exit, so the next trip cannot replay the last one's route.
    func test_exitForgetsTheRoute() {
        let state = TravelState()
        state.origin = .zero
        state.destination = CGPoint(x: 1, y: 1)
        state.onArrival = {}
        state.exit()

        XCTAssertNil(state.origin)
        XCTAssertNil(state.destination)
        XCTAssertNil(state.onArrival)
    }

    /// The pet shrinks into the island on the way rather than on landing.
    /// Reported on the eased curve, so the size and the position stay
    /// together the whole trip.
    func test_progressIsReportedOnTheSameCurveAsTheMove() {
        let world = TestStateWorld()
        let state = TravelState()
        var reported: [Double] = []
        state.origin = .zero
        state.destination = CGPoint(x: 100, y: 0)
        state.duration = 1
        state.onProgress = { reported.append($0) }
        state.enter()

        state.update(dt: 0.25, context: world.context)
        state.update(dt: 0.25, context: world.context)

        XCTAssertEqual(reported.count, 2)
        XCTAssertEqual(reported.last ?? 0, TravelState.eased(0.5), accuracy: 0.0001)
        XCTAssertEqual(
            world.body.position.x,
            100 * TravelState.eased(0.5),
            accuracy: 0.5,
            "the size follows the same curve as the position, not a second one"
        )
    }

    /// A trip that arrives inside one long frame still ends at full size --
    /// the last report is the end of the curve, not wherever the frame landed.
    func test_theFinalProgressIsAlwaysTheEndOfTheCurve() {
        let world = TestStateWorld()
        let state = TravelState()
        var reported: [Double] = []
        state.origin = .zero
        state.destination = CGPoint(x: 10, y: 0)
        state.duration = 0.1
        state.onProgress = { reported.append($0) }
        state.enter()

        state.update(dt: 5, context: world.context)

        XCTAssertEqual(reported.last, 1)
    }

    func test_exitForgetsTheProgressHandler() {
        let state = TravelState()
        state.onProgress = { _ in }
        state.exit()
        XCTAssertNil(state.onProgress)
    }
}
