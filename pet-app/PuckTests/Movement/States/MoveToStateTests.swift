//
//  MoveToStateTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  "임의 | 도구/이벤트 목표좌표 | MoveTo → Point 또는 Idle"
//  (plan/02_pet-app.md section 3).
//
//  Unlike Walk, MoveTo is a directed move ordered by a tool or a socket
//  event, so it does not climb windows it meets on the way — it goes where it
//  was told and hands over to whatever asked.
//

import XCTest
@testable import Puck

/// `@MainActor`: the character and its states belong to the main thread,
/// which is where the frame loop drives them.
@MainActor
final class MoveToStateTests: XCTestCase {
    func test_movesTowardTheTargetAndHandsOverOnArrival() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 100))
        let state = MoveToState()
        state.target = CGPoint(x: 30, y: 100)
        state.nextState = .point
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.body.position.x, 30, accuracy: MovementSolver.arrivalRadius)
        XCTAssertEqual(world.requestedTransitions, [.point])
    }

    func test_defaultsToIdleWhenNothingAskedForAFollowUp() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 100))
        let state = MoveToState()
        state.target = CGPoint(x: 20, y: 100)
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.requestedTransitions, [.idle])
    }

    func test_facesTheDirectionOfTravel() {
        let world = TestStateWorld(position: CGPoint(x: 400, y: 100))
        let state = MoveToState()
        state.target = CGPoint(x: 0, y: 100)
        state.enter()

        world.run(state, seconds: 0.2)

        XCTAssertEqual(world.avatar.facings.last, .left)
    }

    /// A tool sent the pet somewhere specific; stopping to climb a window on
    /// the way would abandon the order.
    func test_walksPastWindowsInsteadOfClimbingThem() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 500))
        world.windows = [
            WindowInfo(windowID: 1, ownerPID: 1, ownerName: nil, title: nil, layer: 0,
                       frame: CGRect(x: 300, y: 200, width: 400, height: 400))
        ]
        let state = MoveToState()
        state.target = CGPoint(x: 900, y: 500)
        state.enter()

        world.run(state, seconds: 12)

        XCTAssertFalse(world.requestedTransitions.contains(.climb))
        XCTAssertEqual(world.body.position.x, 900, accuracy: MovementSolver.arrivalRadius)
    }

    /// Settings' movement-speed slider.
    func test_respectsACustomWalkSpeed() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 100))
        world.walkSpeed = MovementSolver.walkSpeed * 2
        let state = MoveToState()
        state.target = CGPoint(x: 1000, y: 100)
        state.enter()

        world.run(state, seconds: 1)

        XCTAssertEqual(world.body.position.x, MovementSolver.walkSpeed * 2, accuracy: 1)
    }

    func test_withoutATarget_returnsToIdle() {
        let world = TestStateWorld()
        let state = MoveToState()
        state.enter()

        world.run(state, seconds: 0.1)

        XCTAssertEqual(world.requestedTransitions, [.idle])
    }

    func test_handsOverOnlyOnce() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 100))
        let state = MoveToState()
        state.target = CGPoint(x: 5, y: 100)
        state.nextState = .point
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.requestedTransitions.count, 1)
    }
}
