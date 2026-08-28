//
//  CeilingStatesTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  ClimbToCeiling -> Ceiling -> Fall (2026-07-29 ceiling-crawling): climbs
//  straight up to the roamable area's top edge, then crawls upside-down
//  along it, bouncing off the horizontal bounds instead of falling off.
//
//  ClimbToCeiling requires an actual window edge to climb, the same way
//  ClimbState does -- climbing must only happen via a real on-screen wall,
//  not from arbitrary terrain (it used to climb from anywhere).
//

import XCTest
@testable import Puck

private func window(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> WindowInfo {
    WindowInfo(windowID: 1, ownerPID: 1, ownerName: nil, title: nil, layer: 0, frame: CGRect(x: x, y: y, width: width, height: height))
}

/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class ClimbToCeilingStateTests: XCTestCase {
    // A wall tall enough to span from well below the pet's start position up
    // past the ceiling target, at x=100 so windowBeingClimbed recognizes it.
    private let tallWall = window(x: 100, y: 0, width: 400, height: 500)

    func test_climbsStraightUpTowardTheCeiling() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 400))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        world.windows = [tallWall]
        let state = ClimbToCeilingState()
        state.enter()

        world.run(state, seconds: 1)

        XCTAssertEqual(world.body.position.x, 100, "climbing straight up -- x must not drift")
        XCTAssertLessThan(world.body.position.y, 400, "should have climbed upward")
    }

    func test_arrivalAtTheCeilingRequestsCeilingTransition() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 10))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        world.windows = [tallWall]
        let state = ClimbToCeilingState()
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.requestedTransitions.first, .ceiling)
        XCTAssertEqual(world.body.position.y, 0, accuracy: MovementSolver.arrivalRadius)
    }

    /// Position is still the feet here (right-side-up) -- arriving with the
    /// feet at the literal top of the screen would push the head off-screen
    /// before "arrival" (this was the actual bug: the pet visibly vanished
    /// while climbing, then reappeared once Ceiling took over, reading as a
    /// teleport). It must stop with the HEAD at the ceiling instead.
    func test_arrivesWithTheHeadAtTheCeiling_notTheFeet() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 200))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        world.avatarHeight = 140
        world.windows = [tallWall]
        let state = ClimbToCeilingState()
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.body.position.y, 140, accuracy: MovementSolver.arrivalRadius)
    }

    func test_requestsCeilingOnlyOnce() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 10))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        world.windows = [tallWall]
        let state = ClimbToCeilingState()
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.requestedTransitions.count, 1)
    }

    /// Settings' movement-speed slider.
    func test_respectsACustomWalkSpeed() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 400))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        world.walkSpeed = MovementSolver.walkSpeed * 2
        world.windows = [tallWall]
        let state = ClimbToCeilingState()
        state.enter()

        world.run(state, seconds: 0.1)

        let expectedY = 400 - MovementSolver.walkSpeed * 2 * 0.1
        XCTAssertEqual(world.body.position.y, expectedY, accuracy: 5)
    }

    // MARK: - Requires an actual wall (2026-07-29)

    func test_withoutAnyNearbyWindow_fallsInstead() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 400))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        // no windows at all
        let state = ClimbToCeilingState()
        state.enter()

        world.run(state, seconds: 0.1)

        XCTAssertEqual(world.requestedTransitions.first, .fall)
    }

    /// A wall that doesn't reach anywhere near the ceiling: the pet can
    /// climb it, but only as far as the wall actually goes.
    func test_climbingPastTheTopOfAShortWall_fallsInstead() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 400))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        world.windows = [window(x: 100, y: 350, width: 400, height: 150)] // spans y 350...500 only
        let state = ClimbToCeilingState()
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.requestedTransitions.first, .fall)
    }
}

/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class CeilingStateTests: XCTestCase {
    func test_enter_flipsTheBodyUpsideDown() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let state = CeilingState(durationProvider: { 100 })
        state.enter()

        world.run(state, seconds: 0.1)

        XCTAssertTrue(world.body.isUpsideDown)
    }

    func test_walksAlongTheCeiling_stayingWithinRoamableBounds() {
        let world = TestStateWorld(position: CGPoint(x: 490, y: 999))
        world.roamableArea = CGRect(x: 0, y: 0, width: 500, height: 500)
        let state = CeilingState(durationProvider: { 100 })
        state.enter()

        world.run(state, seconds: 5)

        XCTAssertLessThanOrEqual(world.body.position.x, 500)
        XCTAssertGreaterThanOrEqual(world.body.position.x, 0)
        XCTAssertEqual(world.body.position.y, 0, "must crawl along the ceiling, not drift in Y")
    }

    func test_afterDurationElapses_requestsFall() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let state = CeilingState(durationProvider: { 1 })
        state.enter()

        world.run(state, seconds: 0.5)
        XCTAssertTrue(world.requestedTransitions.isEmpty)

        world.run(state, seconds: 1)
        XCTAssertEqual(world.requestedTransitions, [.fall])
    }

    func test_requestsFallOnlyOnce() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let state = CeilingState(durationProvider: { 1 })
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.requestedTransitions.count, 1)
    }

    /// Settings' movement-speed slider.
    func test_respectsACustomWalkSpeed() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 0))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
        world.walkSpeed = MovementSolver.walkSpeed * 2
        let state = CeilingState(durationProvider: { 100 })
        state.enter()

        world.run(state, seconds: 0.1)

        let expectedX = 100 + MovementSolver.walkSpeed * 2 * 0.1
        XCTAssertEqual(world.body.position.x, expectedX, accuracy: 5)
    }

    /// ScreenBounds.contain always pins to leftLimit when the avatar (Settings'
    /// size slider) is wider than the roamable area -- comparing that pinned
    /// result against ever-advancing `travelled.x` used to flip `direction`
    /// every single frame forever, instead of settling (found via review).
    func test_oversizedAvatar_holdsStillInsteadOfJitteringForever() {
        let world = TestStateWorld(position: CGPoint(x: 25, y: 0))
        // visualBounds defaults to width 100 (x: -50...50); a 50-wide roamable
        // area is narrower than the avatar.
        world.roamableArea = CGRect(x: 0, y: 0, width: 50, height: 500)
        let state = CeilingState(durationProvider: { 100 })
        state.enter()

        var facingHistory: [AvatarFacing] = []
        for _ in 0..<180 {
            state.update(dt: 1.0 / 60, context: world.context)
            facingHistory.append(world.body.facing)
        }

        // Once settled, facing must stop alternating frame-to-frame.
        let tail = facingHistory.suffix(10)
        XCTAssertTrue(tail.allSatisfy { $0 == tail.first }, "facing should settle, not alternate every frame: \(tail)")
    }
}

/// The camera housing at the top of a MacBook, once the pet's world reaches
/// it. Usually it does not -- the menu bar is exactly as tall as the notch,
/// so the ceiling is already below it -- but in a fullscreen Space that
/// height is given back and a black rectangle is hanging into the room.
@MainActor
final class CeilingNotchTests: XCTestCase {
    /// A 1000x500 screen with a notch 200 wide and 40 deep in the middle.
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 500)
    private let notch = ScreenNotch(rect: CGRect(x: 400, y: 0, width: 200, height: 40))

    private func world(startingAt x: CGFloat) -> TestStateWorld {
        let world = TestStateWorld(position: CGPoint(x: x, y: 0))
        world.roamableArea = screen
        world.roamableAreas = [screen]
        world.notch = notch
        // Small enough to fit under the notch, so what is being tested is the
        // ceiling rather than containment refusing an oversized avatar.
        world.visualBounds = CGRect(x: -10, y: -20, width: 20, height: 20)
        return world
    }

    /// The reported behaviour: a crawl that keeps aiming at the screen's own
    /// top edge walks the pet straight through the camera.
    func test_theCrawlDucksUnderTheHousing() {
        let world = world(startingAt: 380)
        // No pause here: these are about where the ceiling is, and a pet
        // stopping under the housing never reaches the far side of it.
        let state = CeilingState(hangProvider: { 0 })
        state.enter()

        var wentUnder = false
        for _ in 0..<600 {
            world.run(state, seconds: 1.0 / 60)
            let x = world.body.position.x
            if x > notch.rect.minX, x < notch.rect.maxX {
                wentUnder = true
                XCTAssertEqual(
                    world.body.position.y, notch.rect.maxY,
                    accuracy: 0.5,
                    "under the housing the ceiling is its bottom edge, not the screen's top"
                )
            }
        }
        XCTAssertTrue(wentUnder, "the crawl has to actually reach the notch for this to have tested anything")
    }

    /// And comes back up on the other side of it rather than staying low.
    func test_itRisesAgainPastTheHousing() {
        let world = world(startingAt: 380)
        let state = CeilingState(hangProvider: { 0 })
        state.enter()

        var sawClearOfTheNotch = false
        for _ in 0..<900 {
            world.run(state, seconds: 1.0 / 60)
            let x = world.body.position.x
            if x > notch.rect.maxX + 20 {
                sawClearOfTheNotch = true
                XCTAssertEqual(world.body.position.y, screen.minY, accuracy: 0.5)
            }
        }
        XCTAssertTrue(sawClearOfTheNotch)
    }

    /// A screen with no notch is the ordinary case and must be untouched.
    func test_withoutAHousingTheCeilingIsTheScreensOwnTop() {
        let world = world(startingAt: 380)
        world.notch = nil
        let state = CeilingState(hangProvider: { 0 })
        state.enter()

        for _ in 0..<600 {
            world.run(state, seconds: 1.0 / 60)
            XCTAssertEqual(world.body.position.y, screen.minY, accuracy: 0.001)
        }
    }

    /// Climbing up to a ceiling that has the housing over it stops at the
    /// housing, or the pet's head goes behind the camera on the way.
    func test_theClimbStopsUnderTheHousing() {
        let world = TestStateWorld(position: CGPoint(x: 500, y: 400))
        world.roamableArea = screen
        world.roamableAreas = [screen]
        world.notch = notch
        world.avatarHeight = 20
        world.visualBounds = CGRect(x: -10, y: -20, width: 20, height: 20)
        // The pet climbs a window's *edge*, so its side has to be where the
        // pet is -- and that x has to be under the notch for this to be a
        // test of the notch.
        world.windows = [WindowInfo(windowID: 1, ownerPID: 1, ownerName: nil, title: nil, layer: 0,
                                    frame: CGRect(x: 500, y: 0, width: 400, height: 500))]
        let state = ClimbToCeilingState()
        state.enter()

        world.run(state, seconds: 4)

        XCTAssertEqual(
            world.body.position.y, notch.rect.maxY + world.avatarHeight,
            accuracy: MovementSolver.arrivalRadius,
            "the head stops at the housing's bottom edge, not the screen's top"
        )
    }
}

/// A thrown pet meets the housing too. Bouncing off the screen's own top
/// edge under the notch means going behind the camera to do it.
@MainActor
final class FallNotchTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 500)
    private let notch = ScreenNotch(rect: CGRect(x: 400, y: 0, width: 200, height: 40))

    func test_aThrowUnderTheHousingBouncesOffIt() {
        let world = TestStateWorld(position: CGPoint(x: 500, y: 300))
        world.roamableArea = screen
        world.roamableAreas = [screen]
        world.notch = notch
        world.visualBounds = CGRect(x: -10, y: -20, width: 20, height: 20)
        world.body.launchVelocity = CGPoint(x: 0, y: -2000)
        let state = FallState()
        state.enter()

        var highest = CGFloat.greatestFiniteMagnitude
        for _ in 0..<120 {
            world.run(state, seconds: 1.0 / 60)
            highest = min(highest, world.body.position.y + world.visualBounds.minY)
        }

        XCTAssertGreaterThanOrEqual(
            highest, notch.rect.maxY - 1,
            "the head went behind the camera housing"
        )
    }

    /// Clear of the notch, the whole screen is still available.
    func test_aThrowBesideTheHousingReachesTheScreensTop() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 300))
        world.roamableArea = screen
        world.roamableAreas = [screen]
        world.notch = notch
        world.visualBounds = CGRect(x: -10, y: -20, width: 20, height: 20)
        world.body.launchVelocity = CGPoint(x: 0, y: -2000)
        let state = FallState()
        state.enter()

        var highest = CGFloat.greatestFiniteMagnitude
        for _ in 0..<120 {
            world.run(state, seconds: 1.0 / 60)
            highest = min(highest, world.body.position.y + world.visualBounds.minY)
        }

        XCTAssertLessThan(highest, notch.rect.maxY, "nothing is in the way over here")
    }
}

/// The camera housing is the one landmark on an otherwise blank ceiling, so
/// the pet stops under it -- once per crawl, because stopping every pass
/// would read as being stuck rather than as pausing.
@MainActor
final class CeilingNotchHangTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 500)
    private let notch = ScreenNotch(rect: CGRect(x: 400, y: 0, width: 200, height: 40))

    private func world(startingAt x: CGFloat) -> TestStateWorld {
        let world = TestStateWorld(position: CGPoint(x: x, y: 0))
        world.roamableArea = screen
        world.roamableAreas = [screen]
        world.notch = notch
        world.visualBounds = CGRect(x: -10, y: -20, width: 20, height: 20)
        return world
    }

    func test_thePetStopsUnderTheHousing() {
        let world = world(startingAt: 380)
        // The hang outlasts the whole measurement, so a pet that has stopped
        // and one that is merely slow cannot be confused.
        let state = CeilingState(durationProvider: { 60 }, hangProvider: { 10 })
        state.enter()

        world.run(state, seconds: 1)
        let arrived = world.body.position.x
        XCTAssertGreaterThan(arrived, notch.rect.minX, "it has to reach the housing for this to test anything")
        XCTAssertLessThan(arrived, notch.rect.maxX)

        world.run(state, seconds: 3)
        XCTAssertEqual(world.body.position.x, arrived, accuracy: 0.001, "still hanging")
    }

    func test_itCarriesOnAfterwards() {
        let world = world(startingAt: 380)
        let state = CeilingState(durationProvider: { 60 }, hangProvider: { 1 })
        state.enter()

        world.run(state, seconds: 1)
        let hanging = world.body.position.x
        world.run(state, seconds: 3)

        XCTAssertGreaterThan(world.body.position.x, hanging, "the pause ends")
    }

    /// Once. A crawl bounces off both walls and comes back under the housing
    /// several times in its few seconds, and stopping every time is a pet
    /// that looks stuck to something.
    func test_itHangsOnlyOnce() {
        let world = world(startingAt: 380)
        let state = CeilingState(durationProvider: { 60 }, hangProvider: { 0.5 })
        state.enter()

        // Long enough to cross the whole ceiling and come back.
        world.run(state, seconds: 30)
        let before = world.body.position.x
        world.run(state, seconds: 0.5)

        XCTAssertNotEqual(world.body.position.x, before, accuracy: 0.001, "moving, not stopped again")
    }

    /// A Mac with no notch has nothing to stop at, and the crawl is what it
    /// always was.
    func test_withoutAHousingItNeverStops() {
        let world = world(startingAt: 380)
        world.notch = nil
        let state = CeilingState(durationProvider: { 60 }, hangProvider: { 5 })
        state.enter()

        world.run(state, seconds: 1)
        let before = world.body.position.x
        world.run(state, seconds: 0.2)

        XCTAssertNotEqual(world.body.position.x, before, accuracy: 0.001)
    }
}
