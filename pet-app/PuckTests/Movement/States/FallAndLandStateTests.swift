//
//  FallAndLandStateTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Fall -> Land -> Idle, the tail of the transition table in
//  plan/02_pet-app.md section 3. Fall is the only state with acceleration.
//

import XCTest
@testable import Puck

/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class FallStateTests: XCTestCase {
    func test_acceleratesDownwardEachFrame() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.landingY = 10_000 // far below, so it never lands during this test
        let state = FallState()
        state.enter()

        world.run(state, seconds: 0.2)
        let afterFirstBurst = world.body.position.y
        world.run(state, seconds: 0.2)
        let afterSecondBurst = world.body.position.y

        XCTAssertGreaterThan(afterFirstBurst, 0, "the pet should be falling")
        XCTAssertGreaterThan(
            afterSecondBurst - afterFirstBurst,
            afterFirstBurst,
            "the second interval must cover more ground than the first"
        )
    }

    func test_landsOnTheSurfaceAndRequestsLand() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.landingY = 200
        let state = FallState()
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.body.position.y, 200, accuracy: 0.001, "must stop on the surface, not sink through")
        XCTAssertEqual(world.requestedTransitions.first, .land)
    }

    func test_requestsLandOnlyOnce() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.landingY = 50
        let state = FallState()
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.requestedTransitions, [.land])
    }

    /// A fall off the ceiling (CeilingState) must land right-side up
    /// regardless of which state preceded it -- this resets it unconditionally
    /// rather than only when Fall was entered from Ceiling specifically.
    func test_landingResetsUpsideDown() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.landingY = 10_000
        world.body.isUpsideDown = true
        let state = FallState()
        state.enter()

        world.run(state, seconds: 0.1)

        XCTAssertFalse(world.body.isUpsideDown)
    }

    /// Velocity must not carry over from a previous fall, or the second one
    /// starts at whatever speed the first ended with.
    func test_velocityResetsOnReentry() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.landingY = 10_000
        let state = FallState()

        state.enter()
        world.run(state, seconds: 1)
        let fastFall = world.body.position.y

        world.body.position = CGPoint(x: 100, y: 0)
        state.enter()
        world.run(state, seconds: 1)
        let freshFall = world.body.position.y

        XCTAssertEqual(fastFall, freshFall, accuracy: 1, "a re-entered fall starts from rest")
    }

    // MARK: - Being thrown

    func test_launchVelocityCarriesThePetSideways() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.landingY = 10_000
        world.body.launchVelocity = CGPoint(x: 400, y: 0)
        let state = FallState()
        state.enter()

        world.run(state, seconds: 0.5)

        // Accuracy covers one frame of travel either way (400px/s ÷ 60).
        XCTAssertEqual(world.body.position.x, 300, accuracy: 10, "sideways travel is constant speed")
        XCTAssertGreaterThan(world.body.position.y, 0, "and it still falls while doing it")
    }

    /// The sideways speed is constant while the downward speed accelerates --
    /// that difference is what makes the path an arc rather than a diagonal.
    func test_aThrowArcs() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 0))
        world.landingY = 10_000
        world.body.launchVelocity = CGPoint(x: 400, y: 0)
        let state = FallState()
        state.enter()

        world.run(state, seconds: 0.25)
        let first = world.body.position
        world.run(state, seconds: 0.25)
        let second = world.body.position

        XCTAssertEqual(second.x - first.x, first.x, accuracy: 5, "same sideways distance each interval")
        XCTAssertGreaterThan(second.y - first.y, first.y, "but a greater drop each interval")
    }

    /// A throw at a wall comes back off it
    /// rather than stopping dead against it, and never leaves the screen.
    func test_aThrowBouncesOffTheEdgeOfTheRoamableArea() {
        let world = TestStateWorld(position: CGPoint(x: 900, y: 0))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 10_000)
        world.landingY = 10_000
        world.body.launchVelocity = CGPoint(x: 2000, y: 0) // hard throw at the right wall
        let state = FallState()
        state.enter()

        world.run(state, seconds: 0.1) // long enough to reach the wall and turn around
        let afterBounce = world.body.position.x
        world.run(state, seconds: 0.1)

        XCTAssertLessThan(afterBounce, 1000, "came back off the wall")
        XCTAssertLessThan(world.body.position.x, afterBounce, "and keeps travelling the other way")
    }

    /// An upward throw comes off the top of the
    /// screen and falls back, rather than disappearing above it.
    func test_anUpwardThrowBouncesOffTheTopOfTheScreen() {
        let world = TestStateWorld(position: CGPoint(x: 500, y: 300))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 800)
        world.landingY = 800
        world.body.launchVelocity = CGPoint(x: 0, y: -3000) // hurled straight up
        let state = FallState()
        state.enter()

        // The pet's HEAD is what meets the ceiling, so the limit is its
        // outline's top offset above the position -- not the position itself.
        let headroom = -world.visualBounds.minY
        var highestHead = CGFloat.greatestFiniteMagnitude
        for _ in 0..<60 {
            world.run(state, seconds: 1.0 / 60)
            let head = world.body.position.y - headroom
            highestHead = min(highestHead, head)
            XCTAssertGreaterThanOrEqual(head, 0, "never above the top of the screen")
        }

        // Never lands exactly on 0: a frame at 3000px/sec covers 50px, and the
        // frame that would have crossed the ceiling is reflected back down
        // instead. Getting within one frame of travel is "reached it".
        XCTAssertLessThan(highestHead, 50, "it did reach the ceiling")
        XCTAssertGreaterThan(world.body.position.y - headroom, highestHead, "and came back down from it")
    }

    func test_aThrowNeverLeavesTheScreen() {
        let world = TestStateWorld(position: CGPoint(x: 900, y: 0))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 10_000)
        world.landingY = 10_000
        world.body.launchVelocity = CGPoint(x: 6000, y: 0) // as hard as it gets
        let state = FallState()
        state.enter()

        for _ in 0..<120 { // two seconds of bouncing around
            world.run(state, seconds: 1.0 / 60)
            // The whole outline, not just the position, has to stay inside.
            let outline = world.visualBounds.offsetBy(dx: world.body.position.x, dy: 0)
            XCTAssertGreaterThanOrEqual(outline.minX, 0, "artwork left the screen on the left")
            XCTAssertLessThanOrEqual(outline.maxX, 1000, "artwork left the screen on the right")
        }
    }

    /// One throw must not make every later fall drift sideways.
    func test_launchVelocityIsConsumedByTheFall() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.landingY = 10_000
        world.body.launchVelocity = CGPoint(x: 400, y: 0)
        let state = FallState()

        state.enter()
        world.run(state, seconds: 0.2)
        XCTAssertEqual(world.body.launchVelocity, .zero, "cleared as soon as it is taken")

        world.body.position = CGPoint(x: 100, y: 0)
        state.enter()
        world.run(state, seconds: 0.2)

        XCTAssertEqual(world.body.position.x, 100, "the next fall is straight down")
    }

    // MARK: - Bouncing + sliding on landing (a hard throw landing should
    // bounce a couple of times
    // and slide, not stop dead the instant it touches the ground)

    func test_aHardThrow_bouncesOnLandingInsteadOfStoppingDead() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.landingY = 200
        world.body.launchVelocity = CGPoint(x: 800, y: 0) // a hard sideways throw
        let state = FallState()
        state.enter()

        // One frame past the moment it should first reach the surface --
        // long enough to fall the 200px, not long enough to have fully
        // settled yet.
        world.run(state, seconds: 0.42)

        XCTAssertTrue(world.requestedTransitions.isEmpty, "still bouncing, must not have landed for real yet")
    }

    func test_aHardThrow_eventuallySettlesAndRequestsLand() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.landingY = 200
        world.body.launchVelocity = CGPoint(x: 800, y: 0)
        let state = FallState()
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.body.position.y, 200, accuracy: 0.001)
        XCTAssertEqual(world.requestedTransitions.first, .land)
    }

    /// The slide: horizontal speed keeps carrying the pet for a while after
    /// it touches down, instead of the sideways motion also stopping dead.
    func test_afterLanding_horizontalSpeedDecaysRatherThanStoppingInstantly() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.roamableArea = CGRect(x: 0, y: 0, width: 10_000, height: 500)
        world.landingY = 200
        world.body.launchVelocity = CGPoint(x: 800, y: 0)
        let state = FallState()
        state.enter()

        world.run(state, seconds: 0.42) // reaches the ground
        let xAtTouchdown = world.body.position.x
        world.run(state, seconds: 0.1) // a moment of sliding
        let xShortlyAfter = world.body.position.x
        world.run(state, seconds: 2) // long enough to fully settle
        let xAtRest = world.body.position.x

        XCTAssertGreaterThan(xShortlyAfter, xAtTouchdown, "still sliding just after touchdown")
        XCTAssertGreaterThan(xAtRest, xShortlyAfter, "keeps sliding a little further before stopping")
    }

    func test_aPlainFallIsUnaffected() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.landingY = 10_000
        let state = FallState()
        state.enter()

        world.run(state, seconds: 0.5)

        XCTAssertEqual(world.body.position.x, 100, "no throw, no sideways drift")
    }
}

/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class LandStateTests: XCTestCase {
    func test_returnsToIdleAfterTheLandingBeat() {
        let world = TestStateWorld()
        let state = LandState()
        state.enter()

        world.run(state, seconds: 0.05)
        XCTAssertTrue(world.requestedTransitions.isEmpty, "the landing clip needs a moment to read")

        world.run(state, seconds: 1)
        XCTAssertEqual(world.requestedTransitions, [.idle])
    }
}

/// The throw's sideways half, which is the part nothing was holding onto.
///
/// `ScreenBounds.bounceHorizontally` has its own tests, but nothing checked
/// that Fall actually uses it -- or that the launch velocity a release hands
/// over reaches it at all. Both are easy to break silently: the pet keeps
/// falling either way, it just stops travelling, or sails off the side.
@MainActor
final class FallThrowTests: XCTestCase {
    /// A pet let go mid-flick keeps the speed it was let go with.
    func test_theThrowCarriesThePetSideways() {
        let world = TestStateWorld(position: CGPoint(x: 500, y: 0))
        world.landingY = 10_000
        world.body.launchVelocity = CGPoint(x: 600, y: 0)
        let state = FallState()
        state.enter()

        world.run(state, seconds: 0.2)

        XCTAssertGreaterThan(world.body.position.x, 560, "the throw's sideways speed was dropped")
    }

    /// And rebounds off the side of the screen rather than sailing through it.
    /// The wall is where the pet's *outline* meets the edge, so a throw at the
    /// right wall turns around while the artwork is still on screen.
    func test_theThrownPetBouncesOffTheWall() {
        let world = TestStateWorld(position: CGPoint(x: 900, y: 0))
        world.landingY = 10_000
        // 1000 wide, and the outline reaches 50 either side of the position.
        world.body.launchVelocity = CGPoint(x: 2000, y: 0)
        let state = FallState()
        state.enter()

        world.run(state, seconds: 0.4)

        let rightLimit = world.roamableArea.maxX - world.visualBounds.maxX
        XCTAssertLessThanOrEqual(
            world.body.position.x, rightLimit + 0.5,
            "the pet went through the right wall instead of bouncing off it"
        )
        XCTAssertLessThan(
            world.body.position.x, 900,
            "it should have come back the other way, not stuck to the wall"
        )
    }

    /// The same on the way out to the left.
    func test_theThrownPetBouncesOffTheLeftWall() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.landingY = 10_000
        world.body.launchVelocity = CGPoint(x: -2000, y: 0)
        let state = FallState()
        state.enter()

        world.run(state, seconds: 0.4)

        let leftLimit = world.roamableArea.minX - world.visualBounds.minX
        XCTAssertGreaterThanOrEqual(
            world.body.position.x, leftLimit - 0.5,
            "the pet went through the left wall"
        )
        XCTAssertGreaterThan(world.body.position.x, 100, "it should have come back the other way")
    }

    /// A pet let go of without moving the cursor drops straight down, which is
    /// what it always did before throwing existed.
    func test_aStillReleaseIsAPlainDrop() {
        let world = TestStateWorld(position: CGPoint(x: 500, y: 0))
        world.landingY = 10_000
        let state = FallState()
        state.enter()

        world.run(state, seconds: 0.3)

        XCTAssertEqual(world.body.position.x, 500, accuracy: 0.001)
        XCTAssertGreaterThan(world.body.position.y, 0)
    }
}
