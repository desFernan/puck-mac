//
//  FrameTickerTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The pure dt-computation half of the frame loop. FrameClock (Timer + this)
//  is the thin untested layer, same split as WindowListWatcher.filter vs
//  fetchRawWindowList.
//

import XCTest
@testable import Puck

final class FrameTickerTests: XCTestCase {
    func test_firstSample_producesNoDelta() {
        var ticker = FrameTicker()
        XCTAssertNil(ticker.delta(now: 100), "there is no previous frame to measure against")
    }

    func test_subsequentSamples_produceElapsedTime() throws {
        var ticker = FrameTicker()
        _ = ticker.delta(now: 100)

        // Realistic frame spacing: 60fps and 15fps, both well under maxDelta.
        let sixtyHz = try XCTUnwrap(ticker.delta(now: 100 + 1.0 / 60))
        XCTAssertEqual(sixtyHz, 1.0 / 60, accuracy: 0.0001)

        let fifteenHz = try XCTUnwrap(ticker.delta(now: 100 + 1.0 / 60 + 1.0 / 15))
        XCTAssertEqual(fifteenHz, 1.0 / 15, accuracy: 0.0001)
    }

    /// systemUptime does not advance while the machine sleeps, but a stalled
    /// run loop (modal tracking, a long synchronous load) still produces a
    /// large gap. Feeding that straight into the FSM would advance a
    /// constant-velocity MoveTo by hundreds of pixels in one step and fire
    /// every wander timer at once, so a frame is clamped to a sane maximum.
    func test_longStall_isClampedToMaxDelta() {
        var ticker = FrameTicker(maxDelta: 0.25)
        _ = ticker.delta(now: 100)

        XCTAssertEqual(ticker.delta(now: 400), 0.25)
    }

    func test_clampedFrame_doesNotAccumulateTheDiscardedTime() throws {
        var ticker = FrameTicker(maxDelta: 0.25)
        _ = ticker.delta(now: 100)
        _ = ticker.delta(now: 400) // clamped

        // The next frame measures from 400, not from the clamped 100.25.
        let delta = try XCTUnwrap(ticker.delta(now: 400.1))
        XCTAssertEqual(delta, 0.1, accuracy: 0.0001)
    }

    func test_nonMonotonicSample_producesNoDelta() {
        var ticker = FrameTicker()
        _ = ticker.delta(now: 100)

        XCTAssertNil(ticker.delta(now: 99), "time going backwards must not produce a negative dt")
    }

    func test_reset_startsMeasuringAfresh() {
        var ticker = FrameTicker()
        _ = ticker.delta(now: 100)
        ticker.reset()

        XCTAssertNil(ticker.delta(now: 200), "after reset the next sample is a first sample again")
    }
}
