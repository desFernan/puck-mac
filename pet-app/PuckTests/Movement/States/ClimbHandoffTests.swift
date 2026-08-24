//
//  ClimbHandoffTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The Climb -> WalkOnTop handoff, end to end through the real states --
//  a regression where the pet climbed onto a window and immediately fell
//  back off.
//
//  WindowWalkingTests covers each edge of the transition table on its own.
//  What it never covered is the seam: the position Climb actually leaves the
//  pet at, fed to the check WalkOnTop actually makes. A pet that climbs and
//  then drops on the very next frame passes every one of those tests.
//

import XCTest
@testable import Puck

private func testWindow(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> WindowInfo {
    WindowInfo(windowID: 1, ownerPID: 1234, ownerName: "Test", title: nil, layer: 0,
               frame: CGRect(x: x, y: y, width: width, height: height))
}

/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class ClimbHandoffTests: XCTestCase {
    /// Approaching from the left, Walk stops the pet at the window's *left*
    /// edge (WalkState: `edgeX = blocking.frame.minX`), so this is the x the
    /// climb starts and finishes at.
    func test_climbingTheLeftEdge_thenStandingOnTop_doesNotFall() {
        let window = testWindow(x: 300, y: 200, width: 400, height: 300)
        let world = TestStateWorld(position: CGPoint(x: window.frame.minX, y: 450))
        world.windows = [window]

        let climb = ClimbState()
        climb.enter()
        world.run(climb, seconds: 10)
        XCTAssertEqual(world.requestedTransitions.last, .walkOnTop, "climb should reach the top")

        let onTop = WalkOnTopState()
        onTop.enter()
        world.run(onTop, seconds: 0.05)

        XCTAssertFalse(
            world.requestedTransitions.contains(.fall),
            "the pet fell off the window it just climbed, at x=\(world.body.position.x) y=\(world.body.position.y) " +
            "(window top edge y=\(window.frame.minY), x range \(window.frame.minX)...\(window.frame.maxX))"
        )
    }

    /// Same seam on the other side: approaching from the right, Walk stops at
    /// `maxX`, which is the boundary `supportingWindow` treats as inclusive.
    func test_climbingTheRightEdge_thenStandingOnTop_doesNotFall() {
        let window = testWindow(x: 300, y: 200, width: 400, height: 300)
        let world = TestStateWorld(position: CGPoint(x: window.frame.maxX, y: 450))
        world.windows = [window]

        let climb = ClimbState()
        climb.enter()
        world.run(climb, seconds: 10)

        let onTop = WalkOnTopState()
        onTop.enter()
        world.run(onTop, seconds: 0.05)

        XCTAssertFalse(
            world.requestedTransitions.contains(.fall),
            "fell at x=\(world.body.position.x) y=\(world.body.position.y)"
        )
    }

    /// The pet walks *along* the top after arriving -- so the seam has to
    /// survive more than the first frame, too.
    func test_staysOnTopWhileWalkingAlongIt() {
        let window = testWindow(x: 300, y: 200, width: 400, height: 300)
        let world = TestStateWorld(position: CGPoint(x: window.frame.minX, y: window.frame.minY))
        world.windows = [window]

        let onTop = WalkOnTopState()
        onTop.enter()
        world.run(onTop, seconds: 1.0)

        XCTAssertFalse(world.requestedTransitions.contains(.fall))
        XCTAssertEqual(world.body.position.y, window.frame.minY, accuracy: 0.001)
    }
}
