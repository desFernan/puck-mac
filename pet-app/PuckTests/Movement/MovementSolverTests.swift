//
//  MovementSolverTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The pure motion arithmetic behind MoveTo/Walk. plan/02_pet-app.md F3: no
//  physics engine -- MoveTo travels at a constant px/sec with an arrival
//  radius, and only Fall accelerates.
//  Positions are GlobalScreenSpace pixels (top-left origin, Y down).
//

import XCTest
@testable import Puck

final class MovementSolverTests: XCTestCase {
    // MARK: - Constant-velocity step

    func test_movesTowardTargetAtConstantSpeed() {
        let step = MovementSolver.step(
            from: CGPoint(x: 0, y: 0),
            toward: CGPoint(x: 100, y: 0),
            speed: 200,
            dt: 0.1,
            arrivalRadius: 1
        )

        XCTAssertEqual(step.position.x, 20, accuracy: 0.001, "200px/s for 0.1s = 20px")
        XCTAssertEqual(step.position.y, 0, accuracy: 0.001)
        XCTAssertFalse(step.hasArrived)
    }

    func test_speedIsIndependentOfDirection() {
        // A diagonal target must still advance exactly speed*dt, not speed*dt
        // per axis — that would make diagonal movement 1.41x too fast.
        let step = MovementSolver.step(
            from: .zero,
            toward: CGPoint(x: 100, y: 100),
            speed: 100,
            dt: 1,
            arrivalRadius: 1
        )

        let travelled = hypot(step.position.x, step.position.y)
        XCTAssertEqual(travelled, 100, accuracy: 0.001)
    }

    // MARK: - Arrival

    func test_reportsArrivalInsideTheRadius() {
        let step = MovementSolver.step(
            from: CGPoint(x: 99, y: 0),
            toward: CGPoint(x: 100, y: 0),
            speed: 200,
            dt: 0.1,
            arrivalRadius: 5
        )

        XCTAssertTrue(step.hasArrived)
    }

    /// Without clamping, a fast pet and a slow frame overshoot the target and
    /// then oscillate around it forever, never landing inside the radius.
    func test_doesNotOvershootTheTarget() {
        let step = MovementSolver.step(
            from: .zero,
            toward: CGPoint(x: 10, y: 0),
            speed: 1000,
            dt: 1, // would travel 1000px toward a target 10px away
            arrivalRadius: 1
        )

        XCTAssertEqual(step.position.x, 10, accuracy: 0.001, "must stop at the target, not past it")
        XCTAssertTrue(step.hasArrived)
    }

    func test_alreadyAtTarget_staysPutAndReportsArrival() {
        let step = MovementSolver.step(
            from: CGPoint(x: 50, y: 50),
            toward: CGPoint(x: 50, y: 50),
            speed: 200,
            dt: 0.1,
            arrivalRadius: 1
        )

        XCTAssertEqual(step.position, CGPoint(x: 50, y: 50))
        XCTAssertTrue(step.hasArrived)
    }

    // MARK: - Facing

    func test_facingFollowsHorizontalDirection() {
        XCTAssertEqual(MovementSolver.facing(from: .zero, toward: CGPoint(x: 10, y: 0)), .right)
        XCTAssertEqual(MovementSolver.facing(from: .zero, toward: CGPoint(x: -10, y: 0)), .left)
    }

    func test_facingIsUnchangedForPurelyVerticalMotion() {
        XCTAssertNil(
            MovementSolver.facing(from: .zero, toward: CGPoint(x: 0, y: 50)),
            "climbing straight up must not flip the character"
        )
    }

    // MARK: - Falling

    func test_fallAcceleratesDownward() {
        // Y grows downward in GlobalScreenSpace.
        let first = MovementSolver.fallStep(position: .zero, velocity: 0, gravity: 1000, dt: 0.1)
        XCTAssertEqual(first.velocity, 100, accuracy: 0.001)
        XCTAssertGreaterThan(first.position.y, 0)

        let second = MovementSolver.fallStep(position: first.position, velocity: first.velocity, gravity: 1000, dt: 0.1)
        XCTAssertEqual(second.velocity, 200, accuracy: 0.001)
        XCTAssertGreaterThan(
            second.position.y - first.position.y,
            first.position.y,
            "the second frame must cover more ground than the first"
        )
    }

    /// A fall settles at a steady speed the way a real falling object does
    /// under air resistance, instead of accelerating right up to the moment
    /// it hits -- which read as the pet being yanked onto the floor.
    func test_fallVelocitySettlesAtTerminalVelocity() {
        let step = MovementSolver.fallStep(
            position: .zero,
            velocity: 2000,
            gravity: 1000,
            dt: 1,
            terminalVelocity: 900
        )

        XCTAssertEqual(step.velocity, 900, accuracy: 0.001)
    }

    /// The point of the cap: on the longest drop a display allows, the pet is
    /// still moving at the same steady speed it settled into early on, not an
    /// ever-growing one. Uses the DEFAULT tuning so this pins the real feel.
    func test_aLongFallIsSteadyRatherThanEverFaster() {
        var velocity: CGFloat = 0
        var position = CGPoint.zero
        let dt: TimeInterval = 1.0 / 60
        var midFallVelocity: CGFloat = 0

        while position.y < 1200 { // taller than any display in points
            let step = MovementSolver.fallStep(position: position, velocity: velocity, dt: dt)
            position = step.position
            velocity = step.velocity
            if position.y >= 400, midFallVelocity == 0 {
                midFallVelocity = velocity
            }
        }

        XCTAssertEqual(velocity, midFallVelocity, accuracy: 0.001, "same speed at the end as in the middle")
        XCTAssertLessThan(velocity * CGFloat(dt), 25, "and a readable distance per frame")
    }

    /// A short fall (off a window)
    /// must pick up real speed within a much shorter distance than a drop down
    /// the whole screen, or it never gets past "floaty" before it lands. Uses
    /// the DEFAULT gravity (no override) so this pins the live tuning, not
    /// just the math.
    func test_defaultGravity_picksUpSpeedWithinAShortFall() {
        var velocity: CGFloat = 0
        var position = CGPoint.zero
        let dt: TimeInterval = 1.0 / 60

        while position.y < 250 { // roughly a window's height
            let step = MovementSolver.fallStep(position: position, velocity: velocity, dt: dt)
            position = step.position
            velocity = step.velocity
        }

        XCTAssertGreaterThan(velocity, 1000, "a window-height fall is already moving properly")
    }

    func test_fallVelocityBelowTerminal_acceleratesNormally() {
        let step = MovementSolver.fallStep(
            position: .zero,
            velocity: 0,
            gravity: 1000,
            dt: 0.1
        )

        XCTAssertEqual(step.velocity, 100, accuracy: 0.001)
    }

    /// bounceOnLanding defaults to false: BallPhysics's kicked-ball/juggle
    /// drop reuses this exact function and already has its own separate
    /// bounce/juggle mechanics -- it must keep landing (and resting)
    /// immediately, unaffected by FallState opting into the new behavior.
    func test_fallStopsAtTheLandingSurface_byDefault_regardlessOfImpactSpeed() {
        let step = MovementSolver.fallStep(
            position: CGPoint(x: 0, y: 95),
            velocity: 1000,
            gravity: 1000,
            dt: 1,
            landingY: 100
        )

        XCTAssertEqual(step.position.y, 100, accuracy: 0.001, "must not sink through the surface")
        XCTAssertTrue(step.hasLanded)
        XCTAssertTrue(step.touchedFloor)
        XCTAssertEqual(step.velocity, 0)
    }

    // MARK: - Bouncing on landing, opt-in via bounceOnLanding: true (a hard
    // landing, e.g. after being
    // thrown and bouncing off a wall, should bounce a couple of times before
    // it settles, not stop dead on contact). Only FallState (the pet itself)
    // opts in; BallPhysics does not, see the default-behavior test above.

    func test_fallHardImpact_bouncesInsteadOfLandingImmediately_whenOptedIn() {
        let step = MovementSolver.fallStep(
            position: CGPoint(x: 0, y: 95),
            velocity: 1000,
            gravity: 1000,
            dt: 1,
            landingY: 100,
            bounceOnLanding: true
        )

        XCTAssertFalse(step.hasLanded, "still has too much energy to rest")
        XCTAssertTrue(step.touchedFloor, "but it did just make contact")
        XCTAssertLessThan(step.velocity, 0, "and is now heading back up")
    }

    func test_fallNeverLandsSunkenBelowTheSurface_evenWhileBouncing() {
        let step = MovementSolver.fallStep(
            position: CGPoint(x: 0, y: 95),
            velocity: 1000,
            gravity: 1000,
            dt: 1,
            landingY: 100,
            bounceOnLanding: true
        )

        XCTAssertLessThanOrEqual(step.position.y, 100, "reflected back above the surface, not sunk into it")
    }

    /// A gentle impact still just lands, even opted in -- ScreenBounds.
    /// bounceOffFloor's own minimum-speed rest case handles this, no
    /// special-casing needed here.
    func test_fallGentleImpact_stillJustLands_evenWhenOptedIn() {
        let step = MovementSolver.fallStep(
            position: CGPoint(x: 0, y: 99.9),
            velocity: 50,
            gravity: 1000,
            dt: 0.1,
            landingY: 100,
            bounceOnLanding: true
        )

        XCTAssertEqual(step.position.y, 100, accuracy: 0.001)
        XCTAssertTrue(step.hasLanded)
    }

    /// The whole point: repeated hard impacts eventually decay down to a
    /// gentle one and land for real, instead of bouncing forever.
    func test_fallRepeatedHardBounces_eventuallySettlesAndLands() {
        var position = CGPoint(x: 0, y: 0)
        var velocity: CGFloat = 0
        var bounced = false

        for _ in 0..<300 { // five seconds at 60fps -- plenty for a few decaying bounces
            let step = MovementSolver.fallStep(position: position, velocity: velocity, dt: 1.0 / 60, landingY: 200, bounceOnLanding: true)
            if step.touchedFloor, !step.hasLanded { bounced = true }
            position = step.position
            velocity = step.velocity
            if step.hasLanded { break }
        }

        XCTAssertTrue(bounced, "should have visibly bounced at least once first")
        XCTAssertEqual(position.y, 200, accuracy: 0.001)
        XCTAssertEqual(velocity, 0)
    }

    func test_fallWithNoLandingSurface_neverTouchesTheFloor() {
        let step = MovementSolver.fallStep(position: .zero, velocity: 100, dt: 0.1, landingY: nil, bounceOnLanding: true)

        XCTAssertFalse(step.touchedFloor)
        XCTAssertFalse(step.hasLanded)
    }

    // MARK: - Ground friction (once
    // it has touched down, horizontal speed should decay to a slide-to-a-stop
    // rather than staying constant or dropping to zero instantly)

    func test_groundFriction_decaysVelocityTowardZero() {
        let decayed = MovementSolver.applyGroundFriction(400, dt: 0.1)

        XCTAssertLessThan(decayed, 400)
        XCTAssertGreaterThan(decayed, 0)
    }

    func test_groundFriction_preservesDirection() {
        XCTAssertLessThan(MovementSolver.applyGroundFriction(-400, dt: 0.1), 0)
    }

    func test_groundFriction_isFrameRateIndependent() {
        // Two half-steps must land at the same place as one full step.
        let half = MovementSolver.applyGroundFriction(MovementSolver.applyGroundFriction(400, dt: 0.05), dt: 0.05)
        let whole = MovementSolver.applyGroundFriction(400, dt: 0.1)

        XCTAssertEqual(half, whole, accuracy: 0.01)
    }

    func test_groundFriction_snapsToZeroOnceNegligible() {
        // Many iterations of decay should eventually round down to exactly
        // zero rather than leaving an imperceptible drift forever.
        var velocity: CGFloat = 400
        for _ in 0..<600 { // ten seconds at 60fps
            velocity = MovementSolver.applyGroundFriction(velocity, dt: 1.0 / 60)
        }

        XCTAssertEqual(velocity, 0)
    }
}
