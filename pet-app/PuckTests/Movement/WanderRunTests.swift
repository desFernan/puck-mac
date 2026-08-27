//
//  WanderRunTests.swift
//  PuckTests
//
//  A wander is several walks with a beat between them. Nothing reports an
//  arrival, so the beat is counted down a frame at a time -- and the one
//  thing worth being sure of is that a wander with two legs left walks
//  twice and then stops.
//

import XCTest
@testable import Puck

final class WanderRunTests: XCTestCase {
    /// Ticking the whole pause away starts a leg, and only then.
    func test_aLegStartsWhenTheBeatRunsOut() {
        var run = WanderRun()
        run.begin(atHome: false)
        guard run.isRunning else { return }        // a one-leg draw has none left

        let pause = run.pause
        XCTAssertFalse(run.tick(dt: pause / 2), "half the beat is not the beat")
        XCTAssertTrue(run.tick(dt: pause), "and the rest of it is")
    }

    /// It walks exactly the legs it drew and then stops. A countdown that
    /// never reached zero would leave the pet wandering for the life of the
    /// app; one that undershot would make a wander a single trip.
    func test_itWalksTheLegsItDrewAndThenStops() {
        var run = WanderRun()
        run.begin(atHome: true)
        let drawn = run.legsRemaining

        var walked = 0
        for _ in 0..<10_000 where run.isRunning {
            if run.tick(dt: 0.016) { walked += 1 }
        }

        XCTAssertEqual(walked, drawn)
        XCTAssertFalse(run.isRunning)
    }

    /// Anything that takes the pet over cancels, or it resumes a walk nobody
    /// asked for any more.
    func test_cancellingDropsWhateverIsLeft() {
        var run = WanderRun()
        run.begin(atHome: true)

        run.cancel()

        XCTAssertFalse(run.isRunning)
        XCTAssertFalse(run.tick(dt: 100), "and a tick afterwards starts nothing")
    }

    /// A run that has not begun does nothing, however long the frame was.
    func test_aRunThatNeverBeganStartsNothing() {
        var run = WanderRun()

        XCTAssertFalse(run.isRunning)
        XCTAssertFalse(run.tick(dt: 100))
    }

    /// The draw is a roll, so it is passed in here rather than taken -- the
    /// island walks further per wander because one leg of a 90pt shelf is
    /// barely a step.
    func test_theIslandDrawsMoreLegsThanTheDesktop() {
        for roll in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertGreaterThan(
                WanderRun.drawLegs(atHome: true, roll: CGFloat(roll)),
                WanderRun.drawLegs(atHome: false, roll: CGFloat(roll)),
                "at roll \(roll)"
            )
        }
    }
}
