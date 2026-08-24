//
//  LaunchAppActivationTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Bringing a launched app to the front. The retry exists because a cold-launched app
//  has no windows to raise for a moment -- so what has to be pinned is that it
//  keeps trying, and that it stops.
//

import XCTest
@testable import Puck

final class LaunchAppActivationTests: XCTestCase {
    private final class StubApp: ActivatableApp {
        var isTerminated = false
        var isActive = false
        private(set) var activateCount = 0
        /// Set to have the app "come forward" after N activations.
        var becomesActiveAfter: Int?

        func activateAllWindows() {
            activateCount += 1
            if let becomesActiveAfter, activateCount >= becomesActiveAfter { isActive = true }
        }
    }

    /// Runs scheduled work immediately, so the retry doesn't need a real clock.
    private func handler() -> LaunchAppHandler {
        let handler = LaunchAppHandler()
        handler.scheduleAfter = { _, work in work() }
        return handler
    }

    func test_keepsTryingUntilTheAppIsActuallyActive() {
        let app = StubApp()
        app.becomesActiveAfter = 3

        handler().bringToFront(app)

        XCTAssertEqual(app.activateCount, 3, "should stop as soon as the app reports itself active")
        XCTAssertTrue(app.isActive)
    }

    /// An app that never activates must not retry forever -- with an
    /// immediate scheduler an unbounded loop is an infinite one.
    func test_givesUpAfterABoundedNumberOfAttempts() {
        let app = StubApp() // never becomes active

        handler().bringToFront(app, attemptsRemaining: 4)

        XCTAssertEqual(app.activateCount, 4)
    }

    func test_alreadyFrontmostAppIsLeftAlone() {
        let app = StubApp()
        app.isActive = true

        handler().bringToFront(app)

        XCTAssertEqual(app.activateCount, 0, "no reason to activate what is already in front")
    }

    /// The user can quit an app between the launch and the retry; activating a
    /// dead process would relaunch nothing and log noise.
    func test_stopsWhenTheAppHasQuit() {
        let app = StubApp()
        app.isTerminated = true

        handler().bringToFront(app)

        XCTAssertEqual(app.activateCount, 0)
    }

    /// The pet has to get the stage to itself first, or the window arriving
    /// at the same instant reads as the app opening on its own.
    func test_theFirstActivationWaitsLongerThanTheRetries() {
        let app = StubApp()
        let handler = LaunchAppHandler()
        var delays: [TimeInterval] = []
        handler.scheduleAfter = { delay, work in
            delays.append(delay)
            work()
        }

        handler.bringToFront(app, attemptsRemaining: 10)

        XCTAssertEqual(delays.first, LaunchAppHandler.activationLeadIn)
        XCTAssertTrue(
            delays.dropFirst().allSatisfy { $0 == LaunchAppHandler.activationRetryInterval },
            "only the first attempt gets the lead-in; retries should be quick"
        )
        XCTAssertGreaterThan(
            LaunchAppHandler.activationLeadIn,
            LaunchAppHandler.activationRetryInterval,
            "the lead-in has to actually be a pause"
        )
    }

    func test_stopsIfTheAppQuitsPartWayThroughTheRetries() {
        let app = StubApp()
        let handler = handler()
        // Terminates itself on the second activation attempt.
        var attempts = 0
        handler.scheduleAfter = { _, work in
            attempts += 1
            if attempts == 2 { app.isTerminated = true }
            work()
        }

        handler.bringToFront(app)

        XCTAssertEqual(app.activateCount, 1)
    }
}
