//
//  BallStatesTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  "Idle/Walk 한정 | 공 던지기(F12) | ChaseBall → JuggleBall → KickBall → Idle"
//  (optional ball-toy interaction; JuggleBall
//  added 2026-07-29 for more motion variety on the same interaction).
//

import XCTest
@testable import Puck

/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class ChaseBallStateTests: XCTestCase {
    func test_movesTowardTheBallAndRequestsJuggleOnArrival() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 100))
        let state = ChaseBallState()
        state.target = CGPoint(x: 30, y: 100)
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.body.position.x, 30, accuracy: MovementSolver.arrivalRadius)
        XCTAssertEqual(world.requestedTransitions, [.juggleBall])
    }

    func test_ignoresWindowsInTheWay_likeMoveTo() {
        let world = TestStateWorld(position: CGPoint(x: 100, y: 500))
        world.windows = [
            WindowInfo(windowID: 1, ownerPID: 1, ownerName: nil, title: nil, layer: 0,
                       frame: CGRect(x: 300, y: 200, width: 400, height: 400))
        ]
        let state = ChaseBallState()
        state.target = CGPoint(x: 900, y: 500)
        state.enter()

        world.run(state, seconds: 12)

        XCTAssertFalse(world.requestedTransitions.contains(.climb))
        XCTAssertEqual(world.body.position.x, 900, accuracy: MovementSolver.arrivalRadius)
    }

    func test_withoutATarget_requestsIdleInstead() {
        let world = TestStateWorld()
        let state = ChaseBallState()
        state.enter()

        world.run(state, seconds: 0.1)

        XCTAssertEqual(world.requestedTransitions, [.idle])
    }

    func test_handsOverOnlyOnce() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 100))
        let state = ChaseBallState()
        state.target = CGPoint(x: 5, y: 100)
        state.enter()

        world.run(state, seconds: 3)

        XCTAssertEqual(world.requestedTransitions.count, 1)
    }

    /// Settings' movement-speed slider.
    func test_respectsACustomWalkSpeed() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 100))
        world.walkSpeed = MovementSolver.walkSpeed * 2
        let state = ChaseBallState()
        state.target = CGPoint(x: 1000, y: 100)
        state.enter()

        world.run(state, seconds: 1)

        XCTAssertEqual(world.body.position.x, MovementSolver.walkSpeed * 2, accuracy: 1)
    }
}

/// Playing with the toy overhead: catch, throw, repeat -- then get bored and
/// throw it away after a while.
/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class JuggleBallStateTests: XCTestCase {
    /// Runs one full catch-and-throw round, returning the throws it caused.
    private func playRound(_ state: JuggleBallState, in world: TestStateWorld) {
        state.caught()
        world.run(state, seconds: JuggleBallState.holdTime + 0.02)
    }

    func test_throwsOnceOnEntry() {
        let state = JuggleBallState()
        var throwCount = 0
        state.onThrow = { throwCount += 1 }

        state.enter()

        XCTAssertEqual(throwCount, 1)
    }

    /// The catch is a pause, not a bounce: nothing is thrown at the instant
    /// the toy arrives.
    func test_catchingDoesNotThrowImmediately() {
        let world = TestStateWorld()
        let state = JuggleBallState()
        state.enter()
        var throwCount = 0
        state.onThrow = { throwCount += 1 }

        state.caught()
        world.run(state, seconds: JuggleBallState.holdTime * 0.5)

        XCTAssertEqual(throwCount, 0, "the toy should still be sitting on the pet's head")
    }

    func test_throwsAgainAfterHoldingTheCaughtToy() {
        let world = TestStateWorld()
        let state = JuggleBallState()
        state.enter()
        var throwCount = 0
        state.onThrow = { throwCount += 1 }

        playRound(state, in: world)

        XCTAssertEqual(throwCount, 1)
    }

    func test_keepsPlayingForItsWholePlayDuration() {
        let world = TestStateWorld()
        let state = JuggleBallState()
        state.enter()
        var throwCount = 0
        state.onThrow = { throwCount += 1 }

        // Rounds well inside the play duration.
        for _ in 0..<4 {
            playRound(state, in: world)
            world.run(state, seconds: 0.3) // the toy's arc
        }

        XCTAssertGreaterThanOrEqual(throwCount, 4)
        XCTAssertTrue(world.requestedTransitions.isEmpty, "gave up while still meant to be playing")
    }

    /// Bored: the final throw is a proper throw-away (KickBall), and it
    /// happens from the hand -- on a catch, not by snatching the toy out of
    /// the air mid-arc.
    func test_onceBoredItThrowsTheToyAwayOnTheNextCatch() {
        let world = TestStateWorld()
        let state = JuggleBallState()
        state.enter()

        // Keep playing -- catching each time -- until it's had enough.
        var played: TimeInterval = 0
        while played < JuggleBallState.playDuration {
            playRound(state, in: world)
            world.run(state, seconds: 0.4) // the toy's arc
            played += JuggleBallState.holdTime + 0.42
            XCTAssertTrue(world.requestedTransitions.isEmpty, "gave up early, at \(played)s")
        }

        // Bored now, but still mid-air: it must wait for the toy in hand.
        XCTAssertEqual(world.requestedTransitions, [], "must not bail out mid-air")

        playRound(state, in: world)

        XCTAssertEqual(world.requestedTransitions, [.kickBall])
    }

    /// A toy that never comes back -- picked up by the cursor, knocked away --
    /// ends play without a throw-away, since there is nothing in hand.
    func test_givesUpWhenTheToyNeverComesBack() {
        let world = TestStateWorld()
        let state = JuggleBallState()
        state.enter()

        world.run(state, seconds: JuggleBallState.patience + 0.1)

        XCTAssertEqual(world.requestedTransitions, [.idle])
    }

    func test_aCatchResetsTheGiveUpTimer() {
        let world = TestStateWorld()
        let state = JuggleBallState()
        state.enter()

        world.run(state, seconds: JuggleBallState.patience * 0.9)
        playRound(state, in: world) // caught and thrown again
        world.run(state, seconds: JuggleBallState.patience * 0.9)

        XCTAssertTrue(world.requestedTransitions.isEmpty, "the catch should have reset the wait")
    }

    func test_endsOnlyOnce() {
        let world = TestStateWorld()
        let state = JuggleBallState()
        state.enter()

        world.run(state, seconds: JuggleBallState.patience + 5)

        XCTAssertEqual(world.requestedTransitions.count, 1)
    }
}

/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class KickBallStateTests: XCTestCase {
    func test_firesOnEnterOnceWhenEntered() {
        let state = KickBallState()
        var kickCount = 0
        state.onEnter = { kickCount += 1 }

        state.enter()

        XCTAssertEqual(kickCount, 1)
    }

    func test_returnsToIdleAfterTheKickPlays() {
        let world = TestStateWorld()
        let state = KickBallState()
        state.enter()

        world.run(state, seconds: 0.05)
        XCTAssertTrue(world.requestedTransitions.isEmpty, "the kick clip needs a moment to read")

        world.run(state, seconds: 2)
        XCTAssertEqual(world.requestedTransitions, [.idle])
    }
}

/// A spin-style toy is played with differently but for the same length of
/// time.
/// `@MainActor`: what it exercises belongs to the main thread -- the
/// character, its states, or a view that draws them.
@MainActor
final class JuggleBallSpinStyleTests: XCTestCase {
    private func spinning() -> JuggleBallState {
        let state = JuggleBallState()
        state.style = .spinOverhead
        return state
    }

    /// Nothing is thrown: the toy never leaves the pet.
    func test_aSpinToyIsNeverThrownUp() {
        let state = spinning()
        var throwCount = 0
        state.onThrow = { throwCount += 1 }

        state.enter()

        XCTAssertEqual(throwCount, 0)
    }

    /// And with nothing in the air, the "it never came back" timeout must not
    /// cut play short -- that's the failure this style would fall into if it
    /// shared the throw-and-catch path.
    func test_aSpinToyIsNotEndedByThePatienceTimeout() {
        let world = TestStateWorld()
        let state = spinning()
        state.enter()

        world.run(state, seconds: JuggleBallState.patience + 0.5)

        XCTAssertTrue(world.requestedTransitions.isEmpty, "gave up on a toy that never left")
    }

    func test_aSpinToyEndsAfterThePlayDuration() {
        let world = TestStateWorld()
        let state = spinning()
        state.enter()

        world.run(state, seconds: JuggleBallState.playDuration - 0.2)
        XCTAssertTrue(world.requestedTransitions.isEmpty, "stopped early")

        world.run(state, seconds: 0.4)
        XCTAssertEqual(world.requestedTransitions, [.kickBall], "should put it down the same way")
    }

    func test_aSpinToyEndsOnlyOnce() {
        let world = TestStateWorld()
        let state = spinning()
        state.enter()

        world.run(state, seconds: JuggleBallState.playDuration + 3)

        XCTAssertEqual(world.requestedTransitions.count, 1)
    }
}
