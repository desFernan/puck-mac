//
//  WindowWalkingTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The window half of the transition table (plan/02_pet-app.md section 3):
//  Walk -> Climb at a window edge, Climb -> WalkOnTop at the top, WalkOnTop ->
//  Fall when the supporting window goes away.
//
//  Window frames arrive in the same space as the pet's position: overlay-local
//  pixels, top-left origin, Y down. AppDelegate converts F4's global Quartz
//  frames into that space before they reach a state.
//

import XCTest
@testable import Puck

private func window(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, id: CGWindowID = 1) -> WindowInfo {
    WindowInfo(
        windowID: id,
        ownerPID: 1234,
        ownerName: "Test",
        title: nil,
        layer: 0,
        frame: CGRect(x: x, y: y, width: width, height: height)
    )
}

/// `@MainActor`: the character and its states belong to the main thread,
/// which is where the frame loop drives them.
@MainActor
final class WalkStateWindowTests: XCTestCase {
    /// Walking into the side of a window is what starts a climb — the pet
    /// shouldn't walk through it.
    func test_reachingAWindowEdge_requestsClimb() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 500))
        world.windows = [window(x: 300, y: 200, width: 400, height: 300)]
        let state = WalkState()
        state.target = CGPoint(x: 900, y: 500) // straight through the window

        world.run(state, seconds: 5)

        XCTAssertEqual(world.requestedTransitions.first, .climb)
        XCTAssertEqual(world.body.position.x, 300, accuracy: MovementSolver.arrivalRadius + 1)
    }

    /// Settings' "포커스된 창 위로는 올라가지 않기". The pet keeps walking rather
    /// than scaling the window the user is working in -- the toggle used to
    /// be written by the Settings panel and read by nothing, so this window
    /// got climbed exactly like any other.
    func test_aWindowTheSettingRulesOut_isWalkedPastRatherThanClimbed() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 500))
        let focused = window(x: 300, y: 200, width: 400, height: 300, id: 42)
        world.windows = [focused]
        world.unclimbableWindowIDs = [focused.windowID]
        let state = WalkState()
        state.target = CGPoint(x: 900, y: 500)

        world.run(state, seconds: 10)

        XCTAssertEqual(world.requestedTransitions, [.idle], "no climb may be requested")
        XCTAssertEqual(world.body.position.x, 900, accuracy: MovementSolver.arrivalRadius)
    }

    /// A window tall enough to leave no headroom above it (near-fullscreen)
    /// is skipped rather than climbed -- climbing it would clip the
    /// character's head off the top of the screen, the same geometry
    /// problem ceiling-crawling had.
    func test_windowTooTallToClimbWithoutClipping_isNotTreatedAsBlocking() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 500))
        world.avatarHeight = 140
        // roamableArea.minY defaults to 0; the window's top edge is only
        // 50px below it -- far less than the 140px of headroom needed.
        world.windows = [window(x: 300, y: 50, width: 400, height: 450)]
        let state = WalkState()
        state.target = CGPoint(x: 900, y: 500)

        world.run(state, seconds: 10)

        XCTAssertEqual(world.requestedTransitions, [.idle], "should walk straight past, not climb")
        XCTAssertEqual(world.body.position.x, 900, accuracy: MovementSolver.arrivalRadius)
    }

    func test_windowOutOfTheWay_doesNotInterruptTheWalk() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 500))
        world.windows = [window(x: 300, y: 20, width: 400, height: 100)] // far above the pet
        let state = WalkState()
        state.target = CGPoint(x: 400, y: 500)

        world.run(state, seconds: 5)

        XCTAssertEqual(world.requestedTransitions, [.idle], "no window in the pet's path")
    }
}

/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class ClimbStateTests: XCTestCase {
    func test_climbsUpToTheWindowTopThenWalksOnIt() {
        let world = TestStateWorld(position: CGPoint(x: 300, y: 500))
        world.windows = [window(x: 300, y: 200, width: 400, height: 300)]
        let state = ClimbState()
        state.enter()

        world.run(state, seconds: 5)

        XCTAssertEqual(world.body.position.y, 200, accuracy: MovementSolver.arrivalRadius + 1)
        XCTAssertEqual(world.requestedTransitions.first, .walkOnTop)
    }

    /// Climbing is vertical; flipping the character partway up looks wrong.
    func test_doesNotChangeFacingWhileClimbing() {
        let world = TestStateWorld(position: CGPoint(x: 300, y: 500))
        world.windows = [window(x: 300, y: 200, width: 400, height: 300)]
        let state = ClimbState()
        state.enter()

        world.run(state, seconds: 1)

        XCTAssertTrue(world.avatar.facings.isEmpty)
    }

    /// Settings' movement-speed slider.
    func test_respectsACustomWalkSpeed() {
        let world = TestStateWorld(position: CGPoint(x: 300, y: 500))
        world.walkSpeed = MovementSolver.walkSpeed * 2
        world.windows = [window(x: 300, y: 200, width: 400, height: 300)]
        let state = ClimbState()
        state.enter()

        world.run(state, seconds: 0.1)

        // 300 (start) minus 2x the default speed over the elapsed time.
        let expectedY = 500 - MovementSolver.walkSpeed * 2 * 0.1
        XCTAssertEqual(world.body.position.y, expectedY, accuracy: 5)
    }

    func test_withNoWindowToClimb_falls() {
        let world = TestStateWorld(position: CGPoint(x: 300, y: 500))
        world.windows = []
        let state = ClimbState()
        state.enter()

        world.run(state, seconds: 0.5)

        XCTAssertEqual(world.requestedTransitions.first, .fall)
    }
}

/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class WalkOnTopStateTests: XCTestCase {
    func test_supportingWindowDisappears_falls() {
        let world = TestStateWorld(position: CGPoint(x: 400, y: 200))
        world.windows = [window(x: 300, y: 200, width: 400, height: 300)]
        let state = WalkOnTopState()
        state.enter()

        world.run(state, seconds: 0.5)
        XCTAssertTrue(world.requestedTransitions.isEmpty, "still supported")

        world.windows = [] // window closed or minimized
        world.run(state, seconds: 0.5)

        XCTAssertEqual(world.requestedTransitions, [.fall])
    }

    /// Walking off the end of a window top is the same situation as the
    /// window vanishing: nothing underfoot. Starts near the left edge, so it
    /// resolves to walk right (see the two direction tests below) and
    /// eventually crosses the whole window with nothing underfoot.
    func test_walkingPastTheWindowEdge_falls() {
        let world = TestStateWorld(position: CGPoint(x: 310, y: 200))
        world.windows = [window(x: 300, y: 200, width: 400, height: 300)] // right edge at 700
        let state = WalkOnTopState()
        state.enter()

        world.run(state, seconds: 5)

        XCTAssertEqual(world.requestedTransitions.first, .fall)
    }

    /// Climb arrives at whichever edge is nearer the approach direction
    /// (WalkState.swift walks up to minX when approaching from the left).
    func test_climbingTheLeftEdge_walksRightIntoTheWindow() {
        let world = TestStateWorld(position: CGPoint(x: 305, y: 200))
        world.windows = [window(x: 300, y: 200, width: 400, height: 300)]
        let state = WalkOnTopState()
        state.enter()

        world.run(state, seconds: 0.5)

        XCTAssertTrue(world.requestedTransitions.isEmpty, "should walk into the window, not fall off the edge just climbed")
        XCTAssertGreaterThan(world.body.position.x, 305, "should be walking right, into the window")
    }

    /// Settings' movement-speed slider.
    func test_respectsACustomWalkSpeed() {
        let world = TestStateWorld(position: CGPoint(x: 305, y: 200))
        world.walkSpeed = MovementSolver.walkSpeed * 2
        world.windows = [window(x: 300, y: 200, width: 400, height: 300)]
        let state = WalkOnTopState()
        state.enter()

        world.run(state, seconds: 0.1)

        let expectedX = 305 + MovementSolver.walkSpeed * 2 * 0.1
        XCTAssertEqual(world.body.position.x, expectedX, accuracy: 5)
    }

    /// A pet that climbed the window's RIGHT edge (approaching from the
    /// right -- WalkState.swift walks up to maxX in that case) arrives at
    /// WalkOnTop near maxX. It must walk left, into the window, rather than
    /// immediately falling off the very edge it just climbed.
    func test_climbingTheRightEdge_walksLeftIntoTheWindow() {
        let world = TestStateWorld(position: CGPoint(x: 695, y: 200))
        world.windows = [window(x: 300, y: 200, width: 400, height: 300)] // right edge at 700
        let state = WalkOnTopState()
        state.enter()

        world.run(state, seconds: 0.5)

        XCTAssertTrue(world.requestedTransitions.isEmpty, "should walk into the window, not fall off the edge just climbed")
        XCTAssertLessThan(world.body.position.x, 695, "should be walking left, into the window")
    }

    /// A window reaching the edge of the display has no end to walk off, so
    /// the stroll has to turn around by itself -- otherwise the pet walks
    /// into the screen edge and stays there playing the walk clip, looking
    /// like it is trying to leave (2026-08-22).
    func test_reachingTheScreenEdge_turnsAroundInsteadOfPressingIntoIt() {
        let world = TestStateWorld(position: CGPoint(x: 900, y: 200))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 600)
        world.windows = [window(x: 0, y: 200, width: 1000, height: 400)]
        let state = WalkOnTopState()
        state.enter()

        world.run(state, seconds: 4) // long enough to reach the edge and come back

        let rightLimit = world.roamableArea.maxX - world.visualBounds.maxX
        XCTAssertLessThanOrEqual(world.body.position.x, rightLimit)
        XCTAssertEqual(world.body.facing, .left, "turned around")
        XCTAssertLessThan(world.body.position.x, rightLimit - 1, "and walked back from the edge")
        XCTAssertTrue(world.requestedTransitions.isEmpty, "the window is still underfoot -- no fall")
    }

    /// Walking off the *end of a window* is still a fall: that is the stroll
    /// finishing, not the screen getting in the way.
    func test_walkingOffTheEndOfTheWindow_stillFalls() {
        let world = TestStateWorld(position: CGPoint(x: 500, y: 200))
        world.roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 600)
        world.windows = [window(x: 300, y: 200, width: 300, height: 400)]
        let state = WalkOnTopState()
        state.enter()

        world.run(state, seconds: 4)

        XCTAssertEqual(world.requestedTransitions, [.fall])
    }
}
