//
//  BallPhysicsTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Pure physics for the ball-toy interaction (F12, optional).
//  Drop reuses MovementSolver.fallStep's free-fall math directly; the kicked
//  fling is this file's one bit of new arithmetic.
//

import XCTest
@testable import Puck

final class BallPhysicsTests: XCTestCase {
    private let roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 600)

    // MARK: - falling

    func test_falling_movesTowardLandingY() {
        let state = BallState(position: CGPoint(x: 100, y: 0), phase: .falling)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertGreaterThan(next.position.y, state.position.y)
        XCTAssertEqual(next.phase, .falling)
    }

    func test_falling_landsAndBecomesResting_onceItReachesLandingY() {
        let state = BallState(position: CGPoint(x: 100, y: 499), verticalVelocity: 1000, phase: .falling)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertEqual(next.position.y, 500)
        XCTAssertEqual(next.phase, .resting)
        XCTAssertEqual(next.verticalVelocity, 0)
    }

    // MARK: - resting

    func test_resting_isANoOp() {
        let state = BallState(position: CGPoint(x: 100, y: 500), phase: .resting)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertEqual(next, state)
    }

    // MARK: - kick(_:direction:)

    func test_kick_facingRight_launchesRightAndUpward() {
        let resting = BallState(position: CGPoint(x: 100, y: 500), phase: .resting)

        let kicked = BallPhysics.kick(resting, direction: .right)

        XCTAssertEqual(kicked.phase, .kicked)
        XCTAssertGreaterThan(kicked.horizontalVelocity, 0)
        XCTAssertLessThan(kicked.verticalVelocity, 0) // negative = upward (Y increases downward)
        XCTAssertEqual(kicked.kickedElapsed, 0)
    }

    func test_kick_facingLeft_launchesLeft() {
        let resting = BallState(position: CGPoint(x: 100, y: 500), phase: .resting)

        let kicked = BallPhysics.kick(resting, direction: .left)

        XCTAssertLessThan(kicked.horizontalVelocity, 0)
    }

    // MARK: - juggle(_:) (F12 juggle-before-kick variety, 2026-07-29)

    /// A small
    /// vertical pop that falls back down and rests again, reusing the exact
    /// same .falling->.resting arc a drop already takes (an upward initial
    /// velocity decelerates under gravity, peaks, then falls back down).
    func test_juggle_popsUpward_thenFallsBackViaTheExistingFallingPhase() {
        let resting = BallState(position: CGPoint(x: 100, y: 500), phase: .resting)

        let juggled = BallPhysics.juggle(resting)

        XCTAssertEqual(juggled.phase, .falling)
        XCTAssertLessThan(juggled.verticalVelocity, 0) // negative = upward
        XCTAssertEqual(juggled.horizontalVelocity, 0, "a juggle pop is straight up, not off to the side")
    }

    func test_juggle_isWeakerThanAKick() {
        let resting = BallState(position: CGPoint(x: 100, y: 500), phase: .resting)

        let juggled = BallPhysics.juggle(resting)
        let kicked = BallPhysics.kick(resting, direction: .right)

        XCTAssertGreaterThan(juggled.verticalVelocity, kicked.verticalVelocity, "less negative = a smaller pop than a full kick")
    }

    // MARK: - kicked

    func test_kicked_movesByBothVelocitiesAndApplesGravity() {
        let state = BallState(position: CGPoint(x: 100, y: 500), verticalVelocity: -400, horizontalVelocity: 260, phase: .kicked)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertEqual(next.position.x, 100 + 26, accuracy: 0.001) // 260 * 0.1
        // y moves by (updated velocity) * dt, not the old velocity -- confirms gravity was applied first.
        let expectedVelocity = -400 + MovementSolver.gravity * 0.1
        XCTAssertEqual(next.verticalVelocity, expectedVelocity, accuracy: 0.001)
        XCTAssertEqual(next.position.y, 500 + expectedVelocity * 0.1, accuracy: 0.001)
    }

    func test_kicked_accumulatesElapsedTime() {
        let state = BallState(position: .zero, horizontalVelocity: 100, phase: .kicked, kickedElapsed: 0.2)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertEqual(next.kickedElapsed, 0.3, accuracy: 0.0001)
    }

    /// The sides, the top and the floor now all hold a kicked toy in, so this
    /// backstop only fires when there is no surface under it at all.
    func test_kicked_becomesGone_whenThereIsNothingBelowToLandOn() {
        let state = BallState(position: CGPoint(x: 500, y: 1400), verticalVelocity: 1000, phase: .kicked)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 99_999, roamableArea: roamableArea)

        XCTAssertEqual(next.phase, .gone)
    }

    // MARK: - A kicked toy comes back to rest

    func test_kicked_bouncesOffTheFloorInsteadOfFallingThroughIt() {
        let floor = roamableArea.maxY
        // Already at the floor, heading down hard.
        let state = BallState(position: CGPoint(x: 500, y: floor), verticalVelocity: 800, phase: .kicked)

        let next = BallPhysics.step(state, dt: 0.01, landingY: floor, roamableArea: roamableArea)

        XCTAssertEqual(next.phase, .kicked, "still bouncing")
        XCTAssertLessThan(next.verticalVelocity, 0, "heading back up")
        XCTAssertLessThanOrEqual(next.position.y, floor, "never below the surface")
    }

    /// An ordinary kick settles back into play rather than disappearing, so
    /// the pet can chase it again.
    func test_anOrdinaryKickSettlesBackToResting() {
        let floor = roamableArea.maxY
        var state = BallPhysics.kick(
            BallState(position: CGPoint(x: 500, y: floor), phase: .resting),
            direction: .right
        )

        for _ in 0..<600 where state.phase == .kicked || state.phase == .rolling {
            state = BallPhysics.step(state, dt: 1.0 / 60, landingY: floor, roamableArea: roamableArea)
            XCTAssertLessThanOrEqual(state.position.y, floor + 0.01, "fell through the floor")
        }

        XCTAssertEqual(state.phase, .resting)
        XCTAssertEqual(state.position.y, floor, accuracy: 0.01, "resting on the surface")
    }

    /// Even a bonk off the pet's head leaves the toy in play now -- it
    /// bounces away and settles rather than disappearing.
    func test_noKickEverEndsInTheToyDisappearing() {
        let floor = roamableArea.maxY
        var state = BallPhysics.kick(
            BallState(position: CGPoint(x: 500, y: floor), phase: .resting),
            direction: .right
        )

        for _ in 0..<600 where state.phase == .kicked || state.phase == .rolling {
            state = BallPhysics.step(state, dt: 1.0 / 60, landingY: floor, roamableArea: roamableArea)
        }

        XCTAssertEqual(state.phase, .resting)
    }

    // MARK: - Screen edges (the toy bounces off the screen bounds like the pet does)

    func test_kicked_bouncesOffTheSideInsteadOfLeaving() {
        // Heading right, already past the right edge of a 1000-wide area.
        let state = BallState(position: CGPoint(x: 1010, y: 300), horizontalVelocity: 1000, phase: .kicked)

        let next = BallPhysics.step(state, dt: 0.01, landingY: 900, roamableArea: roamableArea)

        XCTAssertEqual(next.phase, .kicked, "still in play")
        XCTAssertLessThan(next.horizontalVelocity, 0, "heading back the other way")
        XCTAssertLessThanOrEqual(next.position.x, 1000, "back inside the screen")
    }

    func test_kicked_bouncesOffTheCeiling() {
        // Travelling upward (negative Y) above the top of the area.
        let state = BallState(position: CGPoint(x: 500, y: -10), verticalVelocity: -1000, phase: .kicked)

        let next = BallPhysics.step(state, dt: 0.01, landingY: 900, roamableArea: roamableArea)

        XCTAssertEqual(next.phase, .kicked)
        XCTAssertGreaterThan(next.verticalVelocity, 0, "now coming back down")
        XCTAssertGreaterThanOrEqual(next.position.y, 0)
    }

    /// A hard kick must not tunnel out through a corner over many frames.
    func test_kicked_neverLeavesTheScreenSideways() {
        var state = BallState(position: CGPoint(x: 900, y: 300), horizontalVelocity: 4000, phase: .kicked)

        for _ in 0..<60 where state.phase == .kicked {
            state = BallPhysics.step(state, dt: 1.0 / 60, landingY: 5000, roamableArea: roamableArea)
            XCTAssertGreaterThanOrEqual(state.position.x, 0, "left the screen on the left")
            XCTAssertLessThanOrEqual(state.position.x, 1000, "left the screen on the right")
        }
    }

    /// The toy's own outline decides where the wall is, exactly like the pet's.
    func test_kicked_bouncesOnItsArtworkNotItsCentre() {
        let outline = CGRect(x: -20, y: -20, width: 40, height: 40)
        // Centre still inside, but the artwork's right edge is past the wall.
        let state = BallState(position: CGPoint(x: 990, y: 300), horizontalVelocity: 1000, phase: .kicked)

        let next = BallPhysics.step(
            state, dt: 0.01, landingY: 900, roamableArea: roamableArea, visualBounds: outline
        )

        XCTAssertLessThan(next.horizontalVelocity, 0, "a 40pt-wide toy is already touching the wall")
    }

    /// A falling toy dropped near the edge is held inside too.
    func test_falling_isContainedWithinTheScreen() {
        let outline = CGRect(x: -20, y: -20, width: 40, height: 40)
        let state = BallState(position: CGPoint(x: 1200, y: 100), phase: .falling)

        let next = BallPhysics.step(
            state, dt: 0.01, landingY: 900, roamableArea: roamableArea, visualBounds: outline
        )

        XCTAssertEqual(next.position.x, 980, accuracy: 0.01, "held at the wall by its own edge")
    }

    // MARK: - gone

    func test_gone_isANoOp() {
        let state = BallState(position: CGPoint(x: 100, y: 500), phase: .gone)

        let next = BallPhysics.step(state, dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertEqual(next, state)
    }
}

/// A toy that has landed still has to notice when what it landed on goes
/// away, rather than floating in place.
final class BallRestingSurfaceTests: XCTestCase {
    private let roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func test_aRestingToyStaysPutWhileItsSurfaceIsThere() {
        let state = BallState(position: CGPoint(x: 500, y: 400), phase: .resting)

        let next = BallPhysics.step(state, dt: 1.0 / 60, landingY: 400, roamableArea: roamableArea)

        XCTAssertEqual(next.phase, .resting)
        XCTAssertEqual(next.position, state.position)
    }

    /// The pet walks out from under it: the floor is now much further down.
    func test_aRestingToyFallsOnceItsSurfaceGoesAway() {
        let state = BallState(position: CGPoint(x: 500, y: 400), phase: .resting)

        let next = BallPhysics.step(state, dt: 1.0 / 60, landingY: 560, roamableArea: roamableArea)

        XCTAssertEqual(next.phase, .falling, "left floating in mid-air")
    }

    /// ...and then actually lands on whatever was underneath.
    func test_aToyLeftInMidAirLandsOnTheFloorBelow() {
        var state = BallState(position: CGPoint(x: 500, y: 400), phase: .resting)

        // Not `where state.phase != .resting` -- it starts resting, which
        // would skip every iteration and test nothing.
        for _ in 0..<600 {
            state = BallPhysics.step(state, dt: 1.0 / 60, landingY: 560, roamableArea: roamableArea)
        }

        XCTAssertEqual(state.phase, .resting)
        XCTAssertEqual(state.position.y, 560, accuracy: 0.01)
    }

    /// A toy that has just settled must not immediately decide it's floating
    /// -- landing leaves it a rounding error away from its surface.
    func test_aToyThatJustSettledDoesNotImmediatelyRefall() {
        let state = BallState(position: CGPoint(x: 500, y: 400 - 0.2), phase: .resting)

        let next = BallPhysics.step(state, dt: 1.0 / 60, landingY: 400, roamableArea: roamableArea)

        XCTAssertEqual(next.phase, .resting)
    }

    /// Something can also appear underneath it -- a window opening below a
    /// toy is not a reason to launch it upward.
    func test_aSurfaceRisingUnderneathDoesNotMoveIt() {
        let state = BallState(position: CGPoint(x: 500, y: 400), phase: .resting)

        let next = BallPhysics.step(state, dt: 1.0 / 60, landingY: 300, roamableArea: roamableArea)

        XCTAssertEqual(next.phase, .resting)
        XCTAssertEqual(next.position, state.position)
    }
    // MARK: - Rolling

    /// What a kick used to do at the end of its last bounce: stop dead, in
    /// one frame, with sideways speed still on it. Now it rolls that speed
    /// off along the surface.
    func test_aKickEndsByRollingRatherThanStoppingDead() {
        let floor = roamableArea.maxY
        var state = BallPhysics.kick(
            BallState(position: CGPoint(x: 500, y: floor), phase: .resting),
            direction: .right
        )

        var rolled = false
        for _ in 0..<600 where state.phase == .kicked || state.phase == .rolling {
            state = BallPhysics.step(state, dt: 1.0 / 60, landingY: floor, roamableArea: roamableArea)
            if state.phase == .rolling { rolled = true }
        }

        XCTAssertTrue(rolled, "a kick with sideways speed on it should roll before it stops")
        XCTAssertEqual(state.phase, .resting)
    }

    func test_aRollingToyKeepsGoingInTheDirectionItWasTravelling() {
        let floor = roamableArea.maxY
        let state = BallState(position: CGPoint(x: 500, y: floor), horizontalVelocity: 300, phase: .rolling)

        let next = BallPhysics.step(state, dt: 1.0 / 60, landingY: floor, roamableArea: roamableArea)

        XCTAssertGreaterThan(next.position.x, 500)
        XCTAssertEqual(next.position.y, floor, accuracy: 0.001, "a roll stays on the surface")
        XCTAssertLessThan(next.horizontalVelocity, 300, "and is slowed by it")
        XCTAssertGreaterThan(next.horizontalVelocity, 0, "but never pushed backwards")
    }

    /// Friction that overshoots zero would have the toy roll back the way it
    /// came, which is the one thing a floor cannot do.
    func test_aSlowRollStopsRatherThanReversing() {
        let floor = roamableArea.maxY
        let state = BallState(position: CGPoint(x: 500, y: floor), horizontalVelocity: 5, phase: .rolling)

        let next = BallPhysics.step(state, dt: 1.0 / 60, landingY: floor, roamableArea: roamableArea)

        XCTAssertEqual(next.phase, .resting)
        XCTAssertEqual(next.horizontalVelocity, 0)
    }

    func test_aRollingToyBouncesOffTheSideRatherThanLeaving() {
        let floor = roamableArea.maxY
        let state = BallState(position: CGPoint(x: 1010, y: floor), horizontalVelocity: 600, phase: .rolling)

        let next = BallPhysics.step(state, dt: 1.0 / 60, landingY: floor, roamableArea: roamableArea)

        XCTAssertLessThan(next.horizontalVelocity, 0, "turned around")
        XCTAssertLessThanOrEqual(next.position.x, roamableArea.maxX)
    }

    /// Rolling off the edge of the window it was on: it carries its sideways
    /// speed into the air rather than dropping straight down off the lip.
    func test_aToyThatRollsOffItsSurfaceGoesBackIntoTheAir() {
        let state = BallState(position: CGPoint(x: 500, y: 300), horizontalVelocity: 400, phase: .rolling)

        // Nothing under it any more: the surface is now the floor far below.
        let next = BallPhysics.step(state, dt: 1.0 / 60, landingY: 900, roamableArea: roamableArea)

        XCTAssertEqual(next.phase, .kicked)
        XCTAssertEqual(next.horizontalVelocity, 400, "still travelling the way it was")
    }

    /// A wand dragged along the floor is not a ball: the caller decides how
    /// grippy the surface is for this toy.
    func test_friction_isTheCallers() {
        let floor = roamableArea.maxY
        let state = BallState(position: CGPoint(x: 500, y: floor), horizontalVelocity: 300, phase: .rolling)

        let slippery = BallPhysics.step(
            state, dt: 1.0 / 60, landingY: floor, roamableArea: roamableArea, rollingFriction: 100
        )
        let grippy = BallPhysics.step(
            state, dt: 1.0 / 60, landingY: floor, roamableArea: roamableArea, rollingFriction: 5000
        )

        XCTAssertGreaterThan(slippery.horizontalVelocity, grippy.horizontalVelocity)
    }

    /// The floor takes some of the sideways speed too. Without this a kicked
    /// toy crossed the whole screen at its launch speed however many times it
    /// bounced on the way.
    func test_aBounceOffTheFloorSlowsTheToySideways() {
        let floor = roamableArea.maxY
        let state = BallState(
            position: CGPoint(x: 500, y: floor),
            verticalVelocity: 800,
            horizontalVelocity: 400,
            phase: .kicked
        )

        let next = BallPhysics.step(state, dt: 1.0 / 60, landingY: floor, roamableArea: roamableArea)

        XCTAssertLessThan(next.horizontalVelocity, 400)
        XCTAssertGreaterThan(next.horizontalVelocity, 0)
    }

    // MARK: - Losing speed to the air

    private var area: CGRect { CGRect(x: 0, y: 0, width: 1000, height: 800) }

    /// A hard flick used to cross the whole screen at the speed it left the
    /// hand, losing nothing until it hit something. Which way the toy is
    /// turned is BallController's -- the orientation of every phase lives
    /// there, and putting a second copy here is how the two come to disagree.
    func testTheAirTakesSomeSpeed() {
        var flung = BallState(position: CGPoint(x: 100, y: 100), phase: .kicked)
        flung.horizontalVelocity = 1200
        let openSky = CGRect(x: 0, y: 0, width: 100_000, height: 100_000)

        var state = flung
        for _ in 0..<60 { state = BallPhysics.step(state, dt: 1 / 60, landingY: 4000, roamableArea: openSky) }

        XCTAssertLessThan(state.horizontalVelocity, flung.horizontalVelocity)
        XCTAssertGreaterThan(state.horizontalVelocity, 0, "the air stops it, not a wall")
    }

    /// It slows the toy without turning it round, which a drag written as a
    /// subtraction rather than a fraction would do at low speed.
    func testTheAirNeverReversesTheToy() {
        var slow = BallState(position: CGPoint(x: 100, y: 100), phase: .kicked)
        slow.horizontalVelocity = 3
        let openSky = CGRect(x: 0, y: 0, width: 100_000, height: 100_000)

        var state = slow
        for _ in 0..<600 { state = BallPhysics.step(state, dt: 1 / 60, landingY: 40_000, roamableArea: openSky) }

        XCTAssertGreaterThanOrEqual(state.horizontalVelocity, 0)
    }

    /// A resting toy the physics has nothing to do with is left exactly as it
    /// was, or it never stops producing new states for a toy nobody touched.
    func testASettledToyIsLeftAlone() {
        let still = BallState(position: CGPoint(x: 500, y: 700), phase: .resting)

        XCTAssertEqual(BallPhysics.step(still, dt: 1 / 60, landingY: 700, roamableArea: area), still)
    }
}
