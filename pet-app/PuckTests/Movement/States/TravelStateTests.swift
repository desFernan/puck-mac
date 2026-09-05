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

    // MARK: - A second trip ordered while one is in the air

    /// The reported fault: the pet got smaller every time the window was
    /// alt-tabbed away from quickly.
    ///
    /// Ordering a second trip means transitioning into this state again, and
    /// re-entry is exit-then-enter -- so `exit()` cleared the route and the
    /// callbacks the caller had just installed. The trip was dropped before
    /// its first frame: no progress, no arrival. The size is carried on those
    /// callbacks, so the pet froze part-way between the desktop's size and
    /// the island's, and the next trip home wrote that half-size down as the
    /// size to come back out at.
    func test_aTripOrderedWhileOneIsInTheAirStillRuns() {
        let world = TestStateWorld()
        let state = TravelState()
        state.duration = 0.1
        var firstArrived = false
        state.order(from: .zero, to: CGPoint(x: 100, y: 0), onProgress: { _ in }, onArrival: { firstArrived = true })
        state.enter()
        state.update(dt: 0.03, context: world.context)

        // 두 번째 여행: 실제 앱에서는 transition(to:)가 exit -> enter를 부른다.
        var reported: [Double] = []
        var secondArrived = false
        state.order(
            from: CGPoint(x: 40, y: 0),
            to: CGPoint(x: 900, y: 0),
            onProgress: { reported.append($0) },
            onArrival: { secondArrived = true }
        )
        state.exit()
        state.enter()

        state.update(dt: 5, context: world.context)

        XCTAssertEqual(reported.last, 1, "the second trip never ran")
        XCTAssertTrue(secondArrived, "the second trip never arrived")
        XCTAssertFalse(firstArrived, "the trip it replaced must not also arrive")
        XCTAssertEqual(world.body.position.x, 900, accuracy: 0.001)
    }

    /// And the size lands exactly where it was heading, which is the whole
    /// reason the drift compounded: a trip that stops short leaves the pet at
    /// a size nothing put it at.
    func test_aRestartedTripStillEndsAtItsFullProgress() {
        let world = TestStateWorld()
        let state = TravelState()
        state.duration = 0.1
        var scale = 1.0
        let departing = 1.0
        let target = 0.14
        state.order(from: .zero, to: CGPoint(x: 10, y: 0), onProgress: { _ in }, onArrival: {})
        state.enter()
        state.update(dt: 0.04, context: world.context)

        state.order(
            from: .zero,
            to: CGPoint(x: 10, y: 0),
            onProgress: { progress in scale = departing + (target - departing) * progress },
            onArrival: {}
        )
        state.exit()
        state.enter()
        state.update(dt: 5, context: world.context)

        XCTAssertEqual(scale, target, accuracy: 0.0001, "the pet has to land at the size it was heading for")
    }

    /// A trip that has completed is not put back by a later entry -- that is
    /// the stale replay `exit()` was clearing for in the first place.
    func test_aCompletedTripIsNotReplayedByALaterEntry() {
        let world = TestStateWorld()
        let state = TravelState()
        state.duration = 0.1
        var arrivals = 0
        state.order(from: .zero, to: CGPoint(x: 10, y: 0), onProgress: { _ in }, onArrival: { arrivals += 1 })
        state.enter()
        state.update(dt: 5, context: world.context)
        XCTAssertEqual(arrivals, 1)

        state.exit()
        state.enter()
        state.update(dt: 5, context: world.context)

        XCTAssertEqual(arrivals, 1, "a finished trip must not run again")
        XCTAssertNil(state.origin)
    }

    /// Retargeting keeps the trip: the island moves when its window does, and
    /// a pet on its way to it should arrive where the island now is without
    /// starting over.
    func test_retargetingKeepsTheTripAndSurvivesARestart() {
        let world = TestStateWorld()
        let state = TravelState()
        state.duration = 0.1
        var arrivedAt: CGPoint?
        state.order(from: .zero, to: CGPoint(x: 100, y: 0), onProgress: { _ in }, onArrival: {})
        state.enter()
        state.update(dt: 0.03, context: world.context)

        state.retarget(to: CGPoint(x: 500, y: 0)) { arrivedAt = CGPoint(x: 500, y: 0) }
        // 창이 다시 움직여 상태를 다시 들어가도 새 목적지가 남아 있어야 한다.
        state.exit()
        state.enter()
        state.update(dt: 5, context: world.context)

        XCTAssertEqual(arrivedAt, CGPoint(x: 500, y: 0))
        XCTAssertEqual(world.body.position.x, 500, accuracy: 0.001)
    }
}
