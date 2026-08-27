//
//  WindowPollPolicyTests.swift
//  PuckTests
//
//  Asking the system for the window list is most of what this app does at
//  rest. When it stops being worth asking, and when it starts again.
//

import XCTest
@testable import Puck

final class WindowPollPolicyTests: XCTestCase {
    private func policy(threshold: TimeInterval = 45) -> WindowPollPolicy {
        WindowPollPolicy(threshold: threshold)
    }

    /// A walking pet stands on window tops, and a window can be dragged
    /// without posting anything. It needs the full rate.
    func test_anythingHappeningPollsAtTheActiveRate() {
        var policy = policy()

        XCTAssertEqual(policy.hertz(resting: false, bursting: false, dt: 1), WindowPollPolicy.activeHz)
    }

    /// Resting is not immediately slow: a pet that sits down for a second
    /// between two walks would otherwise take the second one against a list
    /// it stopped watching.
    func test_restingDoesNotSlowDownImmediately() {
        var policy = policy(threshold: 45)

        XCTAssertEqual(policy.hertz(resting: true, bursting: false, dt: 10), WindowPollPolicy.activeHz)
        XCTAssertEqual(policy.hertz(resting: true, bursting: false, dt: 20), WindowPollPolicy.activeHz)
    }

    /// And then it does.
    func test_aLongRestSlowsDown() {
        var policy = policy(threshold: 45)

        _ = policy.hertz(resting: true, bursting: false, dt: 44)
        XCTAssertEqual(policy.hertz(resting: true, bursting: false, dt: 2), WindowPollPolicy.restingHz)
    }

    /// Straight back up, not ramped. The first step of a walk is the one case
    /// that matters, and it happens on the frame the pet stops resting.
    func test_movingAgainGoesStraightBackToTheActiveRate() {
        var policy = policy(threshold: 45)
        _ = policy.hertz(resting: true, bursting: false, dt: 100)
        XCTAssertEqual(policy.hertz(resting: true, bursting: false, dt: 0), WindowPollPolicy.restingHz)

        XCTAssertEqual(policy.hertz(resting: false, bursting: false, dt: 0.016), WindowPollPolicy.activeHz)
    }

    /// And it stays up: the rest that had already been served is not resumed
    /// where it left off.
    func test_theRestStartsOverAfterMoving() {
        var policy = policy(threshold: 45)
        _ = policy.hertz(resting: true, bursting: false, dt: 100)
        _ = policy.hertz(resting: false, bursting: false, dt: 0.016)

        XCTAssertEqual(policy.hertz(resting: true, bursting: false, dt: 10), WindowPollPolicy.activeHz)
    }

    /// An app launching or quitting is the window list changing right now,
    /// which outranks however long the pet has been sitting.
    func test_aBurstOutranksEvenALongRest() {
        var policy = policy(threshold: 45)
        _ = policy.hertz(resting: true, bursting: false, dt: 100)

        XCTAssertEqual(policy.hertz(resting: true, bursting: true, dt: 0.016), WindowPollPolicy.burstHz)
    }

    /// The resting rate is a slow-down, not a stop: a window moved under a
    /// sleeping pet still has to be noticed eventually.
    func test_theRestingRateIsNotZero() {
        XCTAssertGreaterThan(WindowPollPolicy.restingHz, 0)
        XCTAssertLessThan(WindowPollPolicy.restingHz, WindowPollPolicy.activeHz)
    }
    /// The same trap the frame-rate policy fell into: a threshold longer than
    /// the pet's own rests means the slow rate is never reached.
    func test_theThresholdIsShorterThanTheRestsThePetActuallyTakes() {
        XCTAssertLessThan(
            WindowPollPolicy().threshold,
            WanderScheduler.defaultIntervalRange.lowerBound
        )
    }

}
