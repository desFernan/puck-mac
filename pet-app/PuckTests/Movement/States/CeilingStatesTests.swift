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
