//
//  FrameClockTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The Timer half — that starting the clock actually delivers ticks on the
//  main run loop, and that stopping it stops them. Timing bounds are
//  deliberately loose; the exact dt arithmetic is FrameTickerTests' job.
//

import XCTest
@testable import Puck

/// `@MainActor`: the type under test is, being a timer on the main run
/// loop and the state it drives.
@MainActor
final class FrameClockTests: XCTestCase {
    func test_start_deliversRepeatedTicksWithPositiveDeltas() {
        let clock = FrameClock(framesPerSecond: 60)

        var deltas: [TimeInterval] = []
        let gotEnoughTicks = expectation(description: "clock ticked repeatedly")
        gotEnoughTicks.expectedFulfillmentCount = 5
        clock.onTick = { dt in
            deltas.append(dt)
            gotEnoughTicks.fulfill()
        }

        clock.start()
        wait(for: [gotEnoughTicks], timeout: 3)
        clock.stop()

        XCTAssertTrue(deltas.allSatisfy { $0 > 0 }, "every frame must report a positive dt: \(deltas)")
        XCTAssertTrue(deltas.allSatisfy { $0 <= FrameTicker().maxDelta }, "dt must stay clamped: \(deltas)")
    }

    func test_stop_endsTickDelivery() {
        let clock = FrameClock(framesPerSecond: 60)

        var tickCount = 0
        clock.onTick = { _ in tickCount += 1 }
        clock.start()

        let ticked = expectation(description: "clock started ticking")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ticked.fulfill() }
        wait(for: [ticked], timeout: 2)
        clock.stop()

        let countAtStop = tickCount
        XCTAssertGreaterThan(countAtStop, 0, "precondition: the clock should have been running")

        let settled = expectation(description: "waited past several would-be frames")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        XCTAssertEqual(tickCount, countAtStop, "ticks continued after stop()")
    }

    func test_setFramesPerSecond_isIgnoredForNonPositiveRates() {
        let clock = FrameClock(framesPerSecond: 60)

        clock.setFramesPerSecond(0)
        XCTAssertEqual(clock.framesPerSecond, 60)

        clock.setFramesPerSecond(FrameClock.idleFramesPerSecond)
        XCTAssertEqual(clock.framesPerSecond, FrameClock.idleFramesPerSecond)
    }

    /// The 2D target band (F1, post-RealityKit): 15-30 updates per second.
    /// Asserted as literals rather than through the constants, because the
    /// other tests here compare a constant to itself and would pass at any
    /// value -- which is how 60fps survived the 3D removal unnoticed.
    func test_rateConstants_areWithinThe2DTargetBand() {
        XCTAssertEqual(FrameClock.activeFramesPerSecond, 30, "active rate should cap at the 2D target's ceiling")
        XCTAssertEqual(FrameClock.idleFramesPerSecond, 15, "idle rate should sit at the 2D target's floor")

        for rate in [FrameClock.activeFramesPerSecond, FrameClock.idleFramesPerSecond] {
            XCTAssertGreaterThanOrEqual(rate, 15, "below the band the pet's motion visibly steps")
            XCTAssertLessThanOrEqual(rate, 30, "above the band is 3D-era headroom nothing needs now")
        }
    }

    /// A frame is the unit dt is clamped against, so the clamp has to stay
    /// comfortably above the slowest frame interval or every idle frame would
    /// arrive pre-clamped and time would be silently discarded.
    func test_maxDelta_staysAboveTheSlowestFrameInterval() {
        XCTAssertGreaterThan(FrameTicker().maxDelta, 1.0 / FrameClock.idleFramesPerSecond)
    }

    func test_defaultRate_isTheActiveRate() {
        XCTAssertEqual(FrameClock().framesPerSecond, FrameClock.activeFramesPerSecond)
    }
}
